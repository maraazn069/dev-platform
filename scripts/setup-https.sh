#!/bin/bash
# ================================================================
# setup-https.sh — Setup HTTPS dengan Let's Encrypt (Wildcard)
#
# Wildcard cert (*.dev.netprem.org) via Cloudflare DNS Challenge
# sehingga semua subdomain user langsung dapat HTTPS.
#
# Cara pakai:
#   sudo bash scripts/setup-https.sh
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan sebagai root: sudo bash scripts/setup-https.sh${NC}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$PROJECT_DIR/.env" ]; then
  echo -e "${RED}File .env tidak ditemukan.${NC}"
  exit 1
fi

set -a; source "$PROJECT_DIR/.env"; set +a

if [ -z "$DOMAIN" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
  echo -e "${RED}DOMAIN dan LETSENCRYPT_EMAIL wajib ada di .env${NC}"
  exit 1
fi

echo -e "${CYAN}${BOLD}Setup HTTPS Wildcard untuk $DOMAIN${NC}"
echo ""
echo -e "Domain utama   : ${YELLOW}$DOMAIN${NC}"
echo -e "Wildcard       : ${YELLOW}*.$DOMAIN${NC}"
echo -e "Email          : ${YELLOW}$LETSENCRYPT_EMAIL${NC}"
echo ""

# Install certbot dan plugin Cloudflare
echo -e "${CYAN}Install certbot + plugin Cloudflare...${NC}"
apt install -y -qq certbot python3-certbot-dns-cloudflare
echo -e "${GREEN}✓ Certbot siap${NC}"

# Minta Cloudflare API Token
echo ""
echo -e "${YELLOW}Buka Cloudflare Dashboard → My Profile → API Tokens${NC}"
echo -e "${YELLOW}Buat token dengan permission: Zone → DNS → Edit${NC}"
echo ""
read -p "$(echo -e ${YELLOW})Masukkan Cloudflare API Token: $(echo -e ${NC})" CF_TOKEN

mkdir -p /etc/cloudflare
cat > /etc/cloudflare/cloudflare.ini << CFEOF
dns_cloudflare_api_token = $CF_TOKEN
CFEOF
chmod 600 /etc/cloudflare/cloudflare.ini
echo -e "${GREEN}✓ Cloudflare credentials disimpan${NC}"

# Stop nginx sementara
echo -e "${CYAN}Stop nginx sementara...${NC}"
docker compose -f "$PROJECT_DIR/docker-compose.yml" stop nginx 2>/dev/null || true

# Minta wildcard certificate
echo -e "${CYAN}Minta sertifikat SSL wildcard...${NC}"
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /etc/cloudflare/cloudflare.ini \
  --non-interactive \
  --agree-tos \
  --email "$LETSENCRYPT_EMAIL" \
  -d "$DOMAIN" \
  -d "*.$DOMAIN" \
  --keep-until-expiring

echo -e "${GREEN}✓ Sertifikat wildcard berhasil: $DOMAIN dan *.$DOMAIN${NC}"

# Generate nginx.conf dengan HTTPS + wildcard
echo -e "${CYAN}Update konfigurasi Nginx untuk HTTPS...${NC}"
cat > "$PROJECT_DIR/nginx/nginx.conf" << NGINXEOF
events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=30s ipv6=off;

    # ---- Redirect semua HTTP → HTTPS ----
    server {
        listen 80;
        server_name $DOMAIN *.$DOMAIN;
        return 301 https://\$host\$request_uri;
    }

    # ---- Portal utama (HTTPS) ----
    server {
        listen 443 ssl;
        server_name $DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;

        client_max_body_size 50M;

        location / {
            proxy_pass http://devplatform-portal:3000;
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

    # ---- Adminer DB (HTTPS) ----
    server {
        listen 443 ssl;
        server_name db-admin.$DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://devplatform-adminer:8080;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }
    }

    # ---- Wildcard subdomain user → code-server (HTTPS) ----
    server {
        listen 443 ssl;
        server_name ~^(?<username>[a-z][a-z0-9]+)\.$DOMAIN\$;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass http://codeserver-\$username:8443;
            proxy_set_header Host \$host;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_set_header X-Forwarded-Proto https;
            proxy_read_timeout 86400s;
        }
    }

    # ---- Catch-all ----
    server {
        listen 80 default_server;
        server_name _;
        return 301 https://$DOMAIN\$request_uri;
    }
}
NGINXEOF

echo -e "${GREEN}✓ nginx.conf diupdate dengan HTTPS${NC}"

# Update .env supaya portal pakai HTTPS
sed -i 's|^PROTOCOL=.*|PROTOCOL=https|' "$PROJECT_DIR/.env" 2>/dev/null || \
  echo "PROTOCOL=https" >> "$PROJECT_DIR/.env"

# Rebuild portal supaya URL project pakai https://
docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d --build portal

# Start nginx dengan config HTTPS baru
docker compose -f "$PROJECT_DIR/docker-compose.yml" start nginx
sleep 5

# Setup auto-renew
cat > /etc/cron.d/certbot-renew << CRONEOF
0 3 1,15 * * root certbot renew --quiet --post-hook "docker restart nginx-proxy"
CRONEOF
chmod 644 /etc/cron.d/certbot-renew

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ================================================"
echo "  ✓ HTTPS berhasil dikonfigurasi!"
echo "  ================================================"
echo -e "${NC}"
echo -e "  Portal    : ${CYAN}https://$DOMAIN${NC}"
echo -e "  DB Admin  : ${CYAN}https://db-admin.$DOMAIN${NC}"
echo -e "  User VS Code: ${CYAN}https://USERNAME.$DOMAIN${NC}"
echo ""
echo -e "  Semua subdomain user langsung dapat HTTPS (wildcard cert)"
echo -e "  Auto-renew SSL aktif (tanggal 1 dan 15 setiap bulan)"
echo ""
