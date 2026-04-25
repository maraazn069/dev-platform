const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

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
    createdAt: u.createdAt
  }));
  res.json({ users });
});

router.post('/users/add', requireAdmin, (req, res) => {
  const { username, displayName, password } = req.body;

  if (!username || !password) {
    return res.json({ success: false, message: 'Username dan password wajib diisi.' });
  }
  if (!/^[a-z][a-z0-9]{1,15}$/.test(username)) {
    return res.json({ success: false, message: 'Username hanya huruf kecil dan angka, 2-16 karakter.' });
  }

  const users = getUsers();
  if (users.find(u => u.username === username)) {
    return res.json({ success: false, message: `Username '${username}' sudah ada.` });
  }

  const port = 8081 + users.filter(u => u.role !== 'admin').length;
  const newUser = {
    id: uuidv4(),
    username,
    password: bcrypt.hashSync(password, 10),
    role: 'user',
    displayName: displayName || username,
    port,
    projects: ['default'],
    createdAt: new Date().toISOString()
  };

  users.push(newUser);
  saveUsers(users);

  res.json({
    success: true,
    message: `User '${username}' berhasil ditambah.`,
    user: { username, displayName: newUser.displayName, port },
    shellCommand: `sudo bash scripts/add-user.sh ${username} ${password} ${port}`
  });
});

router.post('/users/remove', requireAdmin, (req, res) => {
  const { username } = req.body;
  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);

  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });
  if (users[idx].role === 'admin') return res.json({ success: false, message: 'Admin tidak bisa dihapus.' });

  users.splice(idx, 1);
  saveUsers(users);

  res.json({
    success: true,
    message: `User '${username}' dihapus dari portal.`,
    shellCommand: `sudo bash scripts/remove-user.sh ${username}`
  });
});

router.post('/users/reset-password', requireAdmin, (req, res) => {
  const { username, newPassword } = req.body;
  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);

  if (idx === -1) return res.json({ success: false, message: 'User tidak ditemukan.' });

  users[idx].password = bcrypt.hashSync(newPassword, 10);
  saveUsers(users);
  res.json({ success: true, message: `Password '${username}' berhasil direset.` });
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

  users[idx].projects.push(cleanName);
  saveUsers(users);

  res.json({
    success: true,
    message: `Project '${cleanName}' ditambahkan ke user '${username}'.`,
    shellCommand: `sudo bash scripts/create-project.sh ${username} ${cleanName}`
  });
});

module.exports = router;
