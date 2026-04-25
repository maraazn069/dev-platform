#!/bin/bash
# ================================================================
# update-vps.sh — Safe one-command update flow di VPS
#
# Tujuan: nge-fix masalah Replit → GitHub → VPS Shell yang sering bermasalah:
#   - Shell paste lanjut walau perintah sebelumnya gagal (no &&)
#   - users.json / .env konflik tiap pull
#   - User lupa restart compose / kelewat verifikasi
#
# Pakai (di VPS):
#   cd /opt/devplatform
#   sudo bash scripts/update-vps.sh
#
# Aman dijalankan berulang. Idempotent.
# ================================================================
set -e  # stop di error pertama

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Pastikan dijalankan dari root project
if [ ! -f docker-compose.yml ] || [ ! -d .git ]; then
  echo -e "${RED}✗ Jalankan dari /opt/devplatform (folder yg ada docker-compose.yml + .git)${NC}"
  exit 1
fi

# Pastikan root (butuh akses docker + file /opt/devplatform yg di-own root)
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Harus root. Jalankan: sudo bash scripts/update-vps.sh${NC}"
  exit 1
fi

echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Dev Platform — Update dari GitHub (safe mode)${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"

# ---- 1. BACKUP file kritis yang biasanya di-modifikasi lokal ----
echo ""
echo -e "${CYAN}[1/6] Backup file kritis...${NC}"
BACKUP_DIR="/tmp/devplatform-update-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
SAFE_FILES=(
  ".env"
  "server/data/users.json"
  "server/data/audit.log"
  "nginx/nginx.conf"
)
for f in "${SAFE_FILES[@]}"; do
  if [ -f "$f" ]; then
    mkdir -p "$BACKUP_DIR/$(dirname "$f")"
    cp "$f" "$BACKUP_DIR/$f"
    echo "  ✓ backup $f"
  fi
done
echo -e "${GREEN}  → backup di $BACKUP_DIR${NC}"

# ---- 2. RESET local changes biar pull pasti sukses ----
echo ""
echo -e "${CYAN}[2/6] Reset local changes (akan di-restore dari backup)...${NC}"
git stash --include-untracked --quiet 2>/dev/null || true
# untuk file yang tracked tapi local-modified — hard checkout
for f in "${SAFE_FILES[@]}"; do
  if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    git checkout HEAD -- "$f" 2>/dev/null || true
  fi
done
echo -e "${GREEN}  ✓ working tree clean${NC}"

# ---- 3. PULL ----
echo ""
echo -e "${CYAN}[3/6] Pull dari GitHub...${NC}"
PREV_COMMIT=$(git rev-parse HEAD)
git pull origin main
NEW_COMMIT=$(git rev-parse HEAD)
if [ "$PREV_COMMIT" = "$NEW_COMMIT" ]; then
  echo -e "${YELLOW}  → tidak ada update baru (sudah versi terakhir)${NC}"
else
  echo -e "${GREEN}  ✓ updated: $PREV_COMMIT → $NEW_COMMIT${NC}"
  echo ""
  echo -e "${CYAN}  Changelog ringkas:${NC}"
  git log --oneline "$PREV_COMMIT..$NEW_COMMIT" | head -10 | sed 's/^/    /'
fi

# ---- 4. RESTORE file kritis dari backup ----
echo ""
echo -e "${CYAN}[4/6] Restore file kritis...${NC}"
for f in "${SAFE_FILES[@]}"; do
  if [ -f "$BACKUP_DIR/$f" ]; then
    # Kalau file di repo skrng SUDAH gak ada (ke-delete upstream) → tetap restore data lokal
    # supaya users.json / .env kamu ga hilang.
    cp "$BACKUP_DIR/$f" "$f"
    echo "  ✓ restore $f"
  fi
done

# ---- 5. RESTART compose dengan cleanup orphan ----
echo ""
echo -e "${CYAN}[5/6] Restart Docker compose...${NC}"
docker compose up -d --remove-orphans
echo -e "${GREEN}  ✓ compose up${NC}"

# Tunggu portal sehat
echo -e "${CYAN}  → menunggu portal ready (max 30s)...${NC}"
for i in $(seq 1 15); do
  if docker exec devplatform-portal wget -q -O /dev/null http://localhost:3000/health 2>/dev/null; then
    echo -e "${GREEN}  ✓ portal ready${NC}"
    break
  fi
  sleep 2
done

# ---- 6. VERIFY ----
echo ""
echo -e "${CYAN}[6/6] Verifikasi...${NC}"
echo ""
echo -e "${CYAN}Container status:${NC}"
docker compose ps --format 'table {{.Name}}\t{{.Status}}' | head -20
echo ""
echo -e "${CYAN}Portal log (20 baris terakhir):${NC}"
docker logs devplatform-portal --tail 20 2>&1 | grep -v "MemoryStore" | sed 's/^/  /'

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Update selesai!${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Backup file kritis tersimpan di:${NC} $BACKUP_DIR"
echo -e "${CYAN}Untuk lihat changelog full:${NC} git log --oneline -20"
