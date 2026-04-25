const fs = require('fs');
const https = require('https');

// ============================================================================
// Cloudflare DNS auto-management
//
// Tujuan: saat admin create user baru, otomatis bikin DNS A record
//   *.<username>.<DOMAIN>  →  VPS_PUBLIC_IP
// Supaya project preview <project>.<user>.<DOMAIN> bisa di-resolve di browser.
// (Wildcard *.<DOMAIN> di apex hanya cover depth-1, bukan depth-2.)
//
// Token CF dibaca dari /etc/cloudflare/cloudflare.ini (di-mount dari host)
// ATAU dari env CLOUDFLARE_API_TOKEN.
//
// Zone ID di-auto-discover dari DOMAIN (cached in-memory).
// VPS public IP di-baca dari env VPS_PUBLIC_IP, fallback auto-detect via API.
// ============================================================================

const CF_INI_PATH = '/etc/cloudflare/cloudflare.ini';
const CF_API = 'api.cloudflare.com';

let cachedZoneId = null;
let cachedToken = null;
let cachedVpsIp = null;
let disabled = false;
let warnedDisable = false;

function readToken() {
  if (cachedToken) return cachedToken;
  // Priority: env > file
  if (process.env.CLOUDFLARE_API_TOKEN) {
    cachedToken = process.env.CLOUDFLARE_API_TOKEN.trim();
    return cachedToken;
  }
  try {
    if (fs.existsSync(CF_INI_PATH)) {
      const ini = fs.readFileSync(CF_INI_PATH, 'utf8');
      const m = ini.match(/dns_cloudflare_api_token\s*=\s*(\S+)/);
      if (m) {
        cachedToken = m[1].trim();
        return cachedToken;
      }
    }
  } catch {}
  return null;
}

function disableOnce(reason) {
  disabled = true;
  if (!warnedDisable) {
    console.warn(`[cloudflareDns] DISABLED: ${reason}. DNS record per user TIDAK akan auto-created. Tambahkan manual di Cloudflare dashboard, atau set CLOUDFLARE_API_TOKEN + VPS_PUBLIC_IP di .env.`);
    warnedDisable = true;
  }
}

function cfRequest(method, pathName, body = null) {
  return new Promise((resolve) => {
    const token = readToken();
    if (!token) return resolve({ ok: false, error: 'no token' });

    const data = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: CF_API,
      port: 443,
      path: pathName,
      method,
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {})
      },
      timeout: 15000
    };

    const req = https.request(opts, (res) => {
      let buf = '';
      res.on('data', (chunk) => { buf += chunk; });
      res.on('end', () => {
        try {
          const parsed = JSON.parse(buf);
          resolve({ ok: parsed.success === true, data: parsed.result, errors: parsed.errors, status: res.statusCode });
        } catch (e) {
          resolve({ ok: false, error: 'parse: ' + e.message, raw: buf.slice(0, 200) });
        }
      });
    });
    req.on('error', (e) => resolve({ ok: false, error: e.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
    if (data) req.write(data);
    req.end();
  });
}

async function getZoneId(domain) {
  if (cachedZoneId) return cachedZoneId;
  const r = await cfRequest('GET', `/client/v4/zones?name=${encodeURIComponent(domain)}`);
  if (!r.ok || !Array.isArray(r.data) || r.data.length === 0) {
    return null;
  }
  cachedZoneId = r.data[0].id;
  return cachedZoneId;
}

async function getVpsIp() {
  if (cachedVpsIp) return cachedVpsIp;
  if (process.env.VPS_PUBLIC_IP) {
    cachedVpsIp = process.env.VPS_PUBLIC_IP.trim();
    return cachedVpsIp;
  }
  // Fallback: query an external IP service (fast, cached forever in-memory)
  try {
    const ip = await new Promise((resolve, reject) => {
      const req = https.get({ hostname: 'api.ipify.org', port: 443, path: '/', timeout: 5000 }, (res) => {
        let buf = '';
        res.on('data', (c) => { buf += c; });
        res.on('end', () => resolve(buf.trim()));
      });
      req.on('error', reject);
      req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    });
    if (/^\d+\.\d+\.\d+\.\d+$/.test(ip)) {
      cachedVpsIp = ip;
      return cachedVpsIp;
    }
  } catch {}
  return null;
}

function isSafeUsername(username) {
  return typeof username === 'string' && /^[a-z][a-z0-9_]{1,30}$/.test(username);
}

async function findRecordId(zoneId, fullName, type = 'A') {
  const r = await cfRequest('GET', `/client/v4/zones/${zoneId}/dns_records?type=${type}&name=${encodeURIComponent(fullName)}`);
  if (!r.ok || !Array.isArray(r.data) || r.data.length === 0) return null;
  return r.data[0].id;
}

/**
 * Pastikan DNS record A *.<username>.<domain> → VPS_IP ada di Cloudflare.
 * Idempotent: kalau sudah ada dengan IP yang benar → no-op.
 * Kalau ada tapi IP beda → update.
 */
async function ensureUserSubdomainDns(username) {
  if (disabled) return { ok: true, skipped: true };
  if (!isSafeUsername(username)) {
    return { ok: false, error: `username tidak valid: ${username}` };
  }
  const token = readToken();
  if (!token) {
    disableOnce('CLOUDFLARE_API_TOKEN tidak diset & /etc/cloudflare/cloudflare.ini tidak ada');
    return { ok: true, skipped: true };
  }

  const domain = process.env.DOMAIN || 'netprem.org';
  const ip = await getVpsIp();
  if (!ip) {
    disableOnce('VPS_PUBLIC_IP tidak ke-detect (set di .env atau pastikan VPS bisa akses api.ipify.org)');
    return { ok: true, skipped: true };
  }

  const zoneId = await getZoneId(domain);
  if (!zoneId) {
    disableOnce(`Zone ${domain} tidak ditemukan di Cloudflare (cek token punya akses ke zone ini)`);
    return { ok: true, skipped: true };
  }

  const fullName = `*.${username}.${domain}`;
  const existingId = await findRecordId(zoneId, fullName, 'A');

  const payload = {
    type: 'A',
    name: fullName,
    content: ip,
    ttl: 1,           // 1 = automatic
    proxied: false    // direct A record (proxy off — supaya cert Let's Encrypt langsung resolve)
  };

  if (existingId) {
    const r = await cfRequest('PUT', `/client/v4/zones/${zoneId}/dns_records/${existingId}`, payload);
    if (r.ok) return { ok: true, action: 'updated', name: fullName, ip };
    return { ok: false, error: `update failed: ${JSON.stringify(r.errors || r.error)}` };
  } else {
    const r = await cfRequest('POST', `/client/v4/zones/${zoneId}/dns_records`, payload);
    if (r.ok) return { ok: true, action: 'created', name: fullName, ip };
    return { ok: false, error: `create failed: ${JSON.stringify(r.errors || r.error)}` };
  }
}

async function removeUserSubdomainDns(username) {
  if (disabled) return { ok: true, skipped: true };
  if (!isSafeUsername(username)) return { ok: false, error: `username tidak valid: ${username}` };
  const token = readToken();
  if (!token) return { ok: true, skipped: true };

  const domain = process.env.DOMAIN || 'netprem.org';
  const zoneId = await getZoneId(domain);
  if (!zoneId) return { ok: true, skipped: true };

  const fullName = `*.${username}.${domain}`;
  const existingId = await findRecordId(zoneId, fullName, 'A');
  if (!existingId) return { ok: true, action: 'not-found', name: fullName };

  const r = await cfRequest('DELETE', `/client/v4/zones/${zoneId}/dns_records/${existingId}`, null);
  if (r.ok) return { ok: true, action: 'deleted', name: fullName };
  return { ok: false, error: `delete failed: ${JSON.stringify(r.errors || r.error)}` };
}

module.exports = {
  ensureUserSubdomainDns,
  removeUserSubdomainDns
};
