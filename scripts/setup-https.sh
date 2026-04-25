#!/bin/bash
# ================================================================
# setup-https.sh — Setup HTTPS dengan Let's Encrypt
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

if [ ! -f ".env" ]; then
  echo -e "${RED}File .env tidak ditemukan. Pastikan sudah install dulu.${NC}"
  exit 1
fi

source .env

if [ -z "$DOMAIN" ] || [ -z "$LETSENCRYPT_EMAIL" ]; then
  echo -e "${RED}DOMAIN dan LETSENCRYPT_EMAIL wajib ada di .env${NC}"
  exit 1
fi

echo -e "${CYAN}${BOLD}Setup HTTPS untuk $DOMAIN${NC}"
echo ""

# Cek apakah certbot terinstall
if ! command -v certbot &> /dev/null; then
  echo -e "${CYAN}Install certbot...${NC}"
  apt install -y -qq certbot
fi

# Stop nginx sementara untuk verifikasi domain
echo -e "${CYAN}Stop nginx sementara...${NC}"
docker compose stop nginx

# Jalankan certbot standalone
echo -e "${CYAN}Minta sertifikat SSL...${NC}"
certbot certonly \
  --standalone \
  --non-interactive \
  --agree-tos \
  --email "$LETSENCRYPT_EMAIL" \
  -d "$DOMAIN" \
  -d "db-admin.$DOMAIN" \
  --keep-until-expiring

echo -e "${GREEN}✓ Sertifikat SSL berhasil dibuat${NC}"

# Update nginx.conf dengan HTTPS
echo -e "${CYAN}Update konfigurasi Nginx untuk HTTPS...${NC}"
cat > nginx/nginx.conf << NGINXEOF
events {
    worker_connections 1024;
}

http {
    resolver 127.0.0.11 valid=30s ipv6=off;

    # ---- Redirect HTTP → HTTPS ----
    server {
        listen 80;
        server_name $DOMAIN db-admin.$DOMAIN;
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

    # ---- Adminer (HTTPS) ----
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

    # ---- Catch-all ----
    server {
        listen 80 default_server;
        server_name _;
        return 301 https://$DOMAIN\$request_uri;
    }
}
NGINXEOF

# Start nginx lagi
echo -e "${CYAN}Restart nginx...${NC}"
docker compose start nginx
sleep 3

# Setup auto-renew certbot
echo -e "${CYAN}Setup auto-renew SSL...${NC}"
cat > /etc/cron.d/certbot-renew << 'CRONEOF'
0 3 * * * root certbot renew --quiet --pre-hook "cd /home/$(logname)/dev-platform && docker compose stop nginx" --post-hook "cd /home/$(logname)/dev-platform && docker compose start nginx"
CRONEOF

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ================================================"
echo "  ✓ HTTPS berhasil dikonfigurasi!"
echo "  ================================================"
echo -e "${NC}"
echo -e "  Portal: ${CYAN}https://$DOMAIN${NC}"
echo -e "  DB Admin: ${CYAN}https://db-admin.$DOMAIN${NC}"
echo ""
echo -e "  Auto-renew SSL sudah aktif (setiap hari jam 03:00)"
echo ""
