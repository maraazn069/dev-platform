const { execSync, execFileSync } = require('child_process');
const crypto = require('crypto');

function randomPassword(length = 16) {
  return crypto.randomBytes(length).toString('base64')
    .replace(/[+/=]/g, '')
    .slice(0, length);
}

function dockerExec(container, args, opts = {}) {
  try {
    const output = execFileSync('docker', ['exec', container, ...args], {
      encoding: 'utf8',
      timeout: opts.timeout || 15000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return { success: true, output: output.trim() };
  } catch (err) {
    return {
      success: false,
      error: (err.stderr ? err.stderr.toString() : '') + (err.message || ''),
      output: err.stdout ? err.stdout.toString().trim() : ''
    };
  }
}

/**
 * Like dockerExec but pipes SQL/text via stdin into the container's stdin.
 * Use this for SQL execution to avoid shell-quoting injection.
 */
function dockerExecStdin(container, args, input, opts = {}) {
  try {
    const output = execFileSync('docker', ['exec', '-i', container, ...args], {
      encoding: 'utf8',
      input,
      timeout: opts.timeout || 15000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return { success: true, output: output.trim() };
  } catch (err) {
    return {
      success: false,
      error: (err.stderr ? err.stderr.toString() : '') + (err.message || ''),
      output: err.stdout ? err.stdout.toString().trim() : ''
    };
  }
}

function dockerCmd(args, opts = {}) {
  try {
    const output = execFileSync('docker', args, {
      encoding: 'utf8',
      timeout: opts.timeout || 15000,
      stdio: ['pipe', 'pipe', 'pipe']
    });
    return { success: true, output: output.trim() };
  } catch (err) {
    return {
      success: false,
      error: (err.stderr ? err.stderr.toString() : '') + (err.message || ''),
      output: err.stdout ? err.stdout.toString().trim() : ''
    };
  }
}

/**
 * Run SQL against MySQL via stdin to avoid any shell/argv quoting concerns.
 * SQL is fed to `mysql` over stdin; identifiers must still be validated by callers.
 */
function mysqlQuery(sql) {
  const rootPw = process.env.MYSQL_ROOT_PASSWORD || '';
  return dockerExecStdin(
    'devplatform-mysql',
    ['mysql', '-uroot', `-p${rootPw}`, '-N', '-B'],
    sql
  );
}

/**
 * Run SQL against Postgres via stdin (no `sh -c`, no shell quoting).
 * SQL is fed to `psql` over stdin; identifiers must still be validated by callers.
 */
function pgQuery(sql, db = 'postgres') {
  const pgPw = process.env.POSTGRES_PASSWORD || '';
  return dockerExecStdin(
    'devplatform-postgres',
    ['env', `PGPASSWORD=${pgPw}`, 'psql', '-U', 'postgres', '-d', db, '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
    sql
  );
}

function dockerNetworkName() {
  const res = dockerCmd(['network', 'ls', '--format', '{{.Name}}']);
  if (!res.success) return 'dev-platform_devplatform';
  const line = res.output.split('\n').find(n => n.includes('devplatform'));
  return line || 'dev-platform_devplatform';
}

function reloadNginx() {
  const res = dockerCmd(['exec', 'nginx-proxy', 'nginx', '-s', 'reload']);
  if (!res.success) {
    return dockerCmd(['restart', 'nginx-proxy']);
  }
  return res;
}

function containerExists(name) {
  const res = dockerCmd(['ps', '-a', '--format', '{{.Names}}']);
  if (!res.success) return false;
  return res.output.split('\n').includes(name);
}

module.exports = {
  randomPassword,
  dockerExec,
  dockerExecStdin,
  dockerCmd,
  mysqlQuery,
  pgQuery,
  dockerNetworkName,
  reloadNginx,
  containerExists
};
