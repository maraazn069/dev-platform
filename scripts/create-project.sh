#!/bin/bash
# ============================================================
# create-project.sh — Buat folder project baru untuk user
# Penggunaan: sudo bash scripts/create-project.sh USERNAME PROJECT_NAME
# Contoh:    sudo bash scripts/create-project.sh budi belajar-react
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

USERNAME=$1
PROJECT=$2

if [ -z "$USERNAME" ] || [ -z "$PROJECT" ]; then
  echo -e "${RED}Error: Username dan nama project harus diisi.${NC}"
  echo "Penggunaan: sudo bash scripts/create-project.sh USERNAME PROJECT_NAME"
  exit 1
fi

PROJECT_DIR="/opt/devplatform/data/$USERNAME/projects/$PROJECT"

if [ -d "$PROJECT_DIR" ]; then
  echo -e "${YELLOW}Folder project '$PROJECT' sudah ada untuk user '$USERNAME'.${NC}"
  exit 0
fi

mkdir -p "$PROJECT_DIR"

# Buat README awal di project baru
cat > "$PROJECT_DIR/README.md" <<EOF
# Project: $PROJECT

User: $USERNAME
Dibuat: $(date)

## Cara Mulai

Buka terminal di VS Code dan mulai coding!

### Koneksi Database

**PostgreSQL:**
\`\`\`
Host: localhost
Port: 5432
Database: devplatform
Schema: $USERNAME
User: $USERNAME
\`\`\`

**MySQL:**
\`\`\`
Host: localhost
Port: 3306
Database: db_$USERNAME
User: $USERNAME
\`\`\`
EOF

# Fix permission agar code-server bisa akses
chown -R 1000:1000 "$PROJECT_DIR" 2>/dev/null || true

echo -e "${GREEN}Project '$PROJECT' berhasil dibuat untuk user '$USERNAME'.${NC}"
echo -e "Path: $PROJECT_DIR"
