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

const app = express();
const PORT = process.env.PORT || 5000;
const IS_HTTPS = (process.env.PROTOCOL || 'http') === 'https';

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
      createdAt: new Date().toISOString()
    }
  ];
  fs.writeFileSync(USERS_FILE, JSON.stringify(defaultUsers, null, 2));
  console.log('Default users created: admin / admin123 | user1 / user1234');
}

app.set('trust proxy', 1);

app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false
}));

app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(express.static(path.join(__dirname, '../public')));

const SESSION_SECRET = process.env.SESSION_SECRET;
if (!SESSION_SECRET || SESSION_SECRET.length < 16) {
  if (process.env.NODE_ENV === 'production') {
    console.error('FATAL: SESSION_SECRET env var wajib diisi (min 16 karakter) untuk production.');
    process.exit(1);
  }
  console.warn('PERINGATAN: SESSION_SECRET kosong — pakai random sementara (dev only).');
}
const SECRET = SESSION_SECRET || crypto.randomBytes(32).toString('hex');

app.use(session({
  secret: SECRET,
  name: 'devplatform.sid',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: IS_HTTPS,
    httpOnly: true,
    sameSite: 'lax',
    maxAge: 8 * 60 * 60 * 1000
  }
}));

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  message: { success: false, message: 'Terlalu banyak percobaan login. Coba lagi 15 menit.' },
  standardHeaders: true,
  legacyHeaders: false
});

app.use('/auth/login', loginLimiter);
app.use('/auth', authRoutes);
app.use('/dashboard', dashboardRoutes);
app.use('/admin', adminRoutes);
app.use('/api', apiRoutes);

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/', (req, res) => {
  if (req.session && req.session.user) {
    if (req.session.user.role === 'admin') return res.redirect('/admin');
    return res.redirect('/dashboard');
  }
  res.redirect('/login');
});

app.get('/login', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/login.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dev Platform Portal running on port ${PORT} (${IS_HTTPS ? 'HTTPS' : 'HTTP'} mode)`);
});
