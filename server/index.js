const express = require('express');
const session = require('express-session');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const authRoutes = require('./routes/auth');
const dashboardRoutes = require('./routes/dashboard');
const adminRoutes = require('./routes/admin');
const apiRoutes = require('./routes/api');

const { csrfMiddleware, csrfTokenEndpoint } = require('./middleware/csrf');
const audit = require('./services/auditLog');

const app = express();
const PORT = process.env.PORT || 5000;
const IS_HTTPS = (process.env.PROTOCOL || 'http') === 'https';
const IDLE_TIMEOUT_MIN = parseInt(process.env.IDLE_TIMEOUT_MIN || '60', 10);

const DATA_DIR = path.join(__dirname, 'data');
if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

const USERS_FILE = path.join(DATA_DIR, 'users.json');
if (!fs.existsSync(USERS_FILE)) {
  const bcrypt = require('bcryptjs');
  // Admin password & username di-set dari .env (install-vps.sh nanya manual).
  // Kalau .env tidak ada (mode dev di Replit), pakai default 'admin/admin123'
  // dengan force-change agar tidak bocor.
  const adminUsername = process.env.ADMIN_USERNAME || 'admin';
  const adminPassword = process.env.ADMIN_PASSWORD || 'admin123';
  const adminEmail = process.env.ADMIN_EMAIL || '';
  const adminFromEnv = !!process.env.ADMIN_PASSWORD;

  const defaultUsers = [
    {
      id: 'admin-001',
      username: adminUsername,
      email: adminEmail,
      password: bcrypt.hashSync(adminPassword, 10),
      role: 'admin',
      displayName: 'Administrator',
      port: null,
      projects: [],
      // Kalau admin set password manual via .env → tidak perlu force-change
      // Kalau pakai default 'admin123' → wajib ganti
      mustChangePassword: !adminFromEnv,
      passwordChangedAt: adminFromEnv ? new Date().toISOString() : undefined,
      createdAt: new Date().toISOString()
    }
  ];
  fs.writeFileSync(USERS_FILE, JSON.stringify(defaultUsers, null, 2));
  if (adminFromEnv) {
    console.log(`Admin user created: ${adminUsername} (password dari .env, tidak force-change)`);
  } else {
    console.log('Default admin created: admin / admin123 — WAJIB ganti password saat login pertama.');
  }
}

// Migration: untuk install lama yang belum punya mustChangePassword. Kalau user
// belum pernah ganti password (passwordChangedAt absent), set flag-nya.
try {
  const users = JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
  let changed = false;
  for (const u of users) {
    if (u.mustChangePassword === undefined && !u.passwordChangedAt) {
      u.mustChangePassword = true;
      changed = true;
    }
  }
  if (changed) {
    fs.writeFileSync(USERS_FILE, JSON.stringify(users, null, 2));
    console.log('[migration] mustChangePassword flag ditambahkan ke user lama yang belum ganti password.');
  }
} catch (e) {
  console.warn('[migration] gagal cek users.json:', e.message);
}

app.set('trust proxy', 1);
app.disable('x-powered-by');

// ----- Helmet (HTTP security headers) -----
app.use(helmet({
  contentSecurityPolicy: {
    useDefaults: true,
    directives: {
      "default-src": ["'self'"],
      // Inline styles & scripts diperbolehkan karena dashboard/admin pakai inline.
      // 'unsafe-hashes' diperlukan untuk inline event handlers (onclick, oninput, dll)
      // yang dipakai di admin.html, dashboard.html, change-password-required.html.
      "script-src": ["'self'", "'unsafe-inline'"],
      "script-src-attr": ["'self'", "'unsafe-inline'", "'unsafe-hashes'"],
      "style-src": ["'self'", "'unsafe-inline'"],
      "img-src": ["'self'", "data:", "https:"],
      "connect-src": ["'self'"],
      "frame-ancestors": ["'self'"],
      "form-action": ["'self'"]
    }
  },
  crossOriginEmbedderPolicy: false,
  hsts: IS_HTTPS ? { maxAge: 15552000, includeSubDomains: true, preload: false } : false,
  referrerPolicy: { policy: 'same-origin' }
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));

const SESSION_SECRET = process.env.SESSION_SECRET;
if (!SESSION_SECRET || SESSION_SECRET.length < 16) {
  if (process.env.NODE_ENV === 'production') {
    console.error('FATAL: SESSION_SECRET env var wajib diisi (min 16 karakter) untuk production.');
    process.exit(1);
  }
  console.warn('PERINGATAN: SESSION_SECRET kosong — pakai random sementara (dev only).');
}
const SECRET = SESSION_SECRET || crypto.randomBytes(32).toString('hex');

// Session: idle timeout (rolling cookie)
app.use(session({
  secret: SECRET,
  name: 'devplatform.sid',
  resave: false,
  rolling: true,                  // refresh expiry every request
  saveUninitialized: false,
  cookie: {
    secure: IS_HTTPS,
    httpOnly: true,
    sameSite: 'lax',
    maxAge: IDLE_TIMEOUT_MIN * 60 * 1000
  }
}));

// ----- Rate limits -----
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 8,
  message: { success: false, message: 'Terlalu banyak percobaan login. Coba lagi 15 menit.' },
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res, next, options) => {
    audit.log('login.rate_limited', { username: req.body && req.body.username }, req);
    res.status(options.statusCode).json(options.message);
  }
});

const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 120,
  standardHeaders: true,
  legacyHeaders: false
});

app.use('/auth/login', loginLimiter);
app.use('/api', apiLimiter);

// ----- CSRF protection -----
// Login dan health di-exempt karena user belum punya session.
// Logout dan endpoint lain wajib token.
const csrf = csrfMiddleware({
  secure: IS_HTTPS,
  exempt: ['/auth/login', '/health', '/csrf-token']
});
app.use(csrf);

// Static AFTER session+csrf (so HTML pages get CSRF cookie set on GET)
app.use(express.static(path.join(__dirname, '../public')));

// CSRF token endpoint untuk JS fetch
app.get('/csrf-token', csrfTokenEndpoint);

app.use('/auth', authRoutes);
app.use('/dashboard', dashboardRoutes);
app.use('/admin', adminRoutes);
app.use('/api', apiRoutes);

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/', (req, res) => {
  if (req.session && req.session.user) {
    if (req.session.user.mustChangePassword) return res.redirect('/change-password-required');
    if (req.session.user.role === 'admin') return res.redirect('/admin');
    return res.redirect('/dashboard');
  }
  res.redirect('/login');
});

app.get('/login', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/login.html'));
});

app.get('/change-password-required', (req, res) => {
  if (!req.session || !req.session.user) return res.redirect('/login');
  res.sendFile(path.join(__dirname, '../public/change-password-required.html'));
});

// 404 JSON for /api/*, fallback redirect for others
app.use('/api', (req, res) => res.status(404).json({ error: 'Not found' }));
app.use((req, res) => res.redirect('/'));

// Error handler (don't leak stack)
app.use((err, req, res, next) => {
  console.error('[error]', err.message);
  audit.log('server.error', { path: req.path, message: err.message }, req);
  if (res.headersSent) return next(err);
  res.status(500).json({ error: 'Internal error' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dev Platform Portal running on port ${PORT} (${IS_HTTPS ? 'HTTPS' : 'HTTP'} mode, idle ${IDLE_TIMEOUT_MIN}min)`);

  // SELF-HEAL nginx user conf: scan users.json saat portal start, regenerate semua
  // user.conf di nginx/users/. Heal drift kalau:
  //   - portal restart tapi user.conf hilang (volume baru)
  //   - migration / upgrade gak auto-trigger Repair Container per user
  //   - cert per-user baru di-issue → conf perlu regenerated dengan path cert baru
  // Tulis semua file dulu (skipReload=true), lalu RELOAD SEKALI di akhir.
  // Tunggu container nginx siap dulu — di cold start, portal bisa ready sebelum nginx up.
  const runSelfHeal = async () => {
    try {
      const fs = require('fs');
      const path = require('path');
      const usersFile = path.join(__dirname, 'data/users.json');
      if (!fs.existsSync(usersFile)) return;

      const users = JSON.parse(fs.readFileSync(usersFile, 'utf8'));
      const targets = users.filter(u => u.role !== 'admin' && u.username);
      if (targets.length === 0) {
        console.log('[self-heal] no non-admin users, skip nginx user.conf regen');
        return;
      }

      const nginxManager = require('./services/nginxManager');
      const { reloadNginx } = require('./services/dockerExec');
      const { execFileSync } = require('child_process');

      // Wait for nginx-proxy container (max 30s, cek tiap 2s).
      // Kalau ga ada (mode dev tanpa docker), skip reload tapi tetap tulis file.
      let nginxReady = false;
      for (let i = 0; i < 15; i++) {
        try {
          const out = execFileSync('docker', ['ps', '--format', '{{.Names}}', '--filter', 'name=^nginx-proxy$'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
          if (out.trim() === 'nginx-proxy') { nginxReady = true; break; }
        } catch { /* docker not available — dev mode */ break; }
        await new Promise(r => setTimeout(r, 2000));
      }

      let regenerated = 0;
      let failed = 0;
      for (const u of targets) {
        try {
          const r = nginxManager.ensureUserConfig(u.username, { skipReload: true });
          if (r.success) regenerated++;
          else { failed++; console.warn(`[self-heal] ${u.username}: ${r.message}`); }
        } catch (e) {
          failed++;
          console.warn(`[self-heal] ${u.username} error: ${e.message}`);
        }
      }

      console.log(`[self-heal] nginx user.conf regenerated: ${regenerated} ok, ${failed} failed (nginx ${nginxReady ? 'ready' : 'not detected'})`);

      if (regenerated > 0 && nginxReady) {
        const r = reloadNginx();
        if (r && r.success === false) console.warn(`[self-heal] nginx reload failed: ${r.error}`);
        else console.log('[self-heal] nginx reloaded ✓ (single reload)');
      } else if (regenerated > 0) {
        console.log('[self-heal] file written but nginx not ready — skip reload (will pick up on next start)');
      }
    } catch (e) {
      console.warn(`[self-heal] error: ${e.message}`);
    }
  };
  runSelfHeal();
});
