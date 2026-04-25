#!/bin/bash
# ============================================================
# setup.sh — Script instalasi awal untuk Self-Hosted Dev Platform
# Jalankan SEKALI di VPS baru sebagai root:
#   sudo bash scripts/setup.sh
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Self-Hosted Dev Platform — Setup VPS     ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Cek apakah dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan sebagai root: sudo bash scripts/setup.sh${NC}"
  exit 1
fi

# Cek OS (Ubuntu/Debian)
if ! command -v apt &> /dev/null; then
  echo -e "${RED}Script ini hanya untuk Ubuntu/Debian.${NC}"
  exit 1
fi

echo -e "${YELLOW}[1/6] Update sistem...${NC}"
apt update -qq && apt upgrade -y -qq

echo -e "${YELLOW}[2/6] Install dependensi dasar...${NC}"
apt install -y -qq curl wget git nano ufw fail2ban htop

echo -e "${YELLOW}[3/6] Install Docker...${NC}"
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
  echo -e "${GREEN}Docker berhasil diinstall.${NC}"
else
  echo -e "${GREEN}Docker sudah terinstall.${NC}"
fi

echo -e "${YELLOW}[4/6] Install Docker Compose v2...${NC}"
if ! docker compose version &> /dev/null; then
  apt install -y -qq docker-compose-plugin
  echo -e "${GREEN}Docker Compose berhasil diinstall.${NC}"
else
  echo -e "${GREEN}Docker Compose sudah terinstall.${NC}"
fi

echo -e "${YELLOW}[5/6] Install Nginx & Certbot (Let's Encrypt)...${NC}"
apt install -y -qq nginx certbot python3-certbot-nginx
systemctl enable nginx
systemctl start nginx
echo -e "${GREEN}Nginx siap.${NC}"

echo -e "${YELLOW}[6/6] Konfigurasi firewall (UFW)...${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable
echo -e "${GREEN}Firewall aktif.${NC}"

# Buat direktori data
mkdir -p /opt/devplatform/data
mkdir -p /opt/devplatform/configs
echo -e "${GREEN}Direktori /opt/devplatform dibuat.${NC}"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Setup selesai!                           ${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Langkah selanjutnya:"
echo -e "  1. Isi file .env: ${YELLOW}cp .env.example .env && nano .env${NC}"
echo -e "  2. Pastikan DNS subdomain sudah diarahkan ke IP VPS ini"
echo -e "  3. Tambah user: ${YELLOW}sudo bash scripts/add-user.sh namauser${NC}"
echo ""
