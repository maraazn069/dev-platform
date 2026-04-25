#!/bin/bash
# ============================================================
# add-user.sh — Tambah user baru ke platform
# Penggunaan: sudo bash scripts/add-user.sh USERNAME PASSWORD PORT
# Contoh:    sudo bash scripts/add-user.sh budi password123 8081
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USERNAME=$1
PASSWORD=$2
PORT=${3:-8081}

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo -e "${RED}Error: Username dan password harus diisi.${NC}"
  echo "Penggunaan: sudo bash scripts/add-user.sh USERNAME PASSWORD [PORT]"
  exit 1
fi

if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9]{1,15}$ ]]; then
  echo -e "${RED}Error: Username hanya huruf kecil dan angka, 2-16 karakter.${NC}"
  exit 1
fi

# Cari file .env (bisa dari direktori sekarang atau direktori script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
elif [ -f ".env" ]; then
  set -a; source ".env"; set +a
else
  echo -e "${RED}File .env tidak ditemukan.${NC}"
  exit 1
fi

# Deteksi nama network Docker secara otomatis
DOCKER_NETWORK=$(docker network ls --format "{{.Name}}" | grep devplatform | head -1)
if [ -z "$DOCKER_NETWORK" ]; then
  echo -e "${RED}Network Docker devplatform tidak ditemukan. Pastikan docker compose up sudah jalan.${NC}"
  exit 1
fi

echo -e "${BLUE}Menambah user: ${YELLOW}$USERNAME${BLUE} di port ${YELLOW}$PORT${NC}"
echo -e "${BLUE}Menggunakan network: ${YELLOW}$DOCKER_NETWORK${NC}"

USER_DIR="/opt/devplatform/data/$USERNAME"
mkdir -p "$USER_DIR/projects/default"
mkdir -p "$USER_DIR/projects/belajar-python"
mkdir -p "$USER_DIR/projects/belajar-web"
mkdir -p "$USER_DIR/config"

# Buat container code-server untuk user ini
if docker ps -a --format '{{.Names}}' | grep -q "^codeserver-$USERNAME$"; then
  echo -e "${YELLOW}Container codeserver-$USERNAME sudah ada.${NC}"
else
  docker run -d \
    --name "codeserver-$USERNAME" \
    --restart unless-stopped \
    --network "$DOCKER_NETWORK" \
    -e PUID=1000 \
    -e PGID=1000 \
    -e TZ="${TZ:-Asia/Jakarta}" \
    -e PASSWORD="$PASSWORD" \
    -e SUDO_PASSWORD="$PASSWORD" \
    -e DEFAULT_WORKSPACE="/config/projects/default" \
    -v "$USER_DIR/projects:/config/projects" \
    -v "$USER_DIR/config:/config" \
    --label "devplatform.user=$USERNAME" \
    lscr.io/linuxserver/code-server:latest

  echo -e "${GREEN}Container code-server untuk $USERNAME berhasil dibuat.${NC}"
fi

# Setup PostgreSQL schema untuk user
echo -e "${YELLOW}Setup PostgreSQL schema untuk $USERNAME...${NC}"
PG_USER_PASSWORD=$(openssl rand -base64 12)
docker exec devplatform-postgres psql -U postgres -d devplatform -c "
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$USERNAME') THEN
      CREATE USER $USERNAME WITH PASSWORD '$PG_USER_PASSWORD';
    END IF;
  END
  \$\$;
  CREATE SCHEMA IF NOT EXISTS $USERNAME AUTHORIZATION $USERNAME;
  GRANT USAGE ON SCHEMA $USERNAME TO $USERNAME;
  GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA $USERNAME TO $USERNAME;
  GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA $USERNAME TO $USERNAME;
  ALTER USER $USERNAME SET search_path TO $USERNAME, public;
" 2>/dev/null || echo -e "${YELLOW}PostgreSQL belum siap, setup manual nanti.${NC}"

# Setup MySQL database untuk user
echo -e "${YELLOW}Setup MySQL database untuk $USERNAME...${NC}"
MYSQL_USER_PASSWORD=$(openssl rand -base64 12)
docker exec devplatform-mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
  CREATE DATABASE IF NOT EXISTS db_${USERNAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  CREATE USER IF NOT EXISTS '${USERNAME}'@'%' IDENTIFIED BY '${MYSQL_USER_PASSWORD}';
  GRANT ALL PRIVILEGES ON db_${USERNAME}.* TO '${USERNAME}'@'%';
  FLUSH PRIVILEGES;
" 2>/dev/null || echo -e "${YELLOW}MySQL belum siap, setup manual nanti.${NC}"

# Tambahkan server block nginx untuk subdomain user
NGINX_CONF="$PROJECT_DIR/nginx/nginx.conf"
if ! grep -q "codeserver-$USERNAME" "$NGINX_CONF" 2>/dev/null; then
  echo -e "${YELLOW}Menambah konfigurasi nginx untuk $USERNAME.$DOMAIN...${NC}"

  # Sisipkan server block baru sebelum baris penutup terakhir "}"
  NEW_BLOCK="
    server {
        listen 80;
        server_name $USERNAME.$DOMAIN;

        location / {
            proxy_pass http://codeserver-$USERNAME:8443;
            proxy_set_header Host \$host;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection upgrade;
            proxy_set_header Accept-Encoding gzip;
            proxy_read_timeout 86400s;
        }
    }"

  # Tambahkan sebelum baris "}" terakhir di file
  sed -i "$ s/^}/    $NEW_BLOCK\n}/" "$NGINX_CONF" 2>/dev/null || \
  echo "$NEW_BLOCK" >> "$NGINX_CONF"

  # Reload nginx
  docker compose -f "$PROJECT_DIR/docker-compose.yml" restart nginx 2>/dev/null || \
  docker restart nginx-proxy 2>/dev/null || true
  echo -e "${GREEN}✓ Nginx dikonfigurasi untuk $USERNAME.$DOMAIN${NC}"
fi

# Simpan info user
mkdir -p /opt/devplatform/configs
cat > "/opt/devplatform/configs/$USERNAME.conf" << EOF
USERNAME=$USERNAME
PORT=$PORT
USER_DIR=$USER_DIR
SUBDOMAIN=$USERNAME.$DOMAIN
PG_PASSWORD=$PG_USER_PASSWORD
MYSQL_PASSWORD=$MYSQL_USER_PASSWORD
CREATED=$(date)
EOF

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  User '$USERNAME' berhasil ditambah!      ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "VS Code   : ${YELLOW}http://$USERNAME.$DOMAIN${NC}"
echo -e "Password  : ${YELLOW}$PASSWORD${NC}"
echo ""
echo -e "PostgreSQL:"
echo -e "  Host    : devplatform-postgres (dari container lain)"
echo -e "  DB      : devplatform  |  Schema: $USERNAME"
echo -e "  User    : $USERNAME"
echo -e "  Password: ${YELLOW}$PG_USER_PASSWORD${NC}"
echo ""
echo -e "MySQL:"
echo -e "  Host    : devplatform-mysql (dari container lain)"
echo -e "  DB      : db_$USERNAME"
echo -e "  User    : $USERNAME"
echo -e "  Password: ${YELLOW}$MYSQL_USER_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}Langkah selanjutnya:${NC}"
echo -e "  1. Pastikan DNS ${YELLOW}$USERNAME.$DOMAIN${NC} → IP VPS sudah aktif"
echo -e "  2. Setelah portal aktif, user bisa login di: http://$DOMAIN"
echo ""
