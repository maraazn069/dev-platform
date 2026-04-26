#!/bin/bash
# ================================================================
# regenerate-nginx-main.sh — Regenerate nginx/nginx.conf utama
#
# Idempotent. Hanya regenerate nginx.conf utama dengan template
# HTTPS lengkap (port 443, include users/*.conf, server block untuk
# portal/files/mysql/pgadmin/wildcard code-server).
#
# AMAN dipanggil kapan saja — TIDAK request cert ulang, TIDAK ubah
# Cloudflare token, TIDAK touch user.conf.
#
# Cara pakai:
#   sudo bash scripts/regenerate-nginx-main.sh
# ================================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan sebagai root: sudo bash scripts/regenerate-nginx-main.sh${NC}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo -e "${RED}File .env tidak ditemukan.${NC}"
  exit 1
fi

set -a; source "$PROJECT_DIR/.env"; set +a

if [ -z "$DOMAIN" ]; then
  echo -e "${RED}DOMAIN wajib ada di .env${NC}"
  exit 1
fi

CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
if [ ! -f "$CERT_PATH" ]; then
  echo -e "${RED}Cert apex tidak ditemukan: $CERT_PATH${NC}"
  echo -e "${YELLOW}Jalankan dulu: sudo bash scripts/setup-https.sh${NC}"
  exit 1
fi

# Backup nginx.conf lama
BACKUP="$PROJECT_DIR/nginx/nginx.conf.bak.$(date +%s)"
[ -f "$PROJECT_DIR/nginx/nginx.conf" ] && cp "$PROJECT_DIR/nginx/nginx.conf" "$BACKUP" && \
  echo -e "${CYAN}→ Backup nginx.conf lama: $BACKUP${NC}"

# Pastikan dir users ada
mkdir -p "$PROJECT_DIR/nginx/users"

# Tulis nginx.conf dari template
cat > "$PROJECT_DIR/nginx/nginx.conf" << 'NGINXEOF'
events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=30s ipv6=off;

    # ---- HTTP → HTTPS redirect (apex + semua subdomain) ----
    server {
        listen 80;
        server_name __DOMAIN__ *.__DOMAIN__;
        return 301 https://$host$request_uri;
    }

    # ---- Portal apex ----
    server {
        listen 443 ssl;
        http2 on;
        server_name __DOMAIN__;

        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;

        client_max_body_size 50M;

        location / {
            set $upstream_portal "devplatform-portal:3000";
            proxy_pass http://$upstream_portal;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_read_timeout 60s;
        }
    }

    # ---- phpMyAdmin (mysql.<domain>) ----
    server {
        listen 443 ssl;
        http2 on;
        server_name mysql.__DOMAIN__;
        client_max_body_size 256M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set $upstream_pma "devplatform-phpmyadmin:80";
            proxy_pass http://$upstream_pma;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto https;
        }
    }

    # ---- pgAdmin (pgadmin.<domain>) ----
    server {
        listen 443 ssl;
        http2 on;
        server_name pgadmin.__DOMAIN__;
        client_max_body_size 50M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set $upstream_pga "devplatform-pgadmin:80";
            proxy_pass http://$upstream_pga;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_set_header X-Script-Name "";
        }
    }

    # ---- File Browser (files.<domain>) ----
    server {
        listen 443 ssl;
        http2 on;
        server_name files.__DOMAIN__;
        client_max_body_size 2048M;
        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        location / {
            set $upstream_fb "devplatform-filebrowser:80";
            proxy_pass http://$upstream_fb;
            proxy_set_header Host $host;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
        }
    }

    # ---- OPSI C: per-user subdomain & project preview ----
    # Generated otomatis oleh portal (server/services/nginxManager.js → ensureUserConfig).
    # Setiap user.conf punya server block 443 untuk <user>.DOMAIN + *.<user>.DOMAIN.
    include /etc/nginx/users/*.conf;

    # ---- Fallback wildcard *.<domain> (kalau user.conf belum ada) ----
    server {
        listen 443 ssl;
        http2 on;
        server_name ~^(?<username>[a-z][a-z0-9_]+)\.__DOMAIN__$;

        ssl_certificate /etc/letsencrypt/live/__DOMAIN__/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/__DOMAIN__/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            set $upstream_cs "codeserver-$username:8443";
            proxy_pass http://$upstream_cs;
            proxy_set_header Host $host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 86400s;
        }
    }

    # ---- Catch-all → redirect ke portal ----
    server {
        listen 80 default_server;
        server_name _;
        return 301 https://__DOMAIN__$request_uri;
    }
}
NGINXEOF

# Substitusi placeholder dengan domain asli
sed -i "s|__DOMAIN__|$DOMAIN|g" "$PROJECT_DIR/nginx/nginx.conf"

echo -e "${GREEN}✓ nginx.conf di-regenerate (HTTPS + include users/*.conf)${NC}"

# Restart nginx-proxy
echo -e "${CYAN}→ Restart nginx-proxy...${NC}"
docker restart nginx-proxy >/dev/null 2>&1 || docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d nginx
sleep 3

# Cek nginx tidak crash
if docker ps --filter name=nginx-proxy --format '{{.Status}}' | grep -q "Up"; then
  echo -e "${GREEN}✓ nginx-proxy UP${NC}"
else
  echo -e "${RED}✗ nginx-proxy crash — cek log:${NC}"
  docker logs --tail 20 nginx-proxy
  exit 1
fi

# Test syntax dari dalam container
docker exec nginx-proxy nginx -t 2>&1 | tail -2

echo ""
echo -e "${GREEN}✅ DONE${NC}"
echo "Test:"
echo "  curl -sk -o /dev/null -w '%{http_code}\n' https://localhost/ -H 'Host: $DOMAIN'"
