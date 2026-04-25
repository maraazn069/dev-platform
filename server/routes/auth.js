const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();
const { validateStrong } = require('../services/passwordPolicy');
const audit = require('../services/auditLog');
const userManager = require('../services/userManager');

const USERS_FILE = path.join(__dirname, '../data/users.json');

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

function isValidEmail(email) {
  if (!email) return true;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

router.post('/login', (req, res) => {
  const { username, password } = req.body;
  if (!username || !password) {
    return res.json({ success: false, message: 'Username dan password wajib diisi.' });
  }

  const users = getUsers();
  const user = users.find(u => u.username === username);

  if (!user || !bcrypt.compareSync(password, user.password)) {
    audit.log('login.failed', { attempted: username }, req);
    return res.json({ success: false, message: 'Username atau password salah.' });
  }

  if (user.deletionPending) {
    audit.log('login.blocked_deletion_pending', { username }, req);
    return res.json({ success: false, message: 'Akun ini sedang ditangguhkan, hubungi admin.' });
  }

  req.session.regenerate((err) => {
    if (err) return res.status(500).json({ success: false, message: 'Session error' });

    req.session.user = {
      id: user.id,
      username: user.username,
      role: user.role,
      displayName: user.displayName,
      port: user.port,
      projects: user.projects || [],
      mustChangePassword: !!user.mustChangePassword
    };

    audit.log('login.success', { username, role: user.role, mustChange: !!user.mustChangePassword }, req);

    let redirect;
    if (user.mustChangePassword) redirect = '/change-password-required';
    else if (user.role === 'admin') redirect = '/admin';
    else redirect = '/dashboard';

    res.json({ success: true, role: user.role, mustChangePassword: !!user.mustChangePassword, redirect });
  });
});

router.post('/logout', (req, res) => {
  const username = req.session?.user?.username;
  audit.log('logout', { username }, req);
  req.session.destroy(() => {
    res.clearCookie('devplatform.sid');
    res.json({ success: true });
  });
});

router.post('/change-password', async (req, res) => {
  if (!req.session.user) return res.status(401).json({ success: false });

  const { oldPassword, newPassword } = req.body;

  // Validate dulu (cheap check) sebelum acquire lock
  if (oldPassword === newPassword) {
    return res.json({ success: false, message: 'Password baru tidak boleh sama dengan password lama.' });
  }

  try {
    const result = await userManager.updateUsers((users) => {
      const idx = users.findIndex(u => u.id === req.session.user.id);
      if (idx === -1) return { ok: false, status: 404, message: 'User tidak ditemukan.' };
      if (!bcrypt.compareSync(oldPassword || '', users[idx].password)) {
        return { ok: false, message: 'Password lama salah.', auditEvent: 'password.change_failed_wrong_old', user: users[idx] };
      }
      const policy = validateStrong(newPassword, users[idx].username);
      if (!policy.ok) return { ok: false, message: policy.message };

      users[idx].password = bcrypt.hashSync(newPassword, 12);
      users[idx].mustChangePassword = false;
      users[idx].passwordChangedAt = new Date().toISOString();
      return { ok: true, user: users[idx] };
    });

    if (!result.ok) {
      if (result.auditEvent) audit.log(result.auditEvent, { username: result.user?.username }, req);
      if (result.status === 404) return res.status(404).json({ success: false, message: result.message });
      return res.json({ success: false, message: result.message });
    }

    req.session.user.mustChangePassword = false;
    audit.log('password.changed', { username: result.user.username }, req);

    if (result.user.role === 'admin') {
      const { syncAdminPassword } = require('../services/credentialSync');
      syncAdminPassword({
        username: result.user.username,
        email: result.user.email,
        password: newPassword
      }).then((r) => {
        audit.log('password.sync_admin', {
          username: result.user.username,
          filebrowser: r.filebrowser?.ok ? 'ok' : (r.filebrowser?.message || 'failed'),
          pgadmin: r.pgadmin?.ok ? 'ok' : (r.pgadmin?.message || 'failed'),
          env: r.env?.ok ? 'ok' : (r.env?.message || 'failed')
        }, req);
      }).catch((e) => audit.log('password.sync_admin_error', { error: e.message }, req));
    }

    res.json({
      success: true,
      message: result.user.role === 'admin'
        ? 'Password berhasil diubah. File Browser & pgAdmin sedang di-sync di latar belakang (cek audit log).'
        : 'Password berhasil diubah.'
    });
  } catch (e) {
    res.status(500).json({ success: false, message: 'Gagal ubah password: ' + e.message });
  }
});

router.post('/change-email', async (req, res) => {
  if (!req.session.user) return res.status(401).json({ success: false });
  if (req.session.user.mustChangePassword) {
    return res.status(423).json({ success: false, message: 'Ganti password dulu sebelum aksi lain.' });
  }

  const { email, password } = req.body;
  if (!isValidEmail(email)) {
    return res.json({ success: false, message: 'Format email tidak valid.' });
  }

  try {
    const result = await userManager.updateUsers((users) => {
      const idx = users.findIndex(u => u.id === req.session.user.id);
      if (idx === -1) return { ok: false, message: 'User tidak ditemukan.' };
      if (!bcrypt.compareSync(password || '', users[idx].password)) {
        return { ok: false, message: 'Password salah.' };
      }
      users[idx].email = email || '';
      return { ok: true, username: users[idx].username };
    });
    if (!result.ok) return res.json({ success: false, message: result.message });
    audit.log('email.changed', { username: result.username, email }, req);
    res.json({ success: true, message: 'Email berhasil diubah.' });
  } catch (e) {
    res.status(500).json({ success: false, message: 'Gagal ubah email: ' + e.message });
  }
});

router.get('/me', (req, res) => {
  if (!req.session.user) return res.status(401).json({ success: false });
  const users = getUsers();
  const user = users.find(u => u.id === req.session.user.id);
  if (!user) return res.status(404).json({ success: false });

  res.json({
    success: true,
    user: {
      username: user.username,
      email: user.email || '',
      displayName: user.displayName,
      role: user.role,
      mustChangePassword: !!user.mustChangePassword
    }
  });
});

module.exports = router;
