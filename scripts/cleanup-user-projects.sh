#!/bin/bash
# ================================================================
# cleanup-user-projects.sh — Hapus SEMUA project user (reset clean)
#
# Pakai:
#   sudo bash scripts/cleanup-user-projects.sh <username>
#
# Ngapain:
#   1. Stop container codeserver-<user>
#   2. Hapus semua folder project di /opt/devplatform/data/<user>/projects/*
#   3. Hapus folder .trash juga
#   4. Reset projects[] di users.json jadi []
#   5. Restart container — code-server akan create folder kosong otomatis
#
# Aman: data user (settings, extensions, dll) di luar projects/ TIDAK terhapus.
# ================================================================
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

USERNAME="$1"

if [ -z "$USERNAME" ]; then
  echo -e "${RED}Usage: sudo bash scripts/cleanup-user-projects.sh <username>${NC}"
  exit 1
fi

if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{1,30}$ ]]; then
  echo -e "${RED}✗ username invalid: '$USERNAME' (harus a-z, 0-9, _)${NC}"
  exit 1
fi

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}✗ Harus root. Jalankan: sudo bash $0 $USERNAME${NC}"
  exit 1
fi

USER_DIR="/opt/devplatform/data/$USERNAME"
USERS_JSON="/opt/devplatform/server/data/users.json"
CODESERVER="codeserver-$USERNAME"

echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Reset Project — User: $USERNAME${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"

# Verify user exists
if [ ! -d "$USER_DIR" ]; then
  echo -e "${RED}✗ User dir tidak ada: $USER_DIR${NC}"
  exit 1
fi

# Stop container so file lock bersih
echo -e "${CYAN}[1/4] Stop container $CODESERVER...${NC}"
docker stop "$CODESERVER" 2>/dev/null && echo "  ✓ stopped" || echo "  → container tidak running, skip"

# Hapus projects
echo -e "${CYAN}[2/4] Hapus semua project di $USER_DIR/projects/...${NC}"
if [ -d "$USER_DIR/projects" ]; then
  COUNT=$(find "$USER_DIR/projects" -maxdepth 1 -mindepth 1 -type d | wc -l)
  rm -rf "$USER_DIR/projects"/*
  rm -rf "$USER_DIR/projects"/.[!.]* 2>/dev/null || true
  echo "  ✓ $COUNT project dihapus"
fi
if [ -d "$USER_DIR/.trash" ]; then
  TRASH_COUNT=$(find "$USER_DIR/.trash" -maxdepth 1 -mindepth 1 -type d | wc -l)
  rm -rf "$USER_DIR/.trash"
  echo "  ✓ $TRASH_COUNT item .trash dihapus"
fi

# Update users.json — reset projects[]
echo -e "${CYAN}[3/4] Reset projects[] di users.json...${NC}"
if [ -f "$USERS_JSON" ]; then
  python3 -c "
import json, sys
with open('$USERS_JSON') as f: users = json.load(f)
found = False
for u in users:
    if u.get('username') == '$USERNAME':
        u['projects'] = []
        found = True
        break
if not found:
    print('  ⚠ user $USERNAME tidak di users.json — tetap clean filesystem')
else:
    with open('$USERS_JSON', 'w') as f: json.dump(users, f, indent=2)
    print('  ✓ users.json updated')
"
fi

# Restart container
echo -e "${CYAN}[4/4] Start container $CODESERVER...${NC}"
docker start "$CODESERVER" 2>/dev/null && echo "  ✓ started" || echo "  → container tidak ada, akan ke-create lagi saat user login"

echo ""
echo -e "${GREEN}✓ Done. User $USERNAME sekarang punya 0 project.${NC}"
echo -e "${CYAN}  Login ke dashboard → klik '+ Buat Project' untuk bikin baru.${NC}"
