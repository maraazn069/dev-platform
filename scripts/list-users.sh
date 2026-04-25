#!/bin/bash
# ============================================================
# list-users.sh — Lihat daftar semua user aktif
# Penggunaan: bash scripts/list-users.sh
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Daftar User Platform                     ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

CONFIG_DIR="/opt/devplatform/configs"

if [ ! -d "$CONFIG_DIR" ] || [ -z "$(ls -A $CONFIG_DIR 2>/dev/null)" ]; then
  echo "Belum ada user terdaftar."
  echo "Tambah user: sudo bash scripts/add-user.sh namauser"
  exit 0
fi

printf "%-15s %-8s %-30s %-10s\n" "USERNAME" "PORT" "SUBDOMAIN" "STATUS"
printf "%-15s %-8s %-30s %-10s\n" "--------" "----" "---------" "------"

for conf in "$CONFIG_DIR"/*.conf; do
  source "$conf"
  CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "codeserver-$USERNAME" 2>/dev/null || echo "tidak ada")
  COLOR=$([[ "$CONTAINER_STATUS" == "running" ]] && echo "$GREEN" || echo "$YELLOW")
  printf "%-15s %-8s %-30s ${COLOR}%-10s${NC}\n" "$USERNAME" "$PORT" "$SUBDOMAIN" "$CONTAINER_STATUS"
done

echo ""
echo "Untuk menambah user: sudo bash scripts/add-user.sh namauser"
echo "Untuk menghapus user: sudo bash scripts/remove-user.sh namauser"
