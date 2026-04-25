#!/bin/bash
# ============================================================
# add-user.sh — Tambah user baru ke platform
# Penggunaan: sudo bash scripts/add-user.sh namauser
# Contoh:    sudo bash scripts/add-user.sh budi
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

USERNAME=$1

if [ -z "$USERNAME" ]; then
  echo -e "${RED}Error: Nama user harus diisi.${NC}"
  echo "Penggunaan: sudo bash scripts/add-user.sh namauser"
  exit 1
fi

# Validasi nama user (hanya huruf kecil dan angka)
if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9]{1,15}$ ]]; then
  echo -e "${RED}Error: Nama user hanya boleh huruf kecil dan angka, 2-16 karakter, harus diawali huruf.${NC}"
  exit 1
fi

# Load .env
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo -e "${RED}File .env tidak ditemukan. Jalankan setup.sh terlebih dahulu.${NC}"
  exit 1
fi

# Hitung port otomatis berdasarkan jumlah user yang sudah ada
EXISTING_USERS=$(ls /opt/devplatform/data 2>/dev/null | wc -l)
PORT=$((8081 + EXISTING_USERS))

echo -e "${BLUE}Menambah user: ${YELLOW}$USERNAME${BLUE} di port ${YELLOW}$PORT${NC}"

# Buat direktori user
USER_DIR="/opt/devplatform/data/$USERNAME"
mkdir -p "$USER_DIR/projects"
mkdir -p "$USER_DIR/config"

# Generate password random untuk user ini
USER_PASSWORD=$(openssl rand -base64 16)

# Buat Docker container code-server untuk user ini
docker run -d \
  --name "codeserver-$USERNAME" \
  --restart unless-stopped \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ="${TZ:-Asia/Jakarta}" \
  -e PASSWORD="$USER_PASSWORD" \
  -e SUDO_PASSWORD="$USER_PASSWORD" \
  -e DEFAULT_WORKSPACE="/config/projects" \
  -p "$PORT:8443" \
  -v "$USER_DIR/projects:/config/projects" \
  -v "$USER_DIR/config:/config" \
  lscr.io/linuxserver/code-server:latest

echo -e "${GREEN}Container code-server untuk $USERNAME berhasil dibuat.${NC}"

# Simpan info user
cat > "/opt/devplatform/configs/$USERNAME.conf" <<EOF
USERNAME=$USERNAME
PORT=$PORT
USER_DIR=$USER_DIR
USER_PASSWORD=$USER_PASSWORD
SUBDOMAIN=$USERNAME.$DOMAIN
CREATED=$(date)
EOF

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  User '$USERNAME' berhasil ditambah!       ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Detail akses:"
echo -e "  URL      : ${YELLOW}https://$USERNAME.$DOMAIN${NC}"
echo -e "  Password : ${YELLOW}$USER_PASSWORD${NC}"
echo ""
echo -e "${YELLOW}PENTING: Simpan password ini! Tidak bisa dilihat lagi.${NC}"
echo ""
echo -e "Langkah selanjutnya:"
echo -e "  1. Arahkan DNS ${YELLOW}$USERNAME.$DOMAIN${NC} → IP VPS ini"
echo -e "  2. Jalankan certbot: ${YELLOW}sudo certbot --nginx -d $USERNAME.$DOMAIN${NC}"
echo ""
