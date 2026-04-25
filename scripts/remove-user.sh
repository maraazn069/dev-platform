#!/bin/bash
# ============================================================
# remove-user.sh — Hapus user dari platform
# Penggunaan: sudo bash scripts/remove-user.sh namauser
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

USERNAME=$1

if [ -z "$USERNAME" ]; then
  echo -e "${RED}Error: Nama user harus diisi.${NC}"
  echo "Penggunaan: sudo bash scripts/remove-user.sh namauser"
  exit 1
fi

echo -e "${YELLOW}Menghapus user: $USERNAME...${NC}"

# Stop dan hapus container
if docker ps -a --format '{{.Names}}' | grep -q "codeserver-$USERNAME"; then
  docker stop "codeserver-$USERNAME"
  docker rm "codeserver-$USERNAME"
  echo -e "${GREEN}Container dihapus.${NC}"
else
  echo -e "${YELLOW}Container tidak ditemukan (mungkin sudah dihapus).${NC}"
fi

# Hapus file konfigurasi
if [ -f "/opt/devplatform/configs/$USERNAME.conf" ]; then
  rm "/opt/devplatform/configs/$USERNAME.conf"
fi

echo -e "${GREEN}User $USERNAME berhasil dihapus.${NC}"
echo -e "${YELLOW}Data di /opt/devplatform/data/$USERNAME TIDAK dihapus (backup manual).${NC}"
echo "Hapus manual jika diperlukan: rm -rf /opt/devplatform/data/$USERNAME"
