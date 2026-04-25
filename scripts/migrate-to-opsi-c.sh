#!/usr/bin/env bash
# Migrasi VPS existing ke struktur Opsi C:
#   - Portal: <DOMAIN> (apex, contoh: netprem.org)
#   - User code-server: <user>.<DOMAIN>
#   - Project preview: <project>.<user>.<DOMAIN>
#   - Cert depth-1: *.<DOMAIN>  (covers user code-server + services)
#   - Cert per user depth-2: *.<user>.<DOMAIN>  (covers project preview)
#
# Pakai (di VPS):
#   sudo bash scripts/migrate-to-opsi-c.sh
#
# WAJIB SEBELUM JALANKAN:
#   1. Backup dulu! sudo bash scripts/backup-to-r2.sh
#   2. Update DNS Cloudflare:
#      - DOMAIN (apex) → IP VPS  (proxy OFF saat migration, bisa ON setelah selesai)
#      - *.DOMAIN → IP VPS  (proxy ON ok kalau pakai apex DOMAIN)
#      - Untuk tiap user yg sudah ada: *.<user>.DOMAIN → IP VPS
#   3. .env udah pakai DOMAIN baru (apex), simpan DOMAIN_OLD kalau perlu rollback

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

: "${DOMAIN:?DOMAIN belum diset di .env (harus apex, contoh: netprem.org)}"
: "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL belum diset}"

# Pastikan DOMAIN bukan subdomain (cek kasar: tidak boleh contain dev. di awal)
if [[ "$DOMAIN" == dev.* ]] || [[ "$DOMAIN" == *.*.*.* ]]; then
  echo "⚠ DOMAIN='$DOMAIN' kelihatan masih sub-domain."
  echo "  Untuk Opsi C, set DOMAIN ke apex (contoh: netprem.org)."
  read -p "Lanjut juga? Ketik YES: " C
  [ "$C" = "YES" ] || exit 0
fi

echo "════════════════════════════════════════════════════════"
echo "  MIGRASI ke struktur OPSI C"
echo "  DOMAIN apex : $DOMAIN"
echo "  Portal      : https://$DOMAIN"
echo "  User VS     : https://<user>.$DOMAIN"
echo "  Preview     : https://<project>.<user>.$DOMAIN"
echo "════════════════════════════════════════════════════════"
echo ""
echo "⚠ Migration akan:"
echo "  1) Re-issue wildcard cert *.$DOMAIN (kalau belum ada)"
echo "  2) Regenerate nginx.conf dengan include /etc/nginx/users/*.conf"
echo "  3) Untuk tiap user di users.json: request cert *.<user>.$DOMAIN + tulis user.conf"
echo "  4) Restart nginx + portal"
echo ""
read -p "Sudah backup? Sudah update DNS? Ketik YES: " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Dibatalkan."; exit 0; }

# ── 1) Wildcard cert *.DOMAIN
echo ""
echo "[1/4] Cek/issue wildcard cert *.${DOMAIN}..."
if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
  echo "  → Cert belum ada, jalankan setup-https.sh"
  bash scripts/setup-https.sh
else
  echo "  ✓ Cert *.${DOMAIN} udah ada"
fi

# ── 2) Update docker-compose untuk mount nginx/users folder
echo ""
echo "[2/4] Update docker-compose.yml untuk mount nginx/users folder..."
mkdir -p nginx/users
if ! grep -q "nginx/users" docker-compose.yml; then
  # Insert mount setelah baris nginx.conf mount
  sed -i 's|\(- ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro\)|\1\n      - ./nginx/users:/etc/nginx/users:ro|' docker-compose.yml
  echo "  ✓ Mount ditambah"
else
  echo "  ✓ Mount nginx/users sudah ada"
fi

# ── 3) Regenerate nginx.conf dengan include directive
echo ""
echo "[3/4] Regenerate nginx.conf (include users/*.conf)..."

# BACKUP nginx.conf existing dulu — script ini destructive, user bisa restore manual
# kalau ada custom hardening / extra server block yang hilang.
if [ -f nginx/nginx.conf ]; then
  BACKUP_PATH="nginx/nginx.conf.bak-$(date +%Y%m%d-%H%M%S)"
  cp nginx/nginx.conf "$BACKUP_PATH"
  echo "  ✓ Backup nginx.conf lama → $BACKUP_PATH"
  echo "    (kalau ada custom config yg hilang, copy manual dari sini)"
fi

cat > nginx/nginx.conf <<NGINXEOF
events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=30s ipv6=off;

    # HTTP → HTTPS redirect (semua subdomain)
    server {
        listen 80;
        server_name __DOMAIN__ *.__DOMAIN__;
        return 301 https://\$host\$request_uri;
    }

    # Portal utama (apex)
    server {
        listen 443 ssl;
        http2 on;
        server_name __DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        client_max_body_size 50M;

        location / {
            set \$upstream_portal "devplatform-portal:3000";
            proxy_pass http://\$upstream_portal;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 60s;
        }
    }

    # Services depth-1 (semua pakai *.DOMAIN cert)
    server {
        listen 443 ssl;
        http2 on;
        server_name mysql.__DOMAIN__;
        client_max_body_size 256M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set \$upstream_pma "devplatform-phpmyadmin:80";
            proxy_pass http://\$upstream_pma;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Proto https;
        }
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name pgadmin.__DOMAIN__;
        client_max_body_size 50M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set \$upstream_pga "devplatform-pgadmin:80";
            proxy_pass http://\$upstream_pga;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Script-Name "";
        }
    }

    server {
        listen 443 ssl;
        http2 on;
        server_name files.__DOMAIN__;
        client_max_body_size 2048M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set \$upstream_fb "devplatform-filebrowser:80";
            proxy_pass http://\$upstream_fb;
            proxy_set_header Host \$host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
        }
    }

    # Per-user subdomain & project preview — di-include dari per-user file.
    # Generated otomatis oleh portal (server/services/nginxManager.js).
    include /etc/nginx/users/*.conf;

    # Catch-all
    server {
        listen 443 ssl default_server;
        http2 on;
        server_name _;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        return 404;
    }
}
NGINXEOF
# Validasi DOMAIN safe untuk sed — tolak kalau ada karakter aneh
if ! [[ "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
  echo "❌ DOMAIN '$DOMAIN' mengandung karakter berbahaya untuk sed substitution"
  exit 2
fi
sed -i "s|__DOMAIN__|$DOMAIN|g" nginx/nginx.conf
echo "  ✓ nginx.conf regenerated"

# Reload services biar mount baru aktif
echo ""
echo "  → Restart nginx untuk apply mount baru..."
docker compose up -d nginx
sleep 3

# ── 4) Per-user cert + nginx conf
echo ""
echo "[4/4] Provision cert + nginx conf per user..."
USERS_FILE="server/data/users.json"
if [ ! -f "$USERS_FILE" ]; then
  echo "  ⚠ users.json gak ada, skip per-user provisioning."
else
  USERNAMES=$(node -e "
    const u = require('./$USERS_FILE');
    u.filter(x => x.role !== 'admin').forEach(x => console.log(x.username));
  " 2>/dev/null || echo "")

  if [ -z "$USERNAMES" ]; then
    echo "  ⚠ Tidak ada non-admin user di users.json. Skip."
  else
    echo "$USERNAMES" | while read -r U; do
      [ -z "$U" ] && continue
      echo ""
      echo "  ─── User: $U ───"
      echo "  → Request cert *.${U}.${DOMAIN}..."
      if bash scripts/provision-user-cert.sh "$U"; then
        echo "  ✓ Cert ${U}.${DOMAIN} ready"
      else
        echo "  ⚠ Cert ${U}.${DOMAIN} gagal — lanjut dengan wildcard fallback"
      fi
    done
  fi
fi

# ── Restart portal supaya regenerate user.conf via nginxManager
echo ""
echo "→ Restart portal..."
docker compose restart portal
sleep 5

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ Migrasi Opsi C SELESAI"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Cek manual:"
echo "  - Portal: https://$DOMAIN"
echo "  - Admin login → klik 🔧 Repair Container per user → regenerate user.conf"
echo "  - Test user: https://<user>.$DOMAIN"
echo "  - Test preview: https://<project>.<user>.$DOMAIN (jalankan dev server di port 3000 dulu)"
echo ""
echo "Kalau ada user 502 di subdomain:"
echo "  bash scripts/diagnose-502.sh <user>"
echo ""
