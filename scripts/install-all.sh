#!/usr/bin/env bash
# ================================================================
# install-all.sh — Wrapper SATU PERINTAH untuk install fresh.
#
# Jalankan SEKALI di VPS Ubuntu kosong / setelah uninstall-fresh.
# Akan otomatis chain:
#   1. install-vps.sh     → install Docker + container + portal (interaktif, isi prompt)
#   2. setup-https.sh     → cert wildcard *.DOMAIN + nginx HTTPS (di dalam install-vps)
#   3. sync-admin-password → bootstrap akun File Browser/pgAdmin (di dalam install-vps)
#   4. Verify → docker ps + curl health check semua URL
#
# Cara pakai:
#   cd /opt/devplatform && sudo bash scripts/install-all.sh
#
# Kalau VPS belum pernah di-clone:
#   cd /opt && sudo git clone https://github.com/maraazn069/dev-platform.git devplatform
#   cd /opt/devplatform && sudo bash scripts/install-all.sh
# ================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan dengan sudo: sudo bash scripts/install-all.sh${NC}"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════╗
  ║   DEV PLATFORM — INSTALL ALL-IN-ONE             ║
  ║   Install + HTTPS + Verify dalam 1 perintah      ║
  ╚══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# === Step 1: Cek apakah sudah pernah install (ada container running) ===
# Gate dengan command -v docker — di fresh VPS, docker belum install (akan di-install oleh install-vps.sh).
EXISTING=0
if command -v docker >/dev/null 2>&1; then
  EXISTING=$(docker ps -a --filter name=devplatform- --format "{{.Names}}" 2>/dev/null | wc -l)
fi
if [ "$EXISTING" -gt 0 ]; then
  echo -e "${YELLOW}⚠ Detected existing container devplatform-* (jumlah: $EXISTING).${NC}"
  echo -e "${YELLOW}  Kalau install ulang clean, jalankan dulu:${NC}"
  echo -e "${CYAN}    sudo bash scripts/uninstall-fresh.sh --force${NC}"
  echo -e "${CYAN}    sudo rm -f /opt/devplatform/.env${NC}"
  echo ""
  read -p "Lanjut install di atas yang ada? [y/N]: " confirm
  if [ "${confirm,,}" != "y" ]; then
    echo "Batal. Jalankan uninstall dulu lalu re-run script ini."
    exit 0
  fi
fi

# === Step 2: Run install-vps.sh (akan auto-call setup-https.sh + sync-admin-password.sh di akhir) ===
echo ""
echo -e "${BOLD}${CYAN}═══ [1/2] Install platform (interaktif) ═══${NC}"
echo -e "${CYAN}Akan tanya: Domain, Email, Admin user/password, Timezone, dll.${NC}"
echo -e "${CYAN}Setelah jawab semua → install jalan ~5 menit, HTTPS otomatis aktif di akhir.${NC}"
echo ""
sleep 2

bash scripts/install-vps.sh

# === Step 3: Verify ===
echo ""
echo -e "${BOLD}${CYAN}═══ [2/2] Verifikasi semua service ═══${NC}"
sleep 5

# Load DOMAIN dari .env
if [ -f .env ]; then
  set -a; source .env; set +a
fi
DOMAIN="${DOMAIN:-}"

if [ -z "$DOMAIN" ]; then
  echo -e "${YELLOW}⚠ DOMAIN tidak ditemukan di .env, skip URL test.${NC}"
else
  echo -e "${CYAN}→ Status container:${NC}"
  docker ps --format "  {{.Names}}\t{{.Status}}" | column -t -s$'\t'
  echo ""

  echo -e "${CYAN}→ Test HTTPS endpoint (target: 200/301/302):${NC}"
  for sub in "" "files." "mysql." "pgadmin."; do
    URL="https://${sub}${DOMAIN}/"
    CODE=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 "$URL" -H "Host: ${sub}${DOMAIN}" 2>/dev/null || echo "ERR")
    if [[ "$CODE" =~ ^(200|301|302)$ ]]; then
      echo -e "  ${GREEN}✓${NC} $URL → $CODE"
    else
      echo -e "  ${RED}✗${NC} $URL → $CODE"
    fi
  done
fi

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✓ Install all-in-one selesai!${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Selanjutnya:${NC}"
echo -e "  1. Buka portal: ${CYAN}https://$DOMAIN${NC}"
echo -e "  2. Login admin pakai password yang kakak set tadi"
echo -e "  3. Di tab 'Users', klik '+ Tambah User' → buat user baru"
echo -e "  4. User login di ${CYAN}https://<username>.$DOMAIN${NC}"
echo -e "  5. Preview project user di ${CYAN}https://<project>-<username>.$DOMAIN${NC}"
echo -e "       contoh: ${CYAN}https://default-user1.$DOMAIN${NC} (port 3000)"
echo -e "       custom port: ${CYAN}https://default-8000-user1.$DOMAIN${NC} (port 8000)"
echo ""
