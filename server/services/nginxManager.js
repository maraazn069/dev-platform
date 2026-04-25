const fs = require('fs');
const path = require('path');
const { reloadNginx } = require('./dockerExec');

// Path nginx.conf di dalam container portal (mounted dari ./nginx/nginx.conf di host)
const NGINX_CONF = '/app/nginx/nginx.conf';
// Per-user nginx confs: ./nginx/users/<user>.conf di-mount ke /etc/nginx/users/ di nginx container.
// Portal nulis ke /app/nginx/users/ (mounted rw).
const USERS_DIR = '/app/nginx/users';

function readConf() {
  try { return fs.readFileSync(NGINX_CONF, 'utf8'); } catch { return null; }
}

function writeConf(content) {
  fs.writeFileSync(NGINX_CONF, content);
}

function hasWildcardUserBlock(conf) {
  // Cek apakah nginx.conf udah pakai wildcard regex untuk user (HTTPS mode)
  // ATAU pakai include /etc/nginx/users/*.conf (Opsi C mode)
  return /\$username\.|<username>|~\^.+\\\.\$|include\s+\/etc\/nginx\/users/.test(conf || '');
}

function hasUserBlock(conf, username) {
  return new RegExp(`server_name\\s+${username}\\.`).test(conf || '');
}

function ensureUserSubdomain(username) {
  const conf = readConf();
  if (!conf) {
    return { success: false, message: 'nginx.conf tidak bisa dibaca dari portal (mount belum aktif?)' };
  }

  if (hasWildcardUserBlock(conf)) {
    // Mode HTTPS / Opsi C → user di-handle via wildcard / per-user conf file.
    // Kalau Opsi C (per-user cert), juga generate user conf-nya.
    if (/include\s+\/etc\/nginx\/users/.test(conf)) {
      const r = ensureUserConfig(username);
      return r;
    }
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

/**
 * OPSI C: per-user nginx conf.
 *
 * Generate /app/nginx/users/<user>.conf yg berisi:
 *   1. server_name <user>.DOMAIN → code-server UI (port 8443)
 *   2. wildcard regex ~^(?<project>...)\.user\.DOMAIN$ → code-server preview (port 3000)
 *
 * Cert default: /etc/letsencrypt/live/<user>.DOMAIN/ (request via provision-user-cert.sh).
 * Kalau cert per-user belum ada, fallback pakai *.DOMAIN cert (so user bisa langsung
 * akses code-server walaupun preview project-nya belum bisa HTTPS).
 */
// Strict validation supaya username gak bisa path-traversal lewat ke path.join.
// Username juga di-inject ke regex nginx — harus aman dari awal.
function isSafeUsername(username) {
  return typeof username === 'string' && /^[a-z][a-z0-9_]{1,30}$/.test(username);
}

function ensureUserConfig(username) {
  if (!isSafeUsername(username)) {
    return { success: false, message: `Username tidak valid: '${username}' (harus a-z, 0-9, _, max 31 char)` };
  }
  const domain = process.env.DOMAIN || 'netprem.org';
  if (!fs.existsSync(USERS_DIR)) {
    try { fs.mkdirSync(USERS_DIR, { recursive: true }); } catch (e) {
      return { success: false, message: 'Gagal buat dir nginx/users: ' + e.message };
    }
  }

  // Detect cert path: prefer per-user, fallback ke wildcard *.DOMAIN
  const perUserCert = `/etc/letsencrypt/live/${username}.${domain}/fullchain.pem`;
  const wildcardCert = `/etc/letsencrypt/live/${domain}/fullchain.pem`;
  // Kita pakai variable kosong & biarkan certbot config setelah cert ada — tapi
  // file harus REFERENSI sesuatu yg ada, kalau enggak nginx akan refuse start.
  // Strategy: generate dengan wildcard cert dulu (depth-1 only — preview project gak https sampai per-user cert ready).
  // Setelah provision-user-cert.sh sukses, regenerate dengan per-user cert.
  let certPath = wildcardCert;
  let certKey = wildcardCert.replace('fullchain', 'privkey');
  let useUserCert = false;
  try {
    if (fs.existsSync(perUserCert)) {
      certPath = perUserCert;
      certKey = perUserCert.replace('fullchain', 'privkey');
      useUserCert = true;
    }
  } catch {}

  const previewBlock = useUserCert ? `
    # Preview port 3000 di container user — semua subdomain project route ke sini.
    # User jalankan dev server di port 3000 (npm run dev / python -m http.server 3000 dst).
    server {
        listen 443 ssl;
        http2 on;
        server_name ~^(?<project>[a-z0-9][a-z0-9-]*)\\.${username}\\.${domain.replace(/\./g, '\\.')}$;

        ssl_certificate ${perUserCert};
        ssl_certificate_key ${perUserCert.replace('fullchain', 'privkey')};
        ssl_protocols TLSv1.2 TLSv1.3;

        client_max_body_size 50M;

        location / {
            set $upstream_preview "codeserver-${username}:3000";
            proxy_pass http://$upstream_preview;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 86400s;
        }
    }
` : `
    # Preview project (depth-2) belum aktif — cert *.${username}.${domain} belum ready.
    # Jalankan: sudo bash scripts/provision-user-cert.sh ${username}
`;

  const conf = `# Auto-generated by portal nginxManager.js
# User: ${username}
# Per-user cert: ${useUserCert ? 'ACTIVE' : 'pending — run scripts/provision-user-cert.sh ' + username}

server {
    listen 80;
    server_name ${username}.${domain} *.${username}.${domain};
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;
    server_name ${username}.${domain};

    ssl_certificate ${certPath};
    ssl_certificate_key ${certKey};
    ssl_protocols TLSv1.2 TLSv1.3;

    client_max_body_size 50M;

    location / {
        set $upstream_cs "codeserver-${username}:8443";
        proxy_pass http://$upstream_cs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Accept-Encoding gzip;
        proxy_read_timeout 86400s;
    }
}
${previewBlock}
`;

  const filePath = path.join(USERS_DIR, `${username}.conf`);
  // Defense-in-depth: pastikan path masih di dalam USERS_DIR (anti-traversal)
  if (path.dirname(path.resolve(filePath)) !== path.resolve(USERS_DIR)) {
    return { success: false, message: 'Path conf user keluar dari users dir — ditolak' };
  }
  // Atomic write: tulis ke .tmp dulu, rename. Mencegah nginx baca file separuh saat reload.
  const tmpPath = filePath + '.tmp';
  try {
    fs.writeFileSync(tmpPath, conf);
    fs.renameSync(tmpPath, filePath);
  } catch (e) {
    try { fs.unlinkSync(tmpPath); } catch {}
    return { success: false, message: 'Gagal tulis ' + filePath + ': ' + e.message };
  }

  const reload = reloadNginx();
  return {
    success: true,
    message: `nginx user-conf ${username}.conf ditulis (preview ${useUserCert ? 'AKTIF' : 'pending cert'}). Reload: ${reload.success ? 'ok' : reload.error}`
  };
}

function removeUserConfig(username) {
  if (!isSafeUsername(username)) {
    return { success: false, message: `Username tidak valid: '${username}'` };
  }
  const filePath = path.join(USERS_DIR, `${username}.conf`);
  if (path.dirname(path.resolve(filePath)) !== path.resolve(USERS_DIR)) {
    return { success: false, message: 'Path conf user keluar dari users dir — ditolak' };
  }
  try {
    if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
  } catch (e) {
    return { success: false, message: 'Gagal hapus ' + filePath + ': ' + e.message };
  }
  const reload = reloadNginx();
  return { success: true, message: `nginx user-conf ${username}.conf dihapus. Reload: ${reload.success ? 'ok' : reload.error}` };
}

module.exports = { ensureUserSubdomain, ensureUserConfig, removeUserConfig };
