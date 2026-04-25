const express = require('express');
const path = require('path');
const router = express.Router();

function requireAuth(req, res, next) {
  if (!req.session || !req.session.user) return res.redirect('/login');
  next();
}

router.get('/', requireAuth, (req, res) => {
  res.sendFile(path.join(__dirname, '../../public/dashboard.html'));
});

router.get('/me', requireAuth, (req, res) => {
  res.json({ user: req.session.user });
});

module.exports = router;
