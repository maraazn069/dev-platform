const fs = require('fs');
const path = require('path');

const LOG_FILE = path.join(__dirname, '../data/audit.log');
const MAX_BYTES = 5 * 1024 * 1024;

let writeChain = Promise.resolve();
let bytesSinceCheck = 0;
const CHECK_INTERVAL_BYTES = 256 * 1024;

function ensureFile() {
  const dir = path.dirname(LOG_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(LOG_FILE)) fs.writeFileSync(LOG_FILE, '');
}

function maybeRotate() {
  try {
    if (bytesSinceCheck < CHECK_INTERVAL_BYTES) return;
    bytesSinceCheck = 0;
    const stat = fs.statSync(LOG_FILE);
    if (stat.size > MAX_BYTES) {
      const rotated = LOG_FILE + '.1';
      try { fs.unlinkSync(rotated); } catch (_) {}
      fs.renameSync(LOG_FILE, rotated);
      fs.writeFileSync(LOG_FILE, '');
    }
  } catch (_) { /* tolerate */ }
}

/**
 * Append-only JSONL audit log. Writes are serialized via a Promise chain
 * (mutex) to avoid race conditions during rotation.
 */
function log(event, details, req) {
  const entry = {
    ts: new Date().toISOString(),
    event,
    ip: req ? (req.ip || req.connection?.remoteAddress || '?') : null,
    user: req && req.session && req.session.user ? req.session.user.username : null,
    ua: req && req.headers ? (req.headers['user-agent'] || '').substring(0, 120) : null,
    ...details
  };
  const line = JSON.stringify(entry) + '\n';

  writeChain = writeChain.then(() => new Promise((resolve) => {
    try {
      ensureFile();
      maybeRotate();
      fs.appendFile(LOG_FILE, line, (err) => {
        if (err) console.error('[audit] failed to write log:', err.message);
        else bytesSinceCheck += line.length;
        resolve();
      });
    } catch (e) {
      console.error('[audit] write error:', e.message);
      resolve();
    }
  }));
}

/**
 * Read last N lines from audit log (newest first).
 */
function tail(limit = 200) {
  try {
    ensureFile();
    const data = fs.readFileSync(LOG_FILE, 'utf8');
    const lines = data.trim().split('\n').filter(Boolean);
    const last = lines.slice(-limit).reverse();
    return last.map(l => {
      try { return JSON.parse(l); } catch { return { ts: '?', event: 'parse_error', raw: l }; }
    });
  } catch {
    return [];
  }
}

module.exports = { log, tail };
