const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();
const userManager = require('../services/userManager');
const { validateStrong } = require('../services/passwordPolicy');
const audit = require('../services/auditLog');

const USERS_FILE = path.join(__dirname, '../data/users.json');

function requireAdmin(req, res, next) {
  if (!req.session || !req.session.user) return res.redirect('/login');
  if (req.session.user.mustChangePassword) return res.redirect('/change-password-required');
  if (req.session.user.role !== 'admin') return res.redirect('/dashboard');
  next();
}

function requireAdminApi(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  if (req.session.user.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });
  if (req.session.user.mustChangePassword) return res.status(423).json({ error: 'must_change_password' });
  next();
}

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

function saveUsers(users) {
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
}

router.get('/', requireAdmin, (req, res) => {
  res.sendFile(path.join(__dirname, '../../public/admin.html'));
});

router.get('/users', requireAdminApi, (req, res) => {
  const users = getUsers().map(u => ({
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    role: u.role,
    port: u.port,
    projects: u.projects || [],
    databases: u.databases || [],
    hasDbCredentials: !!(u.mysqlPassword && u.pgPassword),
    mustChangePassword: !!u.mustChangePassword,
    deletionPending: !!u.deletionPending,
    createdAt: u.createdAt
  }));
  res.json({ users });
});

router.post('/users/add', requireAdminApi, (req, res) => {
  const { username, displayName, password, email } = req.body;
  if (!username || !password) {
    return res.json({ success: false, message: 'Username dan password wajib diisi.' });
  }
  const policy = validateStrong(password, username);
  if (!policy.ok) return res.json({ success: false, message: policy.message });

  const result = userManager.provisionUser({ username, password, displayName, email });
  audit.log('user.add', { target: username, success: result.success }, req);
  res.json(result);
});

router.post('/users/remove', requireAdminApi, (req, res) => {
  const { username, confirm } = req.body;
  if (confirm !== username) {
    return res.json({ success: false, message: `Konfirmasi: ketik tepat "${username}".` });
  }
  const result = userManager.removeUser(username);
  audit.log('user.remove', { target: username, success: result.success, warnings: result.warnings }, req);
  res.json(result);
});

router.post('/users/reset-password', requireAdminApi, (req, res) => {
  const { username, newPassword, forceChange } = req.body;
  const policy = validateStrong(newPassword, username);
  if (!policy.ok) return res.json({ success: false, message: policy.message });

  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);
  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });

  users[idx].password = bcrypt.hashSync(newPassword, 12);
  if (forceChange !== false) users[idx].mustChangePassword = true;
  users[idx].passwordChangedAt = new Date().toISOString();
  saveUsers(users);
  audit.log('user.password_reset', { target: username, forceChange: forceChange !== false }, req);
  res.json({ success: true, message: `Password '${username}' direset. User wajib ganti saat login.` });
});

router.post('/users/repair-db', requireAdminApi, (req, res) => {
  const { username } = req.body;
  const result = userManager.repairUserCredentials(username);
  audit.log('user.repair_db', { target: username, success: result.success }, req);
  res.json(result);
});

router.get('/users/:username/credentials', requireAdminApi, (req, res) => {
  const creds = userManager.getCredentials(req.params.username);
  if (!creds) return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
  audit.log('user.view_credentials', { target: req.params.username }, req);
  res.json({ success: true, ...creds });
});

router.get('/pgadmin-credentials', requireAdminApi, (req, res) => {
  audit.log('pgadmin.view_admin_creds', {}, req);
  res.json({
    success: true,
    email: process.env.PGADMIN_EMAIL || '(belum di-set)',
    password: process.env.PGADMIN_PASSWORD || '(belum di-set)',
    note: 'Bagikan ke user secara privat (chat/password manager). JANGAN tampilkan di halaman publik — siapapun yang punya admin pgAdmin bisa lihat koneksi semua user.'
  });
});

// Audit log viewer
router.get('/audit', requireAdminApi, (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 200, 1000);
  res.json({ entries: audit.tail(limit) });
});

module.exports = router;
