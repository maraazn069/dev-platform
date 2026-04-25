const fs = require('fs');
const path = require('path');

const ENV_FILE = path.resolve(__dirname, '../../.env');

const ALLOWED_KEYS = {
  IDLE_TIMEOUT_MIN: {
    label: 'Idle Timeout (menit)',
    description: 'Container code-server dimatikan otomatis setelah tidak ada aktivitas selama X menit. 0 = nonaktif.',
    type: 'number',
    min: 0,
    max: 1440,
    default: '60',
    affects: ['portal'],
  },
  CODE_SERVER_MEM: {
    label: 'Memory limit per user',
    description: 'Batas RAM container code-server tiap user. Contoh: 1g, 2g, 512m. Berlaku untuk container yang baru dibuat.',
    type: 'string',
    pattern: /^\d+[mg]$/i,
    default: '2g',
    affects: ['portal'],
  },
  CODE_SERVER_CPUS: {
    label: 'CPU limit per user',
    description: 'Batas CPU (dalam core) per container code-server. Contoh: 1, 1.5, 2.',
    type: 'string',
    pattern: /^\d+(\.\d+)?$/,
    default: '1.5',
    affects: ['portal'],
  },
  CODE_SERVER_PIDS: {
    label: 'Max processes per user',
    description: 'Batas jumlah process di dalam container code-server. Mencegah fork bomb.',
    type: 'number',
    min: 50,
    max: 5000,
    default: '300',
    affects: ['portal'],
  },
  DB_REMOTE_IPS: {
    label: 'IP whitelist untuk MySQL/PostgreSQL remote',
    description: 'Daftar IP/CIDR (pisah koma) yang boleh konek ke MySQL/PG dari luar VPS. Kosongkan = buka untuk semua IP. Contoh: 1.2.3.4,10.0.0.0/24',
    type: 'string',
    default: '',
    affects: ['nginx', 'iptables-note'],
  },
  TZ: {
    label: 'Timezone',
    description: 'Timezone semua container. Contoh: Asia/Jakarta, UTC.',
    type: 'string',
    default: 'Asia/Jakarta',
    affects: ['all-containers'],
  },
};

const READ_ONLY_KEYS = ['DOMAIN', 'PROTOCOL', 'ADMIN_USERNAME', 'ADMIN_EMAIL'];

function parseEnv() {
  if (!fs.existsSync(ENV_FILE)) return {};
  const out = {};
  fs.readFileSync(ENV_FILE, 'utf8').split('\n').forEach(line => {
    const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
    if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, '');
  });
  return out;
}

function getEditableSettings() {
  const env = parseEnv();
  const out = {};
  for (const [key, meta] of Object.entries(ALLOWED_KEYS)) {
    out[key] = {
      ...meta,
      pattern: meta.pattern ? meta.pattern.source : undefined,
      currentValue: env[key] || meta.default || '',
    };
  }
  return out;
}

function getReadOnlySettings() {
  const env = parseEnv();
  const out = {};
  READ_ONLY_KEYS.forEach(k => { out[k] = env[k] || ''; });
  return out;
}

function validateValue(key, value) {
  const meta = ALLOWED_KEYS[key];
  if (!meta) return { ok: false, message: `Setting "${key}" tidak diizinkan diubah.` };

  const v = String(value ?? '').trim();

  if (meta.type === 'number') {
    if (v === '' && meta.min !== 0) return { ok: false, message: `${meta.label} wajib diisi.` };
    const n = Number(v);
    if (!Number.isFinite(n)) return { ok: false, message: `${meta.label} harus angka.` };
    if (meta.min !== undefined && n < meta.min) return { ok: false, message: `${meta.label} minimum ${meta.min}.` };
    if (meta.max !== undefined && n > meta.max) return { ok: false, message: `${meta.label} maksimum ${meta.max}.` };
  }

  if (meta.type === 'string' && meta.pattern && v !== '' && !meta.pattern.test(v)) {
    return { ok: false, message: `Format ${meta.label} tidak valid (harus cocok ${meta.pattern}).` };
  }

  if (/[\r\n]/.test(v)) return { ok: false, message: `${meta.label} tidak boleh mengandung newline.` };

  return { ok: true, value: v };
}

function writeEnvAtomic(env) {
  const lines = [];
  const seen = new Set();
  if (fs.existsSync(ENV_FILE)) {
    fs.readFileSync(ENV_FILE, 'utf8').split('\n').forEach(line => {
      const m = line.match(/^([A-Z_][A-Z0-9_]*)=/);
      if (m) {
        const key = m[1];
        if (env[key] !== undefined) {
          lines.push(`${key}=${env[key]}`);
          seen.add(key);
        } else {
          lines.push(line);
        }
      } else {
        lines.push(line);
      }
    });
  }
  for (const [k, v] of Object.entries(env)) {
    if (!seen.has(k)) lines.push(`${k}=${v}`);
  }
  const tmp = `${ENV_FILE}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, lines.join('\n'), { mode: 0o600 });
  fs.renameSync(tmp, ENV_FILE);
}

function updateSettings(updates) {
  const validated = {};
  const errors = [];
  for (const [key, value] of Object.entries(updates)) {
    const result = validateValue(key, value);
    if (!result.ok) errors.push(result.message);
    else validated[key] = result.value;
  }
  if (errors.length) return { success: false, message: errors.join(' ') };

  writeEnvAtomic(validated);

  const affectedServices = new Set();
  for (const key of Object.keys(validated)) {
    (ALLOWED_KEYS[key].affects || []).forEach(s => affectedServices.add(s));
  }

  return {
    success: true,
    message: 'Pengaturan tersimpan.',
    note: affectedServices.has('portal')
      ? 'Beberapa pengaturan baru aktif setelah portal direstart. Klik "Restart Portal" di tab Layanan, atau jalankan: sudo docker compose restart portal'
      : 'Pengaturan tersimpan ke .env. Beberapa setting (DB_REMOTE_IPS) hanya berlaku ke container code-server yang BARU dibuat.',
    affectedServices: Array.from(affectedServices),
  };
}

module.exports = { getEditableSettings, getReadOnlySettings, updateSettings, ALLOWED_KEYS };
