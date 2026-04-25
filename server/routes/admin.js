const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();
const userManager = require('../services/userManager');

const USERS_FILE = path.join(__dirname, '../data/users.json');

function requireAdmin(req, res, next) {
  if (!req.session || !req.session.user) return res.redirect('/login');
  if (req.session.user.role !== 'admin') return res.redirect('/dashboard');
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

router.get('/users', requireAdmin, (req, res) => {
  const users = getUsers().map(u => ({
    id: u.id,
    username: u.username,
    displayName: u.displayName,
    role: u.role,
    port: u.port,
    projects: u.projects || [],
    databases: u.databases || [],
    hasDbCredentials: !!(u.mysqlPassword && u.pgPassword),
    createdAt: u.createdAt
  }));
  res.json({ users });
});

router.post('/users/add', requireAdmin, (req, res) => {
  const { username, displayName, password, email } = req.body;
  if (!username || !password) {
    return res.json({ success: false, message: 'Username dan password wajib diisi.' });
  }
  if (password.length < 6) {
    return res.json({ success: false, message: 'Password minimal 6 karakter.' });
  }

  const result = userManager.provisionUser({ username, password, displayName, email });
  res.json(result);
});

router.post('/users/remove', requireAdmin, (req, res) => {
  const { username } = req.body;
  const result = userManager.removeUser(username);
  res.json(result);
});

router.post('/users/reset-password', requireAdmin, (req, res) => {
  const { username, newPassword } = req.body;
  if (!newPassword || newPassword.length < 6) {
    return res.json({ success: false, message: 'Password minimal 6 karakter.' });
  }
  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);
  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });

  users[idx].password = bcrypt.hashSync(newPassword, 10);
  saveUsers(users);
  res.json({ success: true, message: `Password '${username}' direset.` });
});

router.post('/users/repair-db', requireAdmin, (req, res) => {
  const { username } = req.body;
  const result = userManager.repairUserCredentials(username);
  res.json(result);
});

router.get('/users/:username/credentials', requireAdmin, (req, res) => {
  const creds = userManager.getCredentials(req.params.username);
  if (!creds) return res.status(404).json({ success: false, message: 'User tidak ditemukan.' });
  res.json({ success: true, ...creds });
});

// Admin-only endpoint untuk dapat pgAdmin shared admin login (untuk dishare ke user secara privat)
router.get('/pgadmin-credentials', requireAdmin, (req, res) => {
  res.json({
    success: true,
    email: process.env.PGADMIN_EMAIL || '(belum di-set)',
    password: process.env.PGADMIN_PASSWORD || '(belum di-set)',
    note: 'Bagikan ke user secara privat (chat/password manager). JANGAN tampilkan di halaman publik — siapapun yang punya admin pgAdmin bisa lihat koneksi semua user.'
  });
});

router.post('/users/add-project', requireAdmin, (req, res) => {
  const { username, projectName } = req.body;
  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);
  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });

  const cleanName = projectName.toLowerCase().replace(/[^a-z0-9-]/g, '-');
  if (users[idx].projects.includes(cleanName)) {
    return res.json({ success: false, message: 'Nama project sudah ada.' });
  }

  // Buat folder project
  try {
    fs.mkdirSync(`/opt/devplatform/data/${username}/projects/${cleanName}`, { recursive: true });
  } catch (e) { /* ignore */ }

  users[idx].projects.push(cleanName);
  saveUsers(users);

  res.json({ success: true, message: `Project '${cleanName}' ditambahkan ke user '${username}'.` });
});

module.exports = router;
