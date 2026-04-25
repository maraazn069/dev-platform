const fs = require('fs');
const path = require('path');

const USER_DATA_BASE = process.env.USER_DATA_BASE || '/opt/devplatform/data';
const NAME_RE = /^[a-z0-9][a-z0-9_-]{0,31}$/;
const RESERVED = new Set(['default', 'config', '.trash', '.cache', '.git', '.ssh']);

function isValidProjectName(name) {
  return typeof name === 'string' && NAME_RE.test(name);
}

function projectsDir(username) {
  return path.join(USER_DATA_BASE, username, 'projects');
}

function trashDir(username) {
  return path.join(USER_DATA_BASE, username, '.trash');
}

function ensureDirs(username) {
  fs.mkdirSync(projectsDir(username), { recursive: true });
  fs.mkdirSync(trashDir(username), { recursive: true });
}

function listProjects(username) {
  try {
    ensureDirs(username);
    const entries = fs.readdirSync(projectsDir(username), { withFileTypes: true });
    return entries
      .filter(e => e.isDirectory())
      .map(e => {
        const p = path.join(projectsDir(username), e.name);
        let mtime = null, size = 0;
        try {
          const st = fs.statSync(p);
          mtime = st.mtime.toISOString();
        } catch (_) {}
        return { name: e.name, mtime };
      })
      .sort((a, b) => (b.mtime || '').localeCompare(a.mtime || ''));
  } catch (e) {
    return [];
  }
}

function listTrash(username) {
  try {
    ensureDirs(username);
    return fs.readdirSync(trashDir(username), { withFileTypes: true })
      .filter(e => e.isDirectory())
      .map(e => {
        const m = e.name.match(/^(.+)__(\d+)$/);
        const original = m ? m[1] : e.name;
        const ts = m ? parseInt(m[2]) : null;
        return { trashName: e.name, originalName: original, deletedAt: ts ? new Date(ts).toISOString() : null };
      })
      .sort((a, b) => (b.deletedAt || '').localeCompare(a.deletedAt || ''));
  } catch {
    return [];
  }
}

function createProject(username, name) {
  if (!isValidProjectName(name)) {
    return { success: false, message: 'Nama project hanya huruf kecil/angka/underscore/dash, 1-32 karakter.' };
  }
  if (RESERVED.has(name)) {
    return { success: false, message: `Nama '${name}' tidak diperbolehkan.` };
  }
  ensureDirs(username);
  const target = path.join(projectsDir(username), name);
  if (fs.existsSync(target)) {
    return { success: false, message: `Project '${name}' sudah ada.` };
  }
  try {
    fs.mkdirSync(target, { recursive: true });
    fs.writeFileSync(path.join(target, 'README.md'),
      `# ${name}\n\nProject baru. Selamat ngoding! 🚀\n`);
    return { success: true, message: `Project '${name}' dibuat.`, project: { name } };
  } catch (e) {
    return { success: false, message: 'Gagal membuat project: ' + e.message };
  }
}

function renameProject(username, oldName, newName) {
  if (!isValidProjectName(oldName) || !isValidProjectName(newName)) {
    return { success: false, message: 'Nama project tidak valid.' };
  }
  if (RESERVED.has(newName) || RESERVED.has(oldName)) {
    return { success: false, message: 'Nama reserved tidak bisa diubah.' };
  }
  if (oldName === newName) {
    return { success: false, message: 'Nama lama dan baru sama.' };
  }
  const src = path.join(projectsDir(username), oldName);
  const dst = path.join(projectsDir(username), newName);
  // Cek dst dulu (informasi UX), tapi rename tetap try/catch untuk handle race.
  if (fs.existsSync(dst)) return { success: false, message: `Project '${newName}' sudah ada.` };
  try {
    fs.renameSync(src, dst);
    return { success: true, message: `Project di-rename ke '${newName}'.` };
  } catch (e) {
    if (e.code === 'ENOENT') return { success: false, message: 'Project tidak ditemukan.' };
    if (e.code === 'EEXIST' || e.code === 'ENOTEMPTY') return { success: false, message: `Project '${newName}' sudah ada.` };
    return { success: false, message: 'Gagal rename: ' + e.message };
  }
}

/**
 * Soft-delete: pindahkan ke .trash/<name>__<timestamp>/. Bisa di-restore.
 * Auto-purge file yang lebih tua dari 7 hari dipanggil oleh cron / saat akses.
 */
function softDeleteProject(username, name) {
  if (!isValidProjectName(name)) return { success: false, message: 'Nama project tidak valid.' };
  if (name === 'default') return { success: false, message: 'Project default tidak bisa dihapus.' };
  ensureDirs(username);
  const src = path.join(projectsDir(username), name);
  const trashName = `${name}__${Date.now()}`;
  const dst = path.join(trashDir(username), trashName);
  try {
    fs.renameSync(src, dst);
    purgeOldTrash(username);
    return { success: true, message: `Project '${name}' dipindah ke trash (bisa restore 7 hari).`, trashName };
  } catch (e) {
    if (e.code === 'ENOENT') return { success: false, message: 'Project tidak ditemukan (mungkin sudah dihapus).' };
    return { success: false, message: 'Gagal hapus: ' + e.message };
  }
}

function restoreProject(username, trashName) {
  if (!/^[a-z0-9][a-z0-9_-]+__\d+$/.test(trashName)) {
    return { success: false, message: 'Trash entry tidak valid.' };
  }
  const src = path.join(trashDir(username), trashName);
  const original = trashName.replace(/__\d+$/, '');
  const dst = path.join(projectsDir(username), original);
  if (fs.existsSync(dst)) return { success: false, message: `Project '${original}' sudah ada lagi (rename dulu yang aktif).` };
  try {
    ensureDirs(username);
    fs.renameSync(src, dst);
    return { success: true, message: `Project '${original}' dipulihkan.` };
  } catch (e) {
    if (e.code === 'ENOENT') return { success: false, message: 'Entry trash tidak ditemukan.' };
    if (e.code === 'EEXIST' || e.code === 'ENOTEMPTY') return { success: false, message: `Project '${original}' sudah ada lagi.` };
    return { success: false, message: 'Gagal restore: ' + e.message };
  }
}

function permanentDeleteTrash(username, trashName) {
  if (!/^[a-z0-9][a-z0-9_-]+__\d+$/.test(trashName)) {
    return { success: false, message: 'Trash entry tidak valid.' };
  }
  const src = path.join(trashDir(username), trashName);
  try {
    fs.rmSync(src, { recursive: true, force: true });
    return { success: true, message: 'Entry dihapus permanen.' };
  } catch (e) {
    if (e.code === 'ENOENT') return { success: true, message: 'Entry sudah tidak ada.' };
    return { success: false, message: 'Gagal: ' + e.message };
  }
}

/** Hapus entry trash > 7 hari. */
function purgeOldTrash(username) {
  try {
    const td = trashDir(username);
    if (!fs.existsSync(td)) return;
    const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
    for (const e of fs.readdirSync(td, { withFileTypes: true })) {
      if (!e.isDirectory()) continue;
      const m = e.name.match(/__(\d+)$/);
      if (!m) continue;
      const ts = parseInt(m[1]);
      if (ts < cutoff) {
        try { fs.rmSync(path.join(td, e.name), { recursive: true, force: true }); } catch {}
      }
    }
  } catch {}
}

module.exports = {
  isValidProjectName,
  listProjects,
  listTrash,
  createProject,
  renameProject,
  softDeleteProject,
  restoreProject,
  permanentDeleteTrash,
  purgeOldTrash,
  USER_DATA_BASE
};
