const express = require('express');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const router = express.Router();
const userManager = require('../services/userManager');
const projectManager = require('../services/projectManager');
const diskUsage = require('../services/diskUsage');
const audit = require('../services/auditLog');

const USERS_FILE = path.join(__dirname, '../data/users.json');

function requireAuth(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  if (req.session.user.mustChangePassword) {
    return res.status(423).json({ error: 'must_change_password', message: 'Ganti password dulu.' });
  }
  next();
}

function requireAdmin(req, res, next) {
  if (!req.session || !req.session.user) return res.status(401).json({ error: 'Unauthorized' });
  if (req.session.user.role !== 'admin') return res.status(403).json({ error: 'Forbidden' });
  if (req.session.user.mustChangePassword) return res.status(423).json({ error: 'must_change_password' });
  next();
}

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

function getDockerStats() {
  try {
    const output = execSync(
      'docker stats --no-stream --format "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}"',
      { timeout: 5000, encoding: 'utf8' }
    );
    return output.trim().split('\n').map(line => {
      const [name, cpu, mem, memPerc, net] = line.split('|');
      return { name, cpu, mem, memPerc, net };
    }).filter(s => s.name && s.name.startsWith('codeserver-'));
  } catch {
    return getMockStats();
  }
}

function getMockStats() {
  const users = getUsers().filter(u => u.role !== 'admin');
  return users.map(u => ({
    name: `codeserver-${u.username}`,
    cpu: (Math.random() * 15).toFixed(1) + '%',
    mem: `${(Math.random() * 800 + 200).toFixed(0)}MiB / 56GiB`,
    memPerc: (Math.random() * 3).toFixed(1) + '%',
    net: `${(Math.random() * 10).toFixed(1)}MB / ${(Math.random() * 50).toFixed(1)}MB`,
    mock: true
  }));
}

function getDockerContainerStatus(username) {
  try {
    return execSync(
      `docker inspect --format='{{.State.Status}}' codeserver-${username}`,
      { timeout: 3000, encoding: 'utf8' }
    ).trim();
  } catch {
    return 'not_found';
  }
}

router.get('/stats', requireAdmin, (req, res) => {
  res.json({ stats: getDockerStats(), timestamp: new Date().toISOString() });
});

router.get('/users/status', requireAdmin, (req, res) => {
  const users = getUsers();
  const stats = getDockerStats();

  const result = users.filter(u => u.role !== 'admin').map(u => {
    const stat = stats.find(s => s.name === `codeserver-${u.username}`);
    const containerStatus = getDockerContainerStatus(u.username);
    return {
      id: u.id,
      username: u.username,
      displayName: u.displayName,
      port: u.port,
      projects: u.projects || [],
      databases: u.databases || [],
      hasDbCredentials: !!(u.mysqlPassword && u.pgPassword),
      mustChangePassword: !!u.mustChangePassword,
      deletionPending: !!u.deletionPending,
      diskKb: diskUsage.getUserUsageKb(u.username),
      createdAt: u.createdAt,
      container: {
        status: containerStatus,
        cpu: stat ? stat.cpu : '0%',
        mem: stat ? stat.mem : '0MiB / 0GiB',
        memPerc: stat ? stat.memPerc : '0%',
        net: stat ? stat.net : '0B / 0B',
        mock: stat ? !!stat.mock : true
      }
    };
  });

  res.json({ users: result, timestamp: new Date().toISOString() });
});

// ===== Database endpoints (per user) =====

router.get('/db/info', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const domain = process.env.DOMAIN || 'dev.example.com';
  const proto = process.env.PROTOCOL || 'http';
  const creds = userManager.getCredentials(username) || {};

  res.json({
    publicHost: domain,
    mysql: {
      remoteHost: domain,
      remotePort: 3306,
      internalHost: 'devplatform-mysql',
      internalPort: 3306,
      user: username,
      password: creds.mysqlPassword,
      defaultDb: `${username}_default`
    },
    postgres: {
      remoteHost: domain,
      remotePort: 5432,
      internalHost: 'devplatform-postgres',
      internalPort: 5432,
      user: username,
      password: creds.pgPassword,
      defaultDb: `${username}_default`
    },
    web: {
      phpmyadmin: `${proto}://mysql.${domain}`,
      pgadmin: `${proto}://pgadmin.${domain}`
    }
  });
});

router.get('/databases', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const dbs = userManager.listUserDatabases(username);
  res.json({ databases: dbs });
});

router.post('/databases', requireAuth, (req, res) => {
  const { type, name } = req.body;
  const username = req.session.user.username;
  const result = userManager.createDatabase(username, type, name);
  audit.log('db.create', { type, name, success: result.success }, req);
  res.json(result);
});

router.delete('/databases/:type/:name', requireAuth, (req, res) => {
  const { type, name } = req.params;
  const { confirm } = req.body || {};
  if (confirm !== name) {
    return res.json({ success: false, message: `Konfirmasi: kirim body { "confirm": "${name}" }.` });
  }
  const username = req.session.user.username;
  const result = userManager.dropDatabase(username, type, name);
  audit.log('db.drop', { type, name, success: result.success }, req);
  res.json(result);
});

// ===== Project management (per user) =====

router.get('/my/projects', requireAuth, (req, res) => {
  const username = req.session.user.username;
  res.json({
    projects: projectManager.listProjects(username),
    trash: projectManager.listTrash(username)
  });
});

router.post('/my/projects', requireAuth, (req, res) => {
  const { name } = req.body;
  const username = req.session.user.username;
  const result = projectManager.createProject(username, name);
  if (result.success) audit.log('project.create', { name, username }, req);
  res.json(result);
});

router.patch('/my/projects/:name', requireAuth, (req, res) => {
  const { name } = req.params;
  const { newName } = req.body;
  const username = req.session.user.username;
  const result = projectManager.renameProject(username, name, newName);
  if (result.success) audit.log('project.rename', { from: name, to: newName, username }, req);
  res.json(result);
});

router.delete('/my/projects/:name', requireAuth, (req, res) => {
  const { name } = req.params;
  const { confirm } = req.body || {};
  if (confirm !== name) {
    return res.json({ success: false, message: `Konfirmasi: kirim body { "confirm": "${name}" } yang sama dengan nama project.` });
  }
  const username = req.session.user.username;
  const result = projectManager.softDeleteProject(username, name);
  if (result.success) audit.log('project.soft_delete', { name, username }, req);
  res.json(result);
});

router.post('/my/trash/:trashName/restore', requireAuth, (req, res) => {
  const { trashName } = req.params;
  const username = req.session.user.username;
  const result = projectManager.restoreProject(username, trashName);
  if (result.success) audit.log('project.restore', { trashName, username }, req);
  res.json(result);
});

router.delete('/my/trash/:trashName', requireAuth, (req, res) => {
  const { trashName } = req.params;
  const username = req.session.user.username;
  const result = projectManager.permanentDeleteTrash(username, trashName);
  if (result.success) audit.log('project.purge', { trashName, username }, req);
  res.json(result);
});

// ===== Disk usage =====
router.get('/my/usage', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const usedKb = diskUsage.getUserUsageKb(username);
  const free = diskUsage.getDiskFree();
  res.json({
    user: {
      username,
      usedKb,
      usedHuman: diskUsage.formatHuman(usedKb)
    },
    disk: free
  });
});

// ===== Auto-login launchers =====

router.get('/launch/phpmyadmin', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const creds = userManager.getCredentials(username);
  if (!creds || !creds.mysqlPassword) {
    return res.status(404).send('Credentials MySQL belum di-generate. Minta admin untuk repair-db.');
  }

  const domain = process.env.DOMAIN || 'dev.example.com';
  const proto = process.env.PROTOCOL || 'http';
  const targetDb = req.query.db ? userManager.safeDbName(username, req.query.db) : `${username}_default`;
  const escapeHtml = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  const html = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <title>Membuka phpMyAdmin...</title>
  <style>
    body { font-family: system-ui; background:#0d1117; color:#c9d1d9;
      display:flex; flex-direction:column; align-items:center; justify-content:center;
      height:100vh; margin:0; gap:14px; }
    .spinner { width:40px; height:40px; border:3px solid #30363d; border-top-color:#1f6feb;
      border-radius:50%; animation:spin .8s linear infinite; }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="spinner"></div>
  <div>Membuka phpMyAdmin sebagai <strong>${escapeHtml(username)}</strong>...</div>
  <form id="f" method="POST" action="${proto}://mysql.${domain}/index.php" style="display:none">
    <input name="pma_username" value="${escapeHtml(username)}">
    <input name="pma_password" value="${escapeHtml(creds.mysqlPassword)}">
    <input name="server" value="1">
    <input name="target" value="db_structure.php">
    <input name="db" value="${escapeHtml(targetDb)}">
  </form>
  <script>document.getElementById('f').submit();</script>
</body>
</html>`;
  audit.log('launch.phpmyadmin', { db: targetDb }, req);
  res.set('Content-Type', 'text/html; charset=utf-8').send(html);
});

router.get('/launch/pgadmin', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const creds = userManager.getCredentials(username);
  if (!creds || !creds.pgPassword) {
    return res.status(404).send('Credentials PostgreSQL belum di-generate. Minta admin untuk repair-db.');
  }

  const domain = process.env.DOMAIN || 'dev.example.com';
  const proto = process.env.PROTOCOL || 'http';
  const pgadminUrl = `${proto}://pgadmin.${domain}`;
  const dbName = `${username}_default`;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  const html = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <title>Buka pgAdmin</title>
  <style>
    * { box-sizing:border-box; margin:0; padding:0; }
    body { font-family: system-ui; background:#0d1117; color:#c9d1d9; padding:32px; }
    .card { max-width:680px; margin:0 auto; background:#161b22; border:1px solid #30363d; border-radius:12px; padding:28px; }
    h2 { color:#f0f6fc; margin-bottom:16px; }
    .step { background:#0d1117; border:1px solid #21262d; border-radius:8px; padding:14px 18px; margin:10px 0; }
    .step b { color:#58a6ff; }
    code { background:#0d1117; padding:3px 8px; border-radius:4px; color:#79c0ff; font-family:'Consolas',monospace; }
    .row { display:flex; justify-content:space-between; padding:8px 0; border-bottom:1px solid #21262d; font-family:'Consolas',monospace; font-size:.85rem; }
    .row:last-child { border-bottom:none; }
    .key { color:#8b949e; }
    .val { color:#79c0ff; }
    a.btn { display:inline-block; background:#1f6feb; color:#fff; padding:10px 20px; border-radius:7px; text-decoration:none; font-weight:600; margin-top:16px; }
    a.btn:hover { background:#388bfd; }
    .copy { cursor:pointer; color:#8b949e; font-size:.8rem; padding:2px 6px; border:1px solid #30363d; border-radius:4px; margin-left:8px; }
    .warn { background:#3d2c1a; border:1px solid #f0883e; color:#f0883e; padding:10px 14px; border-radius:7px; font-size:.82rem; }
  </style>
</head>
<body>
  <div class="card">
    <h2>🐘 Buka pgAdmin (PostgreSQL)</h2>
    <p style="color:#8b949e">pgAdmin butuh login dulu, lalu kamu register koneksi ke database kamu sendiri.</p>

    <div class="step">
      <b>Langkah 1.</b> Login ke pgAdmin pakai akun yang dikasih admin secara terpisah
      (bukan di-display di sini demi keamanan). Kalau belum punya, hubungi admin platform.
    </div>

    <div class="step">
      <b>Langkah 2.</b> Setelah masuk, klik kanan <code>Servers</code> → <b>Register</b> → <b>Server...</b>
    </div>

    <div class="step">
      <b>Langkah 3.</b> Tab <b>General</b> → Name: <code>Database Saya</code><br>
      Tab <b>Connection</b> isi:
      <div class="row"><span class="key">Host</span><span class="val">devplatform-postgres</span></div>
      <div class="row"><span class="key">Port</span><span class="val">5432</span></div>
      <div class="row"><span class="key">Maintenance database</span><span class="val">${esc(dbName)}</span></div>
      <div class="row"><span class="key">Username</span><span class="val">${esc(username)}</span></div>
      <div class="row"><span class="key">Password</span><span class="val" id="pgpw">${esc(creds.pgPassword)}</span><span class="copy" onclick="navigator.clipboard.writeText(document.getElementById('pgpw').textContent)">Copy</span></div>
      <div style="color:#8b949e;font-size:.8rem;margin-top:6px;">✓ Centang "Save password" supaya tidak diminta lagi.</div>
    </div>

    <div class="warn">⚠️ Tip: kalau koneksi remote butuh akses dari laptop, pakai psql/DBeaver dengan
    info di tab "Akses Remote" di dashboard — lebih aman daripada pakai web pgAdmin.</div>

    <a class="btn" href="${esc(pgadminUrl)}" target="_blank">🚀 Buka pgAdmin Sekarang</a>
  </div>
</body>
</html>`;
  audit.log('launch.pgadmin', {}, req);
  res.set('Content-Type', 'text/html; charset=utf-8').send(html);
});

router.get('/projects/:username', requireAuth, (req, res) => {
  const { username } = req.params;
  if (req.session.user.role !== 'admin' && req.session.user.username !== username) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  const users = getUsers();
  const user = users.find(u => u.username === username);
  if (!user) return res.status(404).json({ error: 'User tidak ditemukan' });

  const domain = process.env.DOMAIN || 'dev.example.com';
  const protocol = process.env.PROTOCOL || 'http';

  // Pakai project list dari filesystem (sumber kebenaran), fallback ke users.json
  let projectNames;
  try {
    const fsList = projectManager.listProjects(username).map(p => p.name);
    projectNames = fsList.length > 0 ? fsList : (user.projects || ['default']);
  } catch {
    projectNames = user.projects || ['default'];
  }

  const projects = projectNames.map(p => ({
    name: p,
    url: `${protocol}://${username}.${domain}/?folder=/config/projects/${p}`,
    localPort: `http://localhost:${user.port}/?folder=/config/projects/${p}`
  }));

  res.json({ username, projects });
});

module.exports = router;
