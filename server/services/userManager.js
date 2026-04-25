const fs = require('fs');
const path = require('path');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const {
  randomPassword,
  dockerExec,
  dockerCmd,
  mysqlQuery,
  pgQuery,
  dockerNetworkName,
  reloadNginx,
  containerExists
} = require('./dockerExec');
const nginxManager = require('./nginxManager');

const USERS_FILE = path.join(__dirname, '../data/users.json');
const USER_DATA_BASE = '/opt/devplatform/data';

function getUsers() {
  return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8'));
}

function saveUsers(users) {
  // Atomic write: tulis ke .tmp lalu rename. Mencegah users.json corrupt
  // kalau proses crash / disk full di tengah penulisan.
  const tmp = USERS_FILE + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(users, null, 2));
  fs.renameSync(tmp, USERS_FILE);
}

function isValidName(name) {
  return /^[a-z][a-z0-9_]{1,30}$/.test(name);
}

function safeDbName(username, dbName) {
  return `${username}_${dbName}`;
}

/**
 * Provision a MySQL user with privileges scoped ONLY to databases matching <username>_*.
 * SECURITY: We deliberately do NOT grant CREATE/DROP/SHOW DATABASES on *.* — that would
 * let any user (via the publicly exposed 3306 port) DROP another tenant's databases.
 * The portal creates databases on behalf of users using the root account; users only
 * need data-level privileges within their own prefixed databases.
 */
function provisionMysqlUser(username, password) {
  if (!isValidName(username)) throw new Error('invalid username');
  const escPw = password.replace(/'/g, "''");
  // Note: the LIKE-style pattern grant `username\_%`.* uses backslash to escape `_`
  // so it does NOT accidentally cover databases like `usernameXfoo`.
  const sql = `
    CREATE USER IF NOT EXISTS '${username}'@'%' IDENTIFIED BY '${escPw}';
    ALTER USER '${username}'@'%' IDENTIFIED BY '${escPw}';
    GRANT ALL PRIVILEGES ON \\\`${username}\\_%\\\`.* TO '${username}'@'%';
    FLUSH PRIVILEGES;
  `;
  return mysqlQuery(sql);
}

/**
 * Provision a PostgreSQL role WITHOUT the CREATEDB attribute. Database creation goes
 * through the portal (which uses postgres superuser) so tenants can't create
 * arbitrary out-of-prefix databases via remote psql connections.
 */
function provisionPgUser(username, password) {
  if (!isValidName(username)) throw new Error('invalid username');
  const escPw = password.replace(/'/g, "''");
  const sql = `
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${username}') THEN
        CREATE ROLE ${username} WITH LOGIN PASSWORD '${escPw}';
      ELSE
        ALTER ROLE ${username} WITH LOGIN PASSWORD '${escPw}';
      END IF;
    END
    $$;
  `.replace(/\n\s+/g, ' ');
  return pgQuery(sql);
}

function createMysqlDatabase(username, dbName) {
  const fullName = safeDbName(username, dbName);
  const sql = `
    CREATE DATABASE IF NOT EXISTS \\\`${fullName}\\\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    GRANT ALL PRIVILEGES ON \\\`${fullName}\\\`.* TO '${username}'@'%';
    FLUSH PRIVILEGES;
  `;
  return mysqlQuery(sql);
}

function dropMysqlDatabase(username, dbName) {
  const fullName = safeDbName(username, dbName);
  return mysqlQuery(`DROP DATABASE IF EXISTS \\\`${fullName}\\\`;`);
}

function createPgDatabase(username, dbName) {
  const fullName = safeDbName(username, dbName);
  const r1 = pgQuery(`CREATE DATABASE ${fullName} OWNER ${username};`);
  return r1;
}

function dropPgDatabase(username, dbName) {
  const fullName = safeDbName(username, dbName);
  return pgQuery(`DROP DATABASE IF EXISTS ${fullName};`);
}

function createCodeServerContainer(username, password) {
  if (containerExists(`codeserver-${username}`)) {
    return { success: true, output: 'already exists' };
  }
  const userDir = `${USER_DATA_BASE}/${username}`;
  const network = dockerNetworkName();

  // Create user directories on host (we have /opt/devplatform/data mounted rw)
  try {
    fs.mkdirSync(`${userDir}/projects/default`, { recursive: true });
    fs.mkdirSync(`${userDir}/projects/belajar-python`, { recursive: true });
    fs.mkdirSync(`${userDir}/projects/belajar-web`, { recursive: true });
    fs.mkdirSync(`${userDir}/config`, { recursive: true });
    fs.mkdirSync(`${userDir}/.trash`, { recursive: true });
  } catch (e) { /* ok if exists */ }

  // SECURITY/STABILITY: Resource limits + no-new-privileges + log rotation.
  // We deliberately do NOT cap_drop ALL because linuxserver code-server image needs
  // a wide set of caps (s6 init, su-exec, sudo) and dropping breaks startup.
  // Per-user limits prevent one tenant from OOM/CPU-starving the host.
  const memLimit = process.env.CODE_SERVER_MEM || '2g';
  const cpuLimit = process.env.CODE_SERVER_CPUS || '1.5';
  const pidsLimit = process.env.CODE_SERVER_PIDS || '300';

  return dockerCmd([
    'run', '-d',
    '--name', `codeserver-${username}`,
    '--restart', 'unless-stopped',
    '--network', network,
    '--memory', memLimit,
    '--memory-swap', memLimit,
    '--cpus', cpuLimit,
    '--pids-limit', pidsLimit,
    '--security-opt', 'no-new-privileges:true',
    '--log-opt', 'max-size=10m',
    '--log-opt', 'max-file=3',
    '-e', 'PUID=1000',
    '-e', 'PGID=1000',
    '-e', `TZ=${process.env.TZ || 'Asia/Jakarta'}`,
    '-e', `PASSWORD=${password}`,
    '-e', `SUDO_PASSWORD=${password}`,
    '-e', 'DEFAULT_WORKSPACE=/config/projects/default',
    '-v', `${userDir}/projects:/config/projects`,
    '-v', `${userDir}/config:/config`,
    '--label', `devplatform.user=${username}`,
    'lscr.io/linuxserver/code-server:latest'
  ], { timeout: 60000 });
}

function removeCodeServerContainer(username) {
  return dockerCmd(['rm', '-f', `codeserver-${username}`]);
}

/**
 * Provision full user: code-server container, MySQL user+default DB, PG user+default DB,
 * nginx subdomain entry. Generates passwords and saves to users.json.
 */
function provisionUser({ username, password, displayName, email }) {
  if (!isValidName(username)) {
    return { success: false, message: 'Username hanya huruf kecil/angka/underscore, 2-31 karakter, harus mulai huruf.' };
  }

  const users = getUsers();
  if (users.find(u => u.username === username)) {
    return { success: false, message: `Username '${username}' sudah ada.` };
  }

  const mysqlPassword = randomPassword(16);
  const pgPassword = randomPassword(16);
  const port = 8081 + users.filter(u => u.role !== 'admin').length;
  const errors = [];

  // 1) MySQL user + default db
  const r1 = provisionMysqlUser(username, mysqlPassword);
  if (!r1.success) errors.push('MySQL user: ' + r1.error);

  const r2 = createMysqlDatabase(username, 'default');
  if (!r2.success) errors.push('MySQL db: ' + r2.error);

  // 2) Postgres user + default db
  const r3 = provisionPgUser(username, pgPassword);
  if (!r3.success) errors.push('PG user: ' + r3.error);

  const r4 = createPgDatabase(username, 'default');
  if (!r4.success && !/already exists/i.test(r4.error)) errors.push('PG db: ' + r4.error);

  // 3) Code-server container
  const r5 = createCodeServerContainer(username, password);
  if (!r5.success) errors.push('codeserver: ' + r5.error);

  // 4) Nginx subdomain (idempotent: skip if wildcard already covers it)
  const r6 = nginxManager.ensureUserSubdomain(username);
  if (!r6.success) errors.push('nginx: ' + r6.message);

  // 5) Save to users.json
  // mustChangePassword=true → user dipaksa ganti password admin-set saat login pertama
  const newUser = {
    id: uuidv4(),
    username,
    email: email || '',
    password: bcrypt.hashSync(password, 12),
    role: 'user',
    displayName: displayName || username,
    port,
    projects: ['default', 'belajar-python', 'belajar-web'],
    databases: [
      { type: 'mysql', name: 'default', createdAt: new Date().toISOString() },
      { type: 'postgres', name: 'default', createdAt: new Date().toISOString() }
    ],
    mysqlPassword,
    pgPassword,
    mustChangePassword: true,
    createdAt: new Date().toISOString()
  };
  users.push(newUser);
  saveUsers(users);

  return {
    success: errors.length === 0,
    message: errors.length === 0 ? `User '${username}' berhasil dibuat lengkap.` : `User '${username}' dibuat dengan ${errors.length} peringatan.`,
    warnings: errors,
    user: { username, displayName: newUser.displayName, port, mysqlPassword, pgPassword }
  };
}

function removeUser(username) {
  const users = getUsers();
  const idx = users.findIndex(u => u.username === username);
  if (idx === -1) return { success: false, message: 'User tidak ditemukan.' };
  if (users[idx].role === 'admin') return { success: false, message: 'Admin tidak bisa dihapus.' };
  if (!isValidName(username)) return { success: false, message: 'Username tidak valid.' };

  const errors = [];

  // 1) Enumerate ACTUAL databases on each server matching <username>_* and drop them.
  //    This catches databases created out-of-band that aren't tracked in users.json.
  const myList = mysqlQuery(`SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE '${username}\\_%';`);
  if (myList.success) {
    myList.output.split('\n').map(s => s.trim()).filter(Boolean).forEach(full => {
      // full is e.g. "alice_default". Verify prefix actually matches before dropping.
      if (full.startsWith(username + '_')) {
        const r = mysqlQuery(`DROP DATABASE IF EXISTS \\\`${full}\\\`;`);
        if (!r.success) errors.push(`drop mysql ${full}: ${r.error}`);
      }
    });
  } else {
    errors.push('list mysql dbs: ' + myList.error);
  }

  const pgList = pgQuery(`SELECT datname FROM pg_database WHERE datname LIKE '${username}\\_%' ESCAPE '\\';`);
  if (pgList.success) {
    pgList.output.split('\n').map(s => s.trim()).filter(Boolean).forEach(full => {
      if (full.startsWith(username + '_') && /^[a-z][a-z0-9_]*$/.test(full)) {
        // Terminate active connections then drop
        pgQuery(`SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${full}' AND pid <> pg_backend_pid();`);
        const r = pgQuery(`DROP DATABASE IF EXISTS ${full};`);
        if (!r.success) errors.push(`drop pg ${full}: ${r.error}`);
      }
    });
  } else {
    errors.push('list pg dbs: ' + pgList.error);
  }

  // 2) Drop MySQL user
  const dropMy = mysqlQuery(`DROP USER IF EXISTS '${username}'@'%'; FLUSH PRIVILEGES;`);
  if (!dropMy.success) errors.push('drop mysql user: ' + dropMy.error);

  // 3) Drop Postgres role (reassign owned objects first to avoid dependency errors)
  const dropPg = pgQuery(`REASSIGN OWNED BY ${username} TO postgres; DROP OWNED BY ${username}; DROP ROLE IF EXISTS ${username};`);
  if (!dropPg.success) errors.push('drop pg role: ' + dropPg.error);

  // 4) Remove code-server container
  const dropCt = removeCodeServerContainer(username);
  if (!dropCt.success) errors.push('remove container: ' + dropCt.error);

  // 5) Remove user data folder
  try {
    fs.rmSync(`${USER_DATA_BASE}/${username}`, { recursive: true, force: true });
  } catch (e) { errors.push('rm data dir: ' + e.message); }

  // 6) Only remove from users.json if all destructive steps succeeded.
  //    Otherwise mark deletionPending so admin can retry safely.
  if (errors.length === 0) {
    users.splice(idx, 1);
    saveUsers(users);
    return { success: true, message: `User '${username}' dihapus bersih.`, warnings: [] };
  } else {
    users[idx].deletionPending = true;
    users[idx].deletionErrors = errors;
    users[idx].deletionAttemptedAt = new Date().toISOString();
    saveUsers(users);
    return {
      success: false,
      message: `User '${username}' GAGAL dihapus bersih (${errors.length} error). User ditandai 'deletionPending' — coba lagi setelah perbaikan manual.`,
      warnings: errors
    };
  }
}

function listUserDatabases(username) {
  const users = getUsers();
  const u = users.find(x => x.username === username);
  if (!u) return [];
  return u.databases || [];
}

function createDatabase(username, type, dbName) {
  if (!isValidName(dbName)) {
    return { success: false, message: 'Nama database hanya huruf kecil/angka/underscore, 2-31 karakter, mulai huruf.' };
  }
  if (!['mysql', 'postgres'].includes(type)) {
    return { success: false, message: 'Tipe database harus mysql atau postgres.' };
  }

  const users = getUsers();
  const u = users.find(x => x.username === username);
  if (!u) return { success: false, message: 'User tidak ditemukan.' };

  const existing = (u.databases || []).find(d => d.type === type && d.name === dbName);
  if (existing) return { success: false, message: `Database ${type}:${dbName} sudah ada.` };

  let r;
  if (type === 'mysql') r = createMysqlDatabase(username, dbName);
  else r = createPgDatabase(username, dbName);

  if (!r.success && !/already exists/i.test(r.error || '')) {
    return { success: false, message: 'Gagal buat database: ' + r.error };
  }

  if (!u.databases) u.databases = [];
  u.databases.push({ type, name: dbName, createdAt: new Date().toISOString() });
  saveUsers(users);

  return {
    success: true,
    message: `Database ${type}:${safeDbName(username, dbName)} berhasil dibuat.`,
    database: { type, name: dbName, fullName: safeDbName(username, dbName) }
  };
}

function dropDatabase(username, type, dbName) {
  // Strict validation — dbName goes into raw SQL identifier, no special chars allowed.
  if (!isValidName(dbName)) {
    return { success: false, message: 'Nama database tidak valid.' };
  }
  if (!['mysql', 'postgres'].includes(type)) {
    return { success: false, message: 'Tipe database tidak valid.' };
  }
  if (dbName === 'default') {
    return { success: false, message: 'Database default tidak bisa dihapus.' };
  }
  if (!isValidName(username)) {
    return { success: false, message: 'Username tidak valid.' };
  }

  const users = getUsers();
  const u = users.find(x => x.username === username);
  if (!u) return { success: false, message: 'User tidak ditemukan.' };

  let r;
  if (type === 'mysql') r = dropMysqlDatabase(username, dbName);
  else r = dropPgDatabase(username, dbName);

  u.databases = (u.databases || []).filter(d => !(d.type === type && d.name === dbName));
  saveUsers(users);

  return { success: r.success, message: r.success ? `Database ${type}:${dbName} dihapus.` : 'Gagal: ' + r.error };
}

/**
 * Untuk user lama yang belum punya credentials (created via add-user.sh sebelum upgrade).
 * Generate password baru, set ke MySQL & PG, dan simpan ke users.json.
 */
function repairUserCredentials(username) {
  const users = getUsers();
  const u = users.find(x => x.username === username);
  if (!u) return { success: false, message: 'User tidak ditemukan.' };
  if (u.role === 'admin') return { success: false, message: 'Admin tidak punya database user.' };

  const mysqlPassword = randomPassword(16);
  const pgPassword = randomPassword(16);

  const r1 = provisionMysqlUser(username, mysqlPassword);
  const r2 = createMysqlDatabase(username, 'default');
  const r3 = provisionPgUser(username, pgPassword);
  const r4 = createPgDatabase(username, 'default');

  u.mysqlPassword = mysqlPassword;
  u.pgPassword = pgPassword;
  if (!u.databases || u.databases.length === 0) {
    u.databases = [
      { type: 'mysql', name: 'default', createdAt: new Date().toISOString() },
      { type: 'postgres', name: 'default', createdAt: new Date().toISOString() }
    ];
  }
  saveUsers(users);

  return {
    success: true,
    message: `Credentials database '${username}' di-regenerate.`,
    mysqlPassword,
    pgPassword
  };
}

function getCredentials(username) {
  const users = getUsers();
  const u = users.find(x => x.username === username);
  if (!u) return null;
  return {
    mysqlPassword: u.mysqlPassword || null,
    pgPassword: u.pgPassword || null,
    databases: u.databases || []
  };
}

module.exports = {
  provisionUser,
  removeUser,
  listUserDatabases,
  createDatabase,
  dropDatabase,
  repairUserCredentials,
  getCredentials,
  safeDbName,
  isValidName
};
