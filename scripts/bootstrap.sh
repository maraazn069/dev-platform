#!/usr/bin/env bash
# ================================================================
# bootstrap.sh — One-liner installer untuk VPS Ubuntu fresh.
#
# Tujuan: SATU PERINTAH dari mana saja, otomatis:
#   1. Install git kalau belum ada
#   2. Clone repo (atau pull kalau sudah ada)
#   3. Chain ke install-all.sh (yang chain ke install-vps + setup-https)
#
# Cara pakai (copy-paste 1 baris ke terminal VPS):
#   curl -fsSL https://raw.githubusercontent.com/maraazn069/dev-platform/main/scripts/bootstrap.sh | sudo bash
#
# Atau dengan auto-uninstall existing dulu:
#   curl -fsSL https://raw.githubusercontent.com/maraazn069/dev-platform/main/scripts/bootstrap.sh | sudo bash -s -- --reinstall
# ================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_URL="${REPO_URL:-https://github.com/maraazn069/dev-platform.git}"
INSTALL_DIR="${INSTALL_DIR:-/opt/devplatform}"
BRANCH="${BRANCH:-main}"
REINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --reinstall) REINSTALL=1 ;;
    --repo=*) REPO_URL="${arg#--repo=}" ;;
    --dir=*) INSTALL_DIR="${arg#--dir=}" ;;
    --branch=*) BRANCH="${arg#--branch=}" ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Harap jalankan dengan sudo.${NC}"
  echo -e "Contoh: ${CYAN}curl -fsSL https://raw.githubusercontent.com/maraazn069/dev-platform/main/scripts/bootstrap.sh | sudo bash${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  ╔══════════════════════════════════════════════════╗
  ║   DEV PLATFORM — BOOTSTRAP (One-liner)          ║
  ║   Auto pull + install dari GitHub                ║
  ╚══════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

echo -e "Repo       : ${CYAN}$REPO_URL${NC}"
echo -e "Branch     : ${CYAN}$BRANCH${NC}"
echo -e "Install dir: ${CYAN}$INSTALL_DIR${NC}"
echo -e "Reinstall  : $([ "$REINSTALL" = "1" ] && echo "${YELLOW}YA (uninstall dulu)${NC}" || echo "tidak")"
echo ""

# === [1/3] Install git kalau belum ada ===
if ! command -v git >/dev/null 2>&1; then
  echo -e "${CYAN}→ Install git...${NC}"
  apt update -qq && apt install -y -qq git
  echo -e "${GREEN}  ✓ git terpasang${NC}"
else
  echo -e "${GREEN}✓ git sudah ada${NC}"
fi
echo ""

# === [2/3] Clone repo atau pull update ===
if [ -d "$INSTALL_DIR/.git" ]; then
  echo -e "${CYAN}→ Repo sudah ada di $INSTALL_DIR — pull update...${NC}"
  git -C "$INSTALL_DIR" fetch origin "$BRANCH" --quiet
  git -C "$INSTALL_DIR" checkout "$BRANCH" --quiet
  if ! git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH" 2>&1 | tail -3; then
    echo -e "${YELLOW}  ⚠ git pull gagal (mungkin ada perubahan lokal). Lanjut pakai versi yang ada.${NC}"
  fi
elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  echo -e "${RED}✗ $INSTALL_DIR sudah ada tapi BUKAN git repo (ada file lain).${NC}"
  echo -e "${YELLOW}  Pindahkan/hapus folder ini dulu, atau set INSTALL_DIR ke path lain:${NC}"
  echo -e "${CYAN}  curl -fsSL .../bootstrap.sh | sudo bash -s -- --dir=/opt/devplatform2${NC}"
  exit 1
else
  echo -e "${CYAN}→ Clone repo $REPO_URL ke $INSTALL_DIR...${NC}"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi
echo -e "${GREEN}✓ Repo siap di $INSTALL_DIR${NC}"
echo ""

cd "$INSTALL_DIR"

# === [3/3] Optional: uninstall fresh kalau --reinstall ===
if [ "$REINSTALL" = "1" ]; then
  if command -v docker >/dev/null 2>&1 && docker ps -a --filter name=devplatform- --format "{{.Names}}" 2>/dev/null | grep -q .; then
    echo -e "${YELLOW}→ --reinstall: jalankan uninstall-fresh.sh dulu...${NC}"
    bash scripts/uninstall-fresh.sh --force
    rm -f "$INSTALL_DIR/.env"
    echo -e "${GREEN}✓ Uninstall selesai, .env dihapus${NC}"
    echo ""
  else
    echo -e "${CYAN}→ --reinstall diset, tapi belum ada container existing — skip uninstall.${NC}"
    echo ""
  fi
fi

# === Chain ke install-all.sh ===
if [ ! -f "$INSTALL_DIR/scripts/install-all.sh" ]; then
  echo -e "${RED}✗ scripts/install-all.sh tidak ditemukan di repo. Branch '$BRANCH' mungkin belum punya file ini.${NC}"
  echo -e "${YELLOW}  Coba branch main atau update repo:${NC}"
  echo -e "${CYAN}  cd $INSTALL_DIR && git pull origin main${NC}"
  exit 1
fi

echo -e "${BOLD}${CYAN}═══ Chain ke install-all.sh ═══${NC}"
echo ""

# === Rebind stdin ke TTY supaya prompt interaktif (read) di install-vps.sh tetap jalan ===
# Penting saat dijalankan via `curl ... | sudo bash`: stdin asli adalah pipe dari curl (EOF),
# kalau tidak di-rebind, semua `read -p` akan langsung balik EOF dan script crash di set -e.
if [ ! -t 0 ]; then
  if [ -e /dev/tty ]; then
    echo -e "${CYAN}→ Rebind stdin ke /dev/tty supaya prompt interaktif jalan${NC}"
    exec </dev/tty
  else
    echo -e "${RED}✗ Stdin bukan TTY dan /dev/tty tidak tersedia.${NC}"
    echo -e "${YELLOW}  Install-vps.sh butuh prompt interaktif. Jalankan ulang via SSH session normal:${NC}"
    echo -e "${CYAN}  cd $INSTALL_DIR && sudo bash scripts/install-all.sh${NC}"
    exit 1
  fi
fi

exec bash "$INSTALL_DIR/scripts/install-all.sh"
