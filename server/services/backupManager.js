const fs = require('fs');
const path = require('path');
const { spawn, execSync } = require('child_process');

const BACKUP_ROOT = process.env.BACKUP_ROOT || '/opt/devplatform/backups';
const DATA_DIR = process.env.DATA_DIR || '/opt/devplatform/data';
const ENV_FILE = path.resolve(__dirname, '../../.env');

function ensureRoot() {
  if (!fs.existsSync(BACKUP_ROOT)) {
    fs.mkdirSync(BACKUP_ROOT, { recursive: true, mode: 0o750 });
  }
}

function listBackups() {
  ensureRoot();
  const categories = ['manual', 'daily', 'weekly', 'monthly'];
  const backups = [];
  for (const cat of categories) {
    const dir = path.join(BACKUP_ROOT, cat);
    if (!fs.existsSync(dir)) continue;
    const entries = fs.readdirSync(dir, { withFileTypes: true })
      .filter(e => e.isDirectory());
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      let size = 0;
      let files = [];
      try {
        files = fs.readdirSync(fullPath).map(f => {
          const fp = path.join(fullPath, f);
          const st = fs.statSync(fp);
          size += st.size;
          return { name: f, size: st.size };
        });
      } catch (e) { /* unreadable */ }
      backups.push({
        id: `${cat}/${entry.name}`,
        category: cat,
        timestamp: entry.name,
        sizeMB: (size / 1024 / 1024).toFixed(1),
        sizeBytes: size,
        files,
      });
    }
  }
  backups.sort((a, b) => b.timestamp.localeCompare(a.timestamp));
  return backups;
}

let runningBackup = null;

function isBackupRunning() {
  return runningBackup !== null;
}

function getRunningStatus() {
  return runningBackup ? { running: true, ...runningBackup } : { running: false };
}

async function createBackup() {
  if (runningBackup) {
    return { success: false, message: 'Backup masih berjalan. Tunggu sampai selesai.' };
  }
  ensureRoot();

  const ts = new Date().toISOString().replace(/[:.]/g, '-').replace('T', '_').slice(0, 19);
  const outDir = path.join(BACKUP_ROOT, 'manual', ts);
  fs.mkdirSync(outDir, { recursive: true, mode: 0o750 });

  runningBackup = { startedAt: new Date().toISOString(), outDir, step: 'init', errors: [] };

  let env = {};
  try {
    if (fs.existsSync(ENV_FILE)) {
      fs.readFileSync(ENV_FILE, 'utf8').split('\n').forEach(line => {
        const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
        if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
      });
    }
  } catch {}

  const pgPass = env.POSTGRES_PASSWORD || process.env.POSTGRES_PASSWORD || 'postgres';
  const myPass = env.MYSQL_ROOT_PASSWORD || process.env.MYSQL_ROOT_PASSWORD || '';

  const runCmd = (cmd, args, opts = {}) => new Promise((resolve) => {
    const p = spawn(cmd, args, opts);
    let stderr = '';
    p.stderr?.on('data', d => stderr += d.toString());
    p.on('close', code => resolve({ code, stderr: stderr.slice(-2000) }));
    p.on('error', err => resolve({ code: -1, stderr: err.message }));
  });

  try {
    // Helper: run dump → gzip → file, wait for BOTH gzip exit AND file flush.
    const dumpToGzipFile = (dumpSpawnArgs, outPath) => new Promise(resolve => {
      const dump = spawn(...dumpSpawnArgs);
      const gzip = spawn('gzip');
      const out = fs.createWriteStream(outPath);
      let stderr = '';
      let dumpCode = null;
      dump.stderr.on('data', d => stderr += d.toString());
      dump.stdout.pipe(gzip.stdin);
      gzip.stdout.pipe(out);
      dump.on('close', c => { dumpCode = c; });
      gzip.on('error', err => { stderr += `gzip error: ${err.message}`; });
      out.on('finish', () => {
        // out finishes after gzip ends and all bytes flushed to disk
        resolve({ code: dumpCode === null ? -1 : dumpCode, stderr: stderr.slice(-1000) });
      });
      out.on('error', err => resolve({ code: -1, stderr: stderr + ' file: ' + err.message }));
    });

    runningBackup.step = 'postgres';
    const pgRes = await dumpToGzipFile(
      ['docker', ['exec', '-e', `PGPASSWORD=${pgPass}`, 'devplatform-postgres',
        'pg_dumpall', '-U', 'postgres', '--clean', '--if-exists']],
      path.join(outDir, 'postgres-all.sql.gz')
    );
    if (pgRes.code !== 0) runningBackup.errors.push(`postgres dump rc=${pgRes.code}: ${pgRes.stderr}`);

    runningBackup.step = 'mysql';
    // Pass mysql password via env var (MYSQL_PWD) instead of -p inline,
    // to avoid shell-injection if password contains quotes/$ etc.
    const myRes = await dumpToGzipFile(
      ['docker', ['exec', '-e', `MYSQL_PWD=${myPass}`, 'devplatform-mysql',
        'mysqldump', '-uroot', '--all-databases', '--single-transaction',
        '--quick', '--routines', '--events']],
      path.join(outDir, 'mysql-all.sql.gz')
    );
    if (myRes.code !== 0) runningBackup.errors.push(`mysql dump rc=${myRes.code}: ${myRes.stderr}`);

    runningBackup.step = 'workspace';
    if (fs.existsSync(DATA_DIR)) {
      const tarRes = await runCmd('tar', [
        '--warning=no-file-changed',
        '--exclude=*/.trash/*',
        '--exclude=*/node_modules/*',
        '--exclude=*/.cache/*',
        '-czf', path.join(outDir, 'workspace.tar.gz'),
        '-C', path.dirname(DATA_DIR), path.basename(DATA_DIR)
      ]);
      if (tarRes.code >= 2) runningBackup.errors.push(`workspace tar rc=${tarRes.code}: ${tarRes.stderr}`);
    }

    runningBackup.step = 'portal-data';
    const portalDataDir = path.resolve(__dirname, '../data');
    if (fs.existsSync(portalDataDir)) {
      const tarRes = await runCmd('tar', [
        '-czf', path.join(outDir, 'portal-data.tar.gz'),
        '-C', path.dirname(portalDataDir), path.basename(portalDataDir)
      ]);
      if (tarRes.code !== 0) runningBackup.errors.push(`portal-data tar rc=${tarRes.code}: ${tarRes.stderr}`);
    }

    runningBackup.step = 'env-copy';
    if (fs.existsSync(ENV_FILE)) {
      try {
        fs.copyFileSync(ENV_FILE, path.join(outDir, '.env.backup'));
        fs.chmodSync(path.join(outDir, '.env.backup'), 0o600);
      } catch (e) { runningBackup.errors.push(`env copy: ${e.message}`); }
    }

    runningBackup.step = 'manifest';
    const files = fs.readdirSync(outDir);
    const totalSize = files.reduce((s, f) => s + fs.statSync(path.join(outDir, f)).size, 0);
    fs.writeFileSync(path.join(outDir, 'MANIFEST.txt'),
      `Backup time   : ${ts}\nCategory      : manual\nHostname      : ${require('os').hostname()}\nFiles:\n${files.map(f => `  ${f}`).join('\n')}\nTotal size    : ${(totalSize / 1024 / 1024).toFixed(1)} MB\nErrors        : ${runningBackup.errors.length}\n${runningBackup.errors.join('\n')}\n`);

    runningBackup.step = 'done';
    const result = {
      success: runningBackup.errors.length === 0,
      message: runningBackup.errors.length === 0
        ? `Backup selesai. Lokasi: manual/${ts} (${(totalSize / 1024 / 1024).toFixed(1)} MB)`
        : `Backup selesai dengan ${runningBackup.errors.length} error. Cek MANIFEST.txt.`,
      backupId: `manual/${ts}`,
      errors: runningBackup.errors,
    };
    runningBackup = null;
    return result;
  } catch (e) {
    runningBackup = null;
    return { success: false, message: 'Backup error: ' + e.message };
  }
}

function streamBackup(category, timestamp, res) {
  if (!/^[a-z]+$/.test(category) || !/^[\w\-:.]+$/.test(timestamp)) {
    res.status(400).json({ error: 'Invalid backup id' });
    return;
  }
  const dir = path.join(BACKUP_ROOT, category, timestamp);
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) {
    res.status(404).json({ error: 'Backup tidak ditemukan' });
    return;
  }
  res.setHeader('Content-Type', 'application/gzip');
  res.setHeader('Content-Disposition', `attachment; filename="backup-${category}-${timestamp}.tar.gz"`);
  const tar = spawn('tar', ['-czf', '-', '-C', path.dirname(dir), path.basename(dir)]);
  tar.stdout.pipe(res);
  tar.stderr.on('data', () => {});
  tar.on('error', () => { try { res.end(); } catch {} });
}

function deleteBackup(category, timestamp) {
  if (!/^[a-z]+$/.test(category) || !/^[\w\-:.]+$/.test(timestamp)) {
    return { success: false, message: 'Invalid backup id' };
  }
  const dir = path.join(BACKUP_ROOT, category, timestamp);
  if (!fs.existsSync(dir)) return { success: false, message: 'Backup tidak ditemukan.' };
  try {
    execSync(`rm -rf "${dir}"`, { timeout: 10000 });
    return { success: true, message: `Backup ${category}/${timestamp} dihapus.` };
  } catch (e) {
    return { success: false, message: e.message };
  }
}

module.exports = { listBackups, createBackup, streamBackup, deleteBackup, isBackupRunning, getRunningStatus, BACKUP_ROOT };
