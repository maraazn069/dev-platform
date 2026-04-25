const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const USER_DATA_BASE = process.env.USER_DATA_BASE || '/opt/devplatform/data';

function safeName(s) {
  return /^[a-z][a-z0-9_-]{0,31}$/.test(s);
}

/** Returns kilobytes used by user data folder. */
function getUserUsageKb(username) {
  if (!safeName(username)) return null;
  const dir = path.join(USER_DATA_BASE, username);
  if (!fs.existsSync(dir)) return 0;
  try {
    const out = execSync(`du -sk "${dir}"`, { encoding: 'utf8', timeout: 5000 });
    const kb = parseInt(out.trim().split(/\s+/)[0]);
    return Number.isFinite(kb) ? kb : null;
  } catch {
    return null;
  }
}

function getDiskFree() {
  try {
    const out = execSync(`df -k "${USER_DATA_BASE}" | tail -1`, { encoding: 'utf8', timeout: 3000 });
    const parts = out.trim().split(/\s+/);
    return {
      totalKb: parseInt(parts[1]),
      usedKb: parseInt(parts[2]),
      availKb: parseInt(parts[3]),
      usePct: parts[4]
    };
  } catch {
    return null;
  }
}

function formatHuman(kb) {
  if (kb == null) return '?';
  if (kb < 1024) return kb + ' KB';
  if (kb < 1024 * 1024) return (kb / 1024).toFixed(1) + ' MB';
  return (kb / 1024 / 1024).toFixed(2) + ' GB';
}

module.exports = { getUserUsageKb, getDiskFree, formatHuman };
