const express = require('express');
const bcrypt = require('bcryptjs');
const fs = require('fs');
const path = require('path');
const router = express.Router();
const userManager = require('../services/userManager');
const { validateStrong } = require('../services/passwordPolicy');
const audit = require('../services/auditLog');
const settingsManager = require('../services/settingsManager');
const backupManager = require('../services/backupManager');
const servicesManager = require('../services/servicesManager');

const USERS_FILE = path.join(__dirname, '../data/users.json');

function requireAdmin(req, res, next) {
  if (!req.session || !req.session.user) return res.redirect('/login');
  if (req.session.user.role !== 'admin') return res.redirect('/dashboard');
  next();
}

function requireAdminApi(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  if (req.session.user.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });
  next();
}

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

// saveUsers dipindah ke userManager.updateUsers() — semua mutasi users.json
// HARUS lewat mutex withUserLock untuk hindari race condition.

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

router.post('/users/add', requireAdminApi, async (req, res) => {
  const { username, displayName, password, email } = req.body;
  if (!username || !password) {
    return res.json({ success: false, message: 'Username dan password wajib diisi.' });
  }
  const policy = validateStrong(password, username);
  if (!policy.ok) return res.json({ success: false, message: policy.message });

  try {
    const result = await userManager.provisionUser({ username, password, displayName, email });
    audit.log('user.add', { target: username, success: result.success }, req);
    res.json(result);
  } catch (e) {
    audit.log('user.add', { target: username, success: false, error: e.message }, req);
    res.status(500).json({ success: false, message: 'Provision gagal: ' + e.message });
  }
});

router.post('/users/remove', requireAdminApi, async (req, res) => {
  const { username, confirm } = req.body;
  if (confirm !== username) {
    return res.json({ success: false, message: `Konfirmasi: ketik tepat "${username}".` });
  }
  try {
    const result = await userManager.removeUser(username);
    audit.log('user.remove', { target: username, success: result.success, warnings: result.warnings }, req);
    res.json(result);
  } catch (e) {
    audit.log('user.remove', { target: username, success: false, error: e.message }, req);
    res.status(500).json({ success: false, message: 'Remove gagal: ' + e.message });
  }
});

router.post('/users/reset-password', requireAdminApi, async (req, res) => {
  const { username, newPassword } = req.body;
  const policy = validateStrong(newPassword, username);
  if (!policy.ok) return res.json({ success: false, message: policy.message });

  try {
    const result = await userManager.updateUsers((users) => {
      const idx = users.findIndex(u => u.username === username);
      if (idx === -1) return { ok: false, message: 'User tidak ditemukan.' };
      users[idx].password = bcrypt.hashSync(newPassword, 12);
      users[idx].mustChangePassword = false;
      users[idx].passwordChangedAt = new Date().toISOString();
      return { ok: true };
    });
    if (!result.ok) return res.json({ success: false, message: result.message });

    // Sync password VS Code (code-server) supaya login VS Code juga pakai password baru.
    let csSync = { success: false, error: 'not attempted' };
    try {
      csSync = userManager.updateCodeServerPassword(username, newPassword);
    } catch (e) {
      csSync = { success: false, error: e.message };
    }

    audit.log('user.password_reset', {
      target: username,
      codeserver_sync: csSync.success ? 'ok' : (csSync.error || 'failed')
    }, req);

    const baseMsg = `Password '${username}' direset.`;
    const csMsg = csSync.success
      ? ' VS Code login juga di-update.'
      : ` ⚠ Password VS Code GAGAL di-sync (${csSync.error || 'unknown'}). Restart container manual.`;
    res.json({ success: true, message: baseMsg + csMsg });
  } catch (e) {
    res.status(500).json({ success: false, message: 'Reset password gagal: ' + e.message });
  }
});

router.post('/users/repair-db', requireAdminApi, async (req, res) => {
  const { username } = req.body;
  try {
    const result = await userManager.repairUserCredentials(username);
    audit.log('user.repair_db', { target: username, success: result.success }, req);
    res.json(result);
  } catch (e) {
    res.status(500).json({ success: false, message: 'Repair gagal: ' + e.message });
  }
});

// Recreate (in-place upgrade) container code-server user — fix 502 cepat tanpa SSH
router.post('/users/recreate-container', requireAdminApi, async (req, res) => {
  const { username } = req.body;
  if (!username) return res.json({ success: false, message: 'Username wajib.' });
  try {
    const result = await userManager.recreateContainer(username);
    audit.log('user.recreate_container', { target: username, success: result.success }, req);
    res.json(result);
  } catch (e) {
    res.status(500).json({ success: false, message: 'Recreate gagal: ' + e.message });
  }
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

// ===== Settings (edit .env yang aman dari web) =====
router.get('/settings', requireAdminApi, (req, res) => {
  res.json({
    success: true,
    editable: settingsManager.getEditableSettings(),
    readOnly: settingsManager.getReadOnlySettings(),
  });
});

router.post('/settings', requireAdminApi, (req, res) => {
  const updates = req.body || {};
  const result = settingsManager.updateSettings(updates);
  audit.log('settings.update', { keys: Object.keys(updates), success: result.success }, req);
  res.json(result);
});

// ===== Services (status + restart container) =====
router.get('/services', requireAdminApi, (req, res) => {
  res.json(servicesManager.listServices());
});

router.get('/services/stats', requireAdminApi, (req, res) => {
  res.json({ stats: servicesManager.getDockerStats() });
});

router.post('/services/restart', requireAdminApi, (req, res) => {
  const { name } = req.body;
  const result = servicesManager.restartService(name);
  audit.log('services.restart', { target: name, success: result.success }, req);
  res.json(result);
});

// ===== Backup (list, create, download, delete) =====
router.get('/backups', requireAdminApi, (req, res) => {
  res.json({ backups: backupManager.listBackups(), root: backupManager.BACKUP_ROOT });
});

router.get('/backups/status', requireAdminApi, (req, res) => {
  res.json(backupManager.getRunningStatus());
});

router.post('/backups/create', requireAdminApi, async (req, res) => {
  audit.log('backup.create_start', {}, req);
  const result = await backupManager.createBackup();
  audit.log('backup.create_done', { success: result.success, errors: result.errors }, req);
  res.json(result);
});

router.get('/backups/download/:category/:timestamp', requireAdmin, (req, res) => {
  audit.log('backup.download', { id: `${req.params.category}/${req.params.timestamp}` }, req);
  backupManager.streamBackup(req.params.category, req.params.timestamp, res);
});

router.post('/backups/delete', requireAdminApi, (req, res) => {
  const { category, timestamp, confirm } = req.body;
  if (confirm !== `${category}/${timestamp}`) {
    return res.json({ success: false, message: 'Konfirmasi tidak cocok.' });
  }
  const result = backupManager.deleteBackup(category, timestamp);
  audit.log('backup.delete', { id: `${category}/${timestamp}`, success: result.success }, req);
  res.json(result);
});

module.exports = router;
