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
  const defaultUsers = [
    {
      id: 'admin-001',
      username: 'admin',
      email: '',
      password: bcrypt.hashSync('admin123', 10),
      role: 'admin',
      displayName: 'Administrator',
      port: null,
      projects: [],
      mustChangePassword: true,
      createdAt: new Date().toISOString()
    },
    {
      id: 'user-001',
      username: 'user1',
      email: '',
      password: bcrypt.hashSync('user1234', 10),
      role: 'user',
      displayName: 'User Pertama',
      port: 8081,
      projects: ['default', 'belajar-python', 'belajar-web'],
      mustChangePassword: true,
      createdAt: new Date().toISOString()
    }
  ];
  fs.writeFileSync(USERS_FILE, JSON.stringify(defaultUsers, null, 2));
  console.log('Default users created: admin / admin123 | user1 / user1234');
  console.log('NOTE: Both default users HARUS ganti password saat login pertama.');
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
      // Inline styles & scripts diperbolehkan karena dashboard pakai inline (perubahan
      // besar untuk pisah file = scope lain). Kalau mau lebih ketat, pindah ke external file.
      "script-src": ["'self'", "'unsafe-inline'"],
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
});
