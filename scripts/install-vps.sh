#!/bin/bash
# ================================================================
# install-vps.sh — Installer otomatis Self-Hosted Dev Platform
#
# Cara pakai (satu perintah dari SSH):
#   bash <(curl -fsSL https://raw.githubusercontent.com/USERMU/REPO/main/scripts/install-vps.sh)
#
# Atau setelah clone:
#   sudo bash scripts/install-vps.sh
# ================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${CYAN}${BOLD}"
echo "  ██████╗ ███████╗██╗   ██╗    ██████╗ ██╗      █████╗ ████████╗"
echo "  ██╔══██╗██╔════╝██║   ██║    ██╔══██╗██║     ██╔══██╗╚══██╔══╝"
echo "  ██║  ██║█████╗  ██║   ██║    ██████╔╝██║     ███████║   ██║   "
echo "  ██║  ██║██╔══╝  ╚██╗ ██╔╝    ██╔═══╝ ██║     ██╔══██║   ██║   "
echo "  ██████╔╝███████╗ ╚████╔╝     ██║     ███████╗██║  ██║   ██║   "
echo "  ╚═════╝ ╚══════╝  ╚═══╝      ╚═╝     ╚══════╝╚═╝  ╚═╝   ╚═╝   "
echo -e "${NC}"
echo -e "${BOLD}  Self-Hosted Dev Platform — Installer Otomatis${NC}"
echo -e "  Platform coding mandiri untuk 1-10 user belajar"
echo ""
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo ""

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan sebagai root: sudo bash scripts/install-vps.sh${NC}"
  exit 1
fi

if ! command -v apt &> /dev/null; then
  echo -e "${RED}Script ini hanya untuk Ubuntu/Debian.${NC}"
  exit 1
fi

# ---- Tanya konfigurasi dasar ----
echo -e "${BOLD}Konfigurasi Platform${NC}"
echo ""

read -p "$(echo -e ${YELLOW})Domain utama (contoh: dev.domainku.com): $(echo -e ${NC})" DOMAIN
read -p "$(echo -e ${YELLOW})Email untuk HTTPS/Let's Encrypt: $(echo -e ${NC})" LETSENCRYPT_EMAIL
read -p "$(echo -e ${YELLOW})Timezone (Enter untuk Asia/Jakarta): $(echo -e ${NC})" TZ_INPUT
TZ="${TZ_INPUT:-Asia/Jakarta}"

echo ""
echo -e "${BOLD}Konfigurasi Database${NC}"
echo ""
read -p "$(echo -e ${YELLOW})Password PostgreSQL (Enter untuk auto-generate): $(echo -e ${NC})" PG_PASS
if [ -z "$PG_PASS" ]; then PG_PASS=$(openssl rand -base64 20); fi

read -p "$(echo -e ${YELLOW})Password MySQL root (Enter untuk auto-generate): $(echo -e ${NC})" MYSQL_ROOT_PASS
if [ -z "$MYSQL_ROOT_PASS" ]; then MYSQL_ROOT_PASS=$(openssl rand -base64 20); fi

MYSQL_PASS=$(openssl rand -base64 16)
SESSION_SECRET=$(openssl rand -base64 32)

echo ""
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo -e "${BOLD}Memulai instalasi...${NC}"
echo -e "${YELLOW}────────────────────────────────────────────────${NC}"
echo ""

# [1/8] Update sistem
echo -e "${CYAN}[1/8]${NC} Update sistem..."
apt update -qq && apt upgrade -y -qq
echo -e "${GREEN}✓ Sistem diperbarui${NC}"

# [2/8] Install dependensi
echo -e "${CYAN}[2/8]${NC} Install dependensi dasar..."
apt install -y -qq curl wget git nano ufw fail2ban htop unzip openssl
echo -e "${GREEN}✓ Dependensi terinstall${NC}"

# [3/8] Install Docker
echo -e "${CYAN}[3/8]${NC} Install Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh -s -- -q
  systemctl enable docker && systemctl start docker
  echo -e "${GREEN}✓ Docker terinstall${NC}"
else
  echo -e "${GREEN}✓ Docker sudah ada${NC}"
fi

# [4/8] Docker Compose
echo -e "${CYAN}[4/8]${NC} Install Docker Compose..."
if ! docker compose version &> /dev/null 2>&1; then
  apt install -y -qq docker-compose-plugin
fi
echo -e "${GREEN}✓ Docker Compose siap${NC}"

# [5/8] Certbot (Nginx dihandle Docker, bukan sistem)
echo -e "${CYAN}[5/8]${NC} Install Certbot..."
apt install -y -qq certbot
# Pastikan sistem nginx tidak jalan (konflik dengan Docker nginx di port 80)
systemctl stop nginx 2>/dev/null || true
systemctl disable nginx 2>/dev/null || true
echo -e "${GREEN}✓ Certbot siap (sistem nginx dinonaktifkan)${NC}"

# [6/8] Firewall
echo -e "${CYAN}[6/8]${NC} Konfigurasi firewall..."
ufw --force reset > /dev/null
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw allow 22/tcp > /dev/null
ufw allow 80/tcp > /dev/null
ufw allow 443/tcp > /dev/null
ufw --force enable > /dev/null
echo -e "${GREEN}✓ Firewall aktif (22, 80, 443)${NC}"

# [7/8] Clone atau setup repo
echo -e "${CYAN}[7/8]${NC} Setup direktori project..."
mkdir -p /opt/devplatform/data
mkdir -p /opt/devplatform/configs
chmod 755 /opt/devplatform

# Kalau belum ada repo (mode one-liner), clone dari GitHub
if [ ! -f "docker-compose.yml" ]; then
  echo ""
  read -p "$(echo -e ${YELLOW})URL GitHub repo kamu (contoh: https://github.com/user/repo): $(echo -e ${NC})" REPO_URL
  cd /opt/devplatform
  git clone "$REPO_URL" platform
  cd platform
fi

echo -e "${GREEN}✓ Direktori siap${NC}"

# [8/8] Buat file .env
echo -e "${CYAN}[8/8]${NC} Membuat file .env..."
cat > .env <<EOF
# ================================================================
# .env — Konfigurasi Self-Hosted Dev Platform
# File ini TIDAK boleh di-commit ke GitHub (sudah ada di .gitignore)
# ================================================================

DOMAIN=$DOMAIN
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
SESSION_SECRET=$SESSION_SECRET
TZ=$TZ

# Database PostgreSQL
POSTGRES_PASSWORD=$PG_PASS

# Database MySQL
MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASS
MYSQL_PASSWORD=$MYSQL_PASS

# Cloudflare Tunnel (isi setelah setup tunnel)
CLOUDFLARE_TUNNEL_TOKEN=

# Direktori data
DATA_DIR=/opt/devplatform/data
EOF
echo -e "${GREEN}✓ File .env dibuat${NC}"

# Build & start semua service
echo ""
echo -e "${CYAN}Menjalankan semua service...${NC}"
chmod +x scripts/*.sh
docker compose up -d --build

echo ""
echo -e "${GREEN}${BOLD}"
echo "  ================================================"
echo "  ✓ Instalasi berhasil!"
echo "  ================================================"
echo -e "${NC}"
echo -e "${BOLD}Akses Platform:${NC}"
echo -e "  Portal     : ${CYAN}http://$(curl -s ifconfig.me)${NC} (sementara, belum HTTPS)"
echo -e "  Domain nanti: ${CYAN}https://$DOMAIN${NC}"
echo ""
echo -e "${BOLD}Login Default:${NC}"
echo -e "  Admin  : username ${YELLOW}admin${NC}  / password ${YELLOW}admin123${NC}"
echo -e "  User 1 : username ${YELLOW}user1${NC}  / password ${YELLOW}user1234${NC}"
echo ""
echo -e "${BOLD}Kredensial Database (simpan baik-baik!):${NC}"
echo -e "  PostgreSQL password : ${YELLOW}$PG_PASS${NC}"
echo -e "  MySQL root password : ${YELLOW}$MYSQL_ROOT_PASS${NC}"
echo ""
echo -e "${YELLOW}Langkah selanjutnya:${NC}"
echo -e "  1. Arahkan DNS ${BOLD}$DOMAIN${NC} → IP VPS ini"
echo -e "  2. sudo certbot --nginx -d $DOMAIN"
echo -e "  3. Tambah user: sudo bash scripts/add-user.sh namauser password port"
echo -e "  4. ${RED}WAJIB: Ganti password admin dan user1 setelah login pertama!${NC}"
echo ""
