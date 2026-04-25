const fs = require('fs');
const path = require('path');
const { reloadNginx } = require('./dockerExec');

// Path nginx.conf di dalam container portal (mounted dari ./nginx/nginx.conf di host)
const NGINX_CONF = '/app/nginx/nginx.conf';

function readConf() {
  try { return fs.readFileSync(NGINX_CONF, 'utf8'); } catch { return null; }
}

function writeConf(content) {
  fs.writeFileSync(NGINX_CONF, content);
}

/**
 * Cek apakah nginx.conf sudah pakai wildcard regex untuk subdomain user.
 * Kalau iya, tidak perlu tambah server block manual.
 */
function hasWildcardUserBlock(conf) {
  return /\$username\.|<username>|~\^.+\\\.\$/.test(conf || '');
}

function hasUserBlock(conf, username) {
  return new RegExp(`server_name\\s+${username}\\.`).test(conf || '');
}

/**
 * Tambah server block nginx untuk subdomain user.
 * Kalau wildcard sudah aktif (HTTPS mode), skip.
 */
function ensureUserSubdomain(username) {
  const conf = readConf();
  if (!conf) {
    return { success: false, message: 'nginx.conf tidak bisa dibaca dari portal (mount belum aktif?)' };
  }

  if (hasWildcardUserBlock(conf)) {
    return { success: true, message: 'wildcard nginx aktif, subdomain auto-handled' };
  }

  if (hasUserBlock(conf, username)) {
    return { success: true, message: 'subdomain sudah ada di nginx.conf' };
  }

  const domain = process.env.DOMAIN || 'dev.example.com';
  const block = `
    server {
        listen 80;
        server_name ${username}.${domain};

        location / {
            proxy_pass http://codeserver-${username}:8443;
            proxy_set_header Host $host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_read_timeout 86400s;
        }
    }
`;

  // Insert sebelum closing http { } block (last "}")
  const lastBrace = conf.lastIndexOf('}');
  if (lastBrace === -1) return { success: false, message: 'nginx.conf format tidak dikenal' };

  const newConf = conf.slice(0, lastBrace) + block + '\n' + conf.slice(lastBrace);
  writeConf(newConf);

  const reload = reloadNginx();
  return {
    success: true,
    message: reload.success ? 'nginx subdomain ditambah & direload' : 'nginx subdomain ditambah, tapi reload gagal: ' + reload.error
  };
}

module.exports = { ensureUserSubdomain };
