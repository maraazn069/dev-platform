const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();

const USERS_FILE = path.join(__dirname, '../data/users.json');

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

router.post('/login', (req, res) => {
  const { username, password } = req.body;
  const users = getUsers();
  const user = users.find(u => u.username === username);

  if (!user || !bcrypt.compareSync(password, user.password)) {
    return res.json({ success: false, message: 'Username atau password salah.' });
  }

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

router.post('/logout', (req, res) => {
  req.session.destroy(() => {
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
  if (newPassword.length < 8) {
    return res.json({ success: false, message: 'Password baru minimal 8 karakter.' });
  }

  users[idx].password = bcrypt.hashSync(newPassword, 10);
  fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
  res.json({ success: true, message: 'Password berhasil diubah.' });
});

module.exports = router;
