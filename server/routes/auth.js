const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();

const USERS_FILE = path.join(__dirname, '../data/users.json');

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

function saveUsers(users) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
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
    return res.json({ success: false, message: 'Username atau password salah.' });
  }

  req.session.regenerate((err) => {
    if (err) return res.status(500).json({ success: false, message: 'Session error' });

    req.session.user = {
      id: user.id,
      username: user.username,
      role: user.role,
      displayName: user.displayName,
      port: user.port,
      projects: user.projects || []
    };

    res.json({
      success: true,
      role: user.role,
      redirect: user.role === 'admin' ? '/admin' : '/dashboard'
    });
  });
});

router.post('/logout', (req, res) => {
  req.session.destroy(() => {
    res.clearCookie('devplatform.sid');
    res.json({ success: true });
  });
});

router.post('/change-password', (req, res) => {
  if (!req.session.user) return res.status(401).json({ success: false });

  const { oldPassword, newPassword } = req.body;
  const users = getUsers();
  const idx = users.findIndex(u => u.id === req.session.user.id);

  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });
  if (!bcrypt.compareSync(oldPassword, users[idx].password)) {
    return res.json({ success: false, message: 'Password lama salah.' });
  }
  if (!newPassword || newPassword.length < 8) {
    return res.json({ success: false, message: 'Password baru minimal 8 karakter.' });
  }

  users[idx].password = bcrypt.hashSync(newPassword, 10);
  saveUsers(users);
  res.json({ success: true, message: 'Password berhasil diubah.' });
});

router.post('/change-email', (req, res) => {
  if (!req.session.user) return res.status(401).json({ success: false });

  const { email, password } = req.body;
  if (!isValidEmail(email)) {
    return res.json({ success: false, message: 'Format email tidak valid.' });
  }

  const users = getUsers();
  const idx = users.findIndex(u => u.id === req.session.user.id);

  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });
  if (!bcrypt.compareSync(password || '', users[idx].password)) {
    return res.json({ success: false, message: 'Password salah.' });
  }

  users[idx].email = email || '';
  saveUsers(users);
  res.json({ success: true, message: 'Email berhasil diubah.' });
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
      role: user.role
    }
  });
});

module.exports = router;
