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
  const domain = process.env.DOMAIN || 'netprem.org';
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

router.post('/databases', requireAuth, async (req, res) => {
  const { type, name } = req.body;
  const username = req.session.user.username;
  try {
    const result = await userManager.createDatabase(username, type, name);
    audit.log('db.create', { type, name, success: result.success }, req);
    res.json(result);
  } catch (e) {
    res.status(500).json({ success: false, message: 'DB create gagal: ' + e.message });
  }
});

router.delete('/databases/:type/:name', requireAuth, async (req, res) => {
  const { type, name } = req.params;
  const { confirm } = req.body || {};
  if (confirm !== name) {
    return res.json({ success: false, message: `Konfirmasi: kirim body { "confirm": "${name}" }.` });
  }
  const username = req.session.user.username;
  try {
    const result = await userManager.dropDatabase(username, type, name);
    audit.log('db.drop', { type, name, success: result.success }, req);
    res.json(result);
  } catch (e) {
    res.status(500).json({ success: false, message: 'DB drop gagal: ' + e.message });
  }
});

// ===== Project management (per user) =====

// Subdomain reserved — gak boleh tabrakan dengan service global di apex.
const RESERVED_SUBDOMAINS = new Set([
  'www', 'mail', 'mysql', 'postgres', 'pgadmin', 'phpmyadmin',
  'files', 'admin', 'api', 'preview', 'app'
]);

function slugify(name) {
  const raw = String(name || '').toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (!raw) return 'app';

  // Append 4-char hash supaya nama panjang yg di-truncate gak collide.
  // Juga supaya project bernama 'mysql' (reserved) gak konflik.
  const crypto = require('crypto');
  const hash = crypto.createHash('md5').update(name + '').digest('hex').slice(0, 4);
  let slug = raw.slice(0, 40);

  // Kalau hasil truncate cocok original full, gak perlu hash.
  // Kalau truncated ATAU reserved, append hash.
  if (slug !== raw || RESERVED_SUBDOMAINS.has(slug)) {
    slug = (slug.slice(0, 35) + '-' + hash).replace(/-+/g, '-').replace(/^-+|-+$/g, '');
  }
  return slug || 'app';
}

router.get('/my/projects', requireAuth, (req, res) => {
  const username = req.session.user.username;
  const domain = process.env.DOMAIN || 'netprem.org';
  const proto = process.env.PROTOCOL || 'http';
  const projects = projectManager.listProjects(username).map(p => ({
    ...p,
    url: `${proto}://${username}.${domain}/?folder=/config/projects/${encodeURIComponent(p.name)}`,
    // OPSI C: preview URL untuk dev server di port 3000 dalam container.
    // User jalankan `npm run dev` / `python -m http.server 3000` di project, lalu buka URL ini.
    previewUrl: `${proto}://${slugify(p.name)}.${username}.${domain}`
  }));
  res.json({
    projects,
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
  // Terima confirm dari body (POST-style) atau query string (DELETE-friendly).
  const confirm = (req.body && req.body.confirm) || (req.query && req.query.confirm);
  if (confirm !== name) {
    return res.json({ success: false, message: `Konfirmasi: kirim ?confirm=${name} di URL atau body { "confirm": "${name}" }.` });
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

  const domain = process.env.DOMAIN || 'netprem.org';
  const proto = process.env.PROTOCOL || 'http';
  const targetDb = req.query.db ? userManager.safeDbName(username, req.query.db) : `${username}_default`;
  const phpUrl = `${proto}://mysql.${domain}/`;
  const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

  // Auto-submit di-block sama CSRF protection phpMyAdmin modern. Kita pake landing
  // page dengan kredensial yg di-display + tombol "Buka phpMyAdmin" + auto-copy ke clipboard.
  const html = `<!DOCTYPE html>
<html lang="id">
<head>
  <meta charset="UTF-8">
  <title>Buka phpMyAdmin</title>
  <link rel="icon" href="/assets/favicon.svg" type="image/svg+xml">
  <style>
    * { box-sizing:border-box; margin:0; padding:0; }
    body { font-family: system-ui, -apple-system, sans-serif; background:#0d1117; color:#c9d1d9; padding:32px; min-height:100vh; }
    .card { max-width:680px; margin:0 auto; background:#161b22; border:1px solid #30363d; border-radius:12px; padding:28px; }
    h2 { color:#f0f6fc; margin-bottom:8px; display:flex; align-items:center; gap:10px; }
    .sub { color:#8b949e; margin-bottom:20px; font-size:.92rem; }
    .step { background:#0d1117; border:1px solid #21262d; border-radius:8px; padding:14px 18px; margin:10px 0; }
    .step b { color:#58a6ff; }
    .row { display:flex; justify-content:space-between; align-items:center; padding:10px 0; border-bottom:1px solid #21262d; font-family: 'SF Mono', 'Consolas', monospace; font-size:.9rem; }
    .row:last-child { border-bottom:none; }
    .key { color:#8b949e; font-weight:500; }
    .val { color:#79c0ff; }
    a.btn, button.btn { display:inline-block; background:#1f6feb; color:#fff; padding:12px 24px; border-radius:7px; text-decoration:none; font-weight:600; margin-top:16px; border:none; cursor:pointer; font-size:.95rem; }
    a.btn:hover, button.btn:hover { background:#388bfd; }
    .copy { cursor:pointer; color:#8b949e; font-size:.78rem; padding:4px 10px; border:1px solid #30363d; border-radius:4px; margin-left:8px; background:transparent; transition:.15s; }
    .copy:hover { color:#58a6ff; border-color:#58a6ff; }
    .copy.copied { color:#3fb950; border-color:#3fb950; }
    .info { background:#0c2d6b; border:1px solid #1f6feb; color:#79c0ff; padding:10px 14px; border-radius:7px; font-size:.85rem; margin-top:14px; }
  </style>
</head>
<body>
  <div class="card">
    <h2>🐬 Buka phpMyAdmin (MySQL)</h2>
    <div class="sub">Login otomatis di-block oleh phpMyAdmin (CSRF protection). Pakai langkah berikut — cuma butuh 2 klik.</div>

    <div class="step">
      <b>Langkah 1.</b> Klik tombol <b>Copy Username</b> dan <b>Copy Password</b> di bawah, lalu klik <b>Buka phpMyAdmin</b>.
      <div class="row"><span class="key">Server</span><span class="val">devplatform-mysql</span></div>
      <div class="row"><span class="key">Database</span><span class="val">${esc(targetDb)}</span></div>
      <div class="row"><span class="key">Username</span><span class="val" id="pmaU">${esc(username)}</span><button class="copy" onclick="cp('pmaU',this)">Copy</button></div>
      <div class="row"><span class="key">Password</span><span class="val" id="pmaP">${esc(creds.mysqlPassword)}</span><button class="copy" onclick="cp('pmaP',this)">Copy</button></div>
    </div>

    <div class="step">
      <b>Langkah 2.</b> Di tab phpMyAdmin: paste username & password → Login. Setelah masuk, sidebar kiri akan menampilkan database <b>${esc(targetDb)}</b>.
    </div>

    <div class="info">💡 Tips: centang "Save credentials" di phpMyAdmin biar gak perlu paste tiap kali.</div>

    <a class="btn" href="${esc(phpUrl)}" target="_blank" rel="noopener">🚀 Buka phpMyAdmin</a>
  </div>

  <script>
    function cp(id, btn) {
      const txt = document.getElementById(id).textContent;
      navigator.clipboard.writeText(txt).then(() => {
        btn.textContent = '✓ Copied';
        btn.classList.add('copied');
        setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('copied'); }, 1500);
      });
    }
  </script>
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

  const domain = process.env.DOMAIN || 'netprem.org';
  const proto = process.env.PROTOCOL || 'http';
  const pgadminUrl = `${proto}://pgadmin.${domain}`;
  const dbName = `${username}_default`;
  const pgAdminEmail = creds.pgAdminEmail || `${username}@netprem.local`;
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
    <p style="color:#8b949e">Login pgAdmin pakai akun pribadi kamu di bawah, lalu register koneksi ke database kamu.</p>

    <div class="step">
      <b>Langkah 1. Login pgAdmin</b> — pgAdmin minta <b>email</b> (bukan username). Kamu udah punya akun otomatis:
      <div class="row"><span class="key">Email</span><span class="val" id="pgEmail">${esc(pgAdminEmail)}</span><span class="copy" onclick="copyOne('pgEmail',this)">Copy</span></div>
      <div class="row"><span class="key">Password</span><span class="val" id="pgPw">${esc(creds.pgPassword)}</span><span class="copy" onclick="copyOne('pgPw',this)">Copy</span></div>
    </div>

    <div class="step">
      <b>Langkah 2. Register koneksi</b> — setelah login, klik kanan <code>Servers</code> → <b>Register</b> → <b>Server...</b>
      <br>Tab <b>General</b> → Name: <code>Database Saya</code>
      <br>Tab <b>Connection</b>:
      <div class="row"><span class="key">Host</span><span class="val">devplatform-postgres</span></div>
      <div class="row"><span class="key">Port</span><span class="val">5432</span></div>
      <div class="row"><span class="key">Maintenance DB</span><span class="val">${esc(dbName)}</span></div>
      <div class="row"><span class="key">Username</span><span class="val" id="pgUser">${esc(username)}</span><span class="copy" onclick="copyOne('pgUser',this)">Copy</span></div>
      <div class="row"><span class="key">Password</span><span class="val" id="pgConnPw">${esc(creds.pgPassword)}</span><span class="copy" onclick="copyOne('pgConnPw',this)">Copy</span></div>
      <div style="color:#8b949e;font-size:.8rem;margin-top:6px;">✓ Centang "Save password" supaya tidak diminta lagi.</div>
    </div>

    <div class="warn">⚠️ Kalau pgAdmin nolak email kamu = akun belum di-create. Minta admin tekan tombol "Repair pgAdmin User" di panel admin.</div>

    <a class="btn" href="${esc(pgadminUrl)}" target="_blank">🚀 Buka pgAdmin Sekarang</a>
  </div>
  <script>
    function copyOne(id, btn) {
      const txt = document.getElementById(id).textContent;
      navigator.clipboard.writeText(txt).then(() => {
        const orig = btn.textContent;
        btn.textContent = '✓';
        setTimeout(() => { btn.textContent = orig; }, 1200);
      });
    }
  </script>
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

  const domain = process.env.DOMAIN || 'netprem.org';
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
