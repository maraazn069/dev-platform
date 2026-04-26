const { exec } = require('child_process');
const fs = require('fs');
const path = require('path');

const ENV_FILE = '/app/.env';
const FILEBROWSER_CONTAINER = 'devplatform-filebrowser';
// HARUS match docker-compose.yml. Versi non-s6 (binary di /filebrowser).
const FILEBROWSER_IMAGE = 'filebrowser/filebrowser:v2.30.0';
const PGADMIN_CONTAINER = 'devplatform-pgadmin';

// pgAdmin sync auto-disable kalau image punya issue (typer/argparse migration di v9+).
// Ditandai true setelah deteksi pertama → call subsequent jadi no-op silent.
// User bisa juga set PGADMIN_SYNC=false di .env untuk skip dari awal.
let pgAdminDisabled = (process.env.PGADMIN_SYNC || '').toLowerCase() === 'false';
let pgAdminWarnedOnce = false;
function isPgAdminUnsupportedError(stderr) {
  if (!stderr) return false;
  return /No module named ['"]?typer['"]?|ModuleNotFoundError/i.test(stderr);
}
function maybeDisablePgAdmin(stderr) {
  if (isPgAdminUnsupportedError(stderr) && !pgAdminDisabled) {
    pgAdminDisabled = true;
    if (!pgAdminWarnedOnce) {
      console.warn('[credentialSync] pgAdmin sync DISABLED untuk session ini — image pgAdmin tidak compatible (CLI typer migration). User tetap bisa login pgAdmin manual via UI dgn admin creds dari .env. Set PGADMIN_SYNC=false di .env biar pesan ini gak muncul lagi.');
      pgAdminWarnedOnce = true;
    }
  }
}

async function getFileBrowserVolumeName() {
  const result = await execAsync(
    `docker inspect ${FILEBROWSER_CONTAINER} --format '{{range .Mounts}}{{if eq .Destination "/database"}}{{.Name}}{{end}}{{end}}'`,
    5000
  );
  const name = (result.stdout || '').trim();
  return name || null;
}

function execAsync(cmd, timeoutMs = 30000) {
  return new Promise((resolve) => {
    exec(cmd, { timeout: timeoutMs }, (err, stdout, stderr) => {
      resolve({
        ok: !err,
        stdout: (stdout || '').trim(),
        stderr: (stderr || '').trim(),
        code: err ? (err.code || 1) : 0
      });
    });
  });
}

function shellEscape(s) {
  if (s === undefined || s === null) return "''";
  return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

async function syncToFileBrowser({ username, password }) {
  const target = username || 'admin';
  const volume = await getFileBrowserVolumeName();
  if (!volume) {
    return { ok: false, stderr: 'Tidak bisa deteksi volume File Browser (container belum jalan?)' };
  }

  const cmd = [
    'docker run --rm',
    `-v ${volume}:/database`,
    '--entrypoint filebrowser',
    FILEBROWSER_IMAGE,
    'users update', shellEscape(target),
    '--password', shellEscape(password),
    '--database /database/filebrowser.db'
  ].join(' ');

  // Stop running filebrowser to release DB lock, do update, start again.
  // Pakai docker stop/start (bukan compose) karena compose file path bisa beda.
  await execAsync(`docker stop ${FILEBROWSER_CONTAINER}`, 15000);

  const result = await execAsync(cmd, 25000);

  // Selalu coba start container lagi, bahkan kalau update gagal — supaya filebrowser tidak stuck mati
  const startResult = await execAsync(`docker start ${FILEBROWSER_CONTAINER}`, 15000);
  if (!startResult.ok) {
    return { ok: false, stderr: `Update OK tapi gagal restart container: ${startResult.stderr}` };
  }

  return result;
}

async function syncToPgAdmin({ email, password }) {
  if (pgAdminDisabled) return { ok: true, skipped: true, stderr: 'pgAdmin sync disabled' };
  if (!email) return { ok: false, stderr: 'pgAdmin sync skipped: email kosong' };
  const cmd = [
    `docker exec ${PGADMIN_CONTAINER}`,
    '/venv/bin/python /pgadmin4/setup.py update-password',
    '--user', shellEscape(email),
    '--password', shellEscape(password)
  ].join(' ');
  const result = await execAsync(cmd, 25000);
  if (!result.ok) {
    maybeDisablePgAdmin(result.stderr);
    if (pgAdminDisabled) return { ok: true, skipped: true, stderr: 'pgAdmin sync auto-disabled' };
    // Fallback: try without /venv/bin/python prefix (older images)
    const fallback = await execAsync(
      `docker exec ${PGADMIN_CONTAINER} python /pgadmin4/setup.py update-password --user ${shellEscape(email)} --password ${shellEscape(password)}`,
      25000
    );
    maybeDisablePgAdmin(fallback.stderr);
    return fallback;
  }
  return result;
}

/**
 * Create user pgAdmin baru (atau update password kalau udah ada).
 * pgAdmin minta EMAIL untuk login (bukan username), jadi kita pakai synthetic email.
 * Tries `add-user` (idempotent gak — kalau exists, fall back ke update-password).
 */
async function createPgAdminUser({ email, password, role }) {
  if (pgAdminDisabled) return { ok: true, skipped: true };
  if (!email || !password) return { ok: false, stderr: 'email/password kosong' };
  if (!fs.existsSync('/var/run/docker.sock')) return { ok: true, skipped: true };

  const roleArg = role === 'admin' ? '--admin' : '--nonadmin';

  // pgAdmin v6+ punya `setup.py add-user`. Cek dulu apakah subcommand ada.
  const tryAdd = await execAsync(
    `docker exec ${PGADMIN_CONTAINER} /venv/bin/python /pgadmin4/setup.py add-user --email ${shellEscape(email)} --password ${shellEscape(password)} ${roleArg}`,
    25000
  );
  if (tryAdd.ok) return { ok: true, action: 'created', email };
  maybeDisablePgAdmin(tryAdd.stderr);
  if (pgAdminDisabled) return { ok: true, skipped: true };

  // Kalau add-user gak ada / error karena duplicate, fall back ke update-password
  if (/already exists|duplicate/i.test(tryAdd.stderr) || /already exists|duplicate/i.test(tryAdd.stdout)) {
    const upd = await syncToPgAdmin({ email, password });
    return upd.ok ? { ok: true, action: 'updated', email } : { ok: false, stderr: upd.stderr };
  }

  // Fallback ke versi non-venv path
  const tryAdd2 = await execAsync(
    `docker exec ${PGADMIN_CONTAINER} python /pgadmin4/setup.py add-user --email ${shellEscape(email)} --password ${shellEscape(password)} ${roleArg}`,
    25000
  );
  if (tryAdd2.ok) return { ok: true, action: 'created', email };
  maybeDisablePgAdmin(tryAdd2.stderr);
  if (pgAdminDisabled) return { ok: true, skipped: true };
  if (/already exists|duplicate/i.test(tryAdd2.stderr)) {
    const upd = await syncToPgAdmin({ email, password });
    return upd.ok ? { ok: true, action: 'updated', email } : { ok: false, stderr: upd.stderr };
  }

  return { ok: false, stderr: tryAdd2.stderr || tryAdd.stderr || 'pgAdmin add-user failed' };
}

function updateEnvFile(updates) {
  if (!fs.existsSync(ENV_FILE)) {
    return { ok: false, stderr: '.env tidak di-mount ke portal container — skip update env' };
  }
  try {
    let content = fs.readFileSync(ENV_FILE, 'utf8');
    for (const [key, value] of Object.entries(updates)) {
      const safeValue = String(value).replace(/(\r?\n)/g, '');
      const re = new RegExp(`^${key}=.*$`, 'm');
      if (re.test(content)) {
        content = content.replace(re, `${key}=${safeValue}`);
      } else {
        content += `\n${key}=${safeValue}\n`;
      }
    }
    fs.writeFileSync(ENV_FILE, content);
    return { ok: true };
  } catch (e) {
    return { ok: false, stderr: e.message };
  }
}

/**
 * Sync admin password ke semua service. Best-effort: kalau salah satu gagal,
 * yang lain tetap dicoba. Return object dengan status per service.
 */
async function syncAdminPassword({ username, email, password }) {
  const results = {
    filebrowser: { ok: false, skipped: false },
    pgadmin: { ok: false, skipped: false },
    env: { ok: false, skipped: false }
  };

  // Skip sync di environment dev (Replit) — hanya jalan di VPS dengan docker socket
  if (!fs.existsSync('/var/run/docker.sock')) {
    results.filebrowser.skipped = true;
    results.pgadmin.skipped = true;
    results.env.skipped = true;
    return { ...results, allSkipped: true };
  }

  const fb = await syncToFileBrowser({ username, password });
  results.filebrowser = { ok: fb.ok, message: fb.ok ? 'updated' : (fb.stderr || fb.stdout) };

  const pg = await syncToPgAdmin({ email, password });
  results.pgadmin = { ok: pg.ok, message: pg.ok ? 'updated' : (pg.stderr || pg.stdout) };

  const env = updateEnvFile({ ADMIN_PASSWORD: password });
  results.env = { ok: env.ok, message: env.ok ? 'updated' : env.stderr };

  return results;
}

module.exports = { syncAdminPassword, createPgAdminUser, syncToPgAdmin };
