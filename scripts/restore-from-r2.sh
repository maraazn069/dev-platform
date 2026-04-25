#!/usr/bin/env bash
# Restore DevPlatform dari Cloudflare R2 — biar VPS baru / reinstall langsung punya data lama.
#
# Pakai:
#   sudo bash scripts/restore-from-r2.sh                # ambil backup TERAKHIR otomatis
#   sudo bash scripts/restore-from-r2.sh 20260425_140000  # restore backup spesifik
#   sudo bash scripts/restore-from-r2.sh --list         # lihat semua backup yg ada
#
# PRECONDITION: 
#   - .env udah ada dengan R2_* credentials (R2_ACCOUNT_ID, R2_ACCESS_KEY, R2_SECRET_KEY, R2_BUCKET)
#   - docker-compose.yml udah ada (dari git pull)
#   - awscli terinstall (sudo apt install awscli -y)

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID belum diset di .env}"
: "${R2_ACCESS_KEY:?R2_ACCESS_KEY belum diset di .env}"
: "${R2_SECRET_KEY:?R2_SECRET_KEY belum diset di .env}"

R2_BUCKET="${R2_BUCKET:-devplatform-backups}"
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
HOSTNAME_SOURCE="${RESTORE_FROM_HOST:-$(hostname)}"

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_KEY"
export AWS_DEFAULT_REGION="auto"

if ! command -v aws >/dev/null 2>&1; then
  echo "❌ aws cli belum terinstall. Install: sudo apt install awscli -y"
  exit 1
fi

# --list mode
if [ "${1:-}" = "--list" ]; then
  echo "Backup tersedia di s3://$R2_BUCKET/"
  aws s3 ls "s3://$R2_BUCKET/" --endpoint-url "$R2_ENDPOINT" --recursive 2>/dev/null \
    | awk '{print $1, $2, $4}' \
    | grep -E '_[0-9]{6}/' | head -50
  echo ""
  echo "Untuk restore: sudo bash $0 <YYYYMMDD_HHMMSS>"
  echo "Untuk restore dari host lain, set: export RESTORE_FROM_HOST=<old-hostname>"
  exit 0
fi

# Tentukan backup mana yg di-restore
BACKUP_ID="${1:-}"
if [ -z "$BACKUP_ID" ]; then
  echo "→ Cari backup terakhir untuk host '$HOSTNAME_SOURCE'..."
  if ! aws s3 cp "s3://$R2_BUCKET/$HOSTNAME_SOURCE/latest.txt" /tmp/r2-latest.txt \
       --endpoint-url "$R2_ENDPOINT" --no-progress 2>/dev/null; then
    echo "❌ Tidak bisa baca latest.txt. Coba list manual: $0 --list"
    echo "   Atau set host source: export RESTORE_FROM_HOST=<hostname>"
    exit 1
  fi
  BACKUP_PREFIX=$(cat /tmp/r2-latest.txt)
  rm -f /tmp/r2-latest.txt
  if [ -z "$BACKUP_PREFIX" ]; then
    echo "❌ latest.txt kosong. Coba: $0 --list"
    exit 1
  fi
else
  BACKUP_PREFIX="$HOSTNAME_SOURCE/$BACKUP_ID"
fi

echo "════════════════════════════════════════════════════════"
echo "  Restore dari: s3://$R2_BUCKET/$BACKUP_PREFIX/"
echo "════════════════════════════════════════════════════════"
echo ""
echo "⚠ PERINGATAN: ini akan REPLACE database+workspace+config saat ini."
echo "  Pastikan udah backup current state kalau perlu."
echo ""
read -p "Lanjut restore? Ketik YES (uppercase): " CONFIRM
[ "$CONFIRM" = "YES" ] || { echo "Dibatalkan."; exit 0; }

RESTORE_DIR="/tmp/devplatform-restore-$$"
mkdir -p "$RESTORE_DIR"

trap 'rm -rf "$RESTORE_DIR"' EXIT

# Download semua file dari backup folder — strict, fail kalau sync error
echo "→ Download backup files..."
if ! aws s3 sync "s3://$R2_BUCKET/$BACKUP_PREFIX/" "$RESTORE_DIR/" \
    --endpoint-url "$R2_ENDPOINT" --no-progress >/tmp/r2-sync.log 2>&1; then
  echo "❌ Download gagal:"
  tail -10 /tmp/r2-sync.log
  exit 1
fi

if [ ! -f "$RESTORE_DIR/manifest.json" ]; then
  echo "❌ Backup tidak lengkap (manifest.json hilang). Aborted."
  exit 1
fi

# Validate critical artefacts non-empty
for required in mysql.sql.gz postgres.sql.gz; do
  if [ ! -s "$RESTORE_DIR/$required" ]; then
    echo "⚠ $required missing/empty di backup ini. Restore akan SKIP file ini."
    echo "  Backup ini mungkin partial. Lanjut? (Ctrl+C untuk batal)"
    sleep 5
  fi
done

echo "  ✓ Files downloaded:"
ls -lh "$RESTORE_DIR/"

# 1) Restore config dulu (.env, users.json, docker-compose.yml)
if [ -f "$RESTORE_DIR/config.tar.gz" ]; then
  echo ""
  echo "→ Restore config (users.json, .env)..."
  tar xzf "$RESTORE_DIR/config.tar.gz" -C "$(pwd)"
  echo "  ✓ Config restored"
fi

# 2) Restore SSL certs SEBELUM start container (biar nginx langsung punya cert)
if [ -f "$RESTORE_DIR/letsencrypt.tar.gz" ]; then
  echo ""
  echo "→ Restore SSL certs ke /etc/letsencrypt..."
  tar xzf "$RESTORE_DIR/letsencrypt.tar.gz" -C /etc/
  echo "  ✓ SSL certs restored"
fi

# 3) Restore nginx site configs
if [ -f "$RESTORE_DIR/nginx.tar.gz" ]; then
  echo ""
  echo "→ Restore nginx configs..."
  tar xzf "$RESTORE_DIR/nginx.tar.gz" -C "$(pwd)"
  echo "  ✓ Nginx configs restored"
fi

# 4) Restore workspace data (folder /opt/devplatform/data)
if [ -f "$RESTORE_DIR/workspace.tar.gz" ]; then
  echo ""
  echo "→ Restore workspace user → /opt/devplatform/data..."
  mkdir -p /opt/devplatform
  tar xzf "$RESTORE_DIR/workspace.tar.gz" -C /opt/devplatform/
  chown -R 1000:1000 /opt/devplatform/data
  echo "  ✓ Workspace restored"
fi

# 5) Start docker-compose services (biar mysql+postgres running sebelum restore)
echo ""
echo "→ Start MySQL + PostgreSQL services..."
docker compose up -d mysql postgres
echo "  ⏳ Wait 15 detik biar DB siap..."
sleep 15

# 6) Restore MySQL
if [ -s "$RESTORE_DIR/mysql.sql.gz" ]; then
  echo ""
  echo "→ Restore MySQL..."
  if ! zcat "$RESTORE_DIR/mysql.sql.gz" \
      | docker exec -i devplatform-mysql sh -c 'exec mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' 2>/tmp/mysql-restore.err; then
    echo "  ❌ MySQL restore gagal:"
    tail -10 /tmp/mysql-restore.err
    exit 1
  fi
  echo "  ✓ MySQL restored"
else
  echo "  ⚠ MySQL dump kosong/missing — SKIP"
fi

# 7) Restore PostgreSQL
if [ -s "$RESTORE_DIR/postgres.sql.gz" ]; then
  echo ""
  echo "→ Restore PostgreSQL..."
  if ! zcat "$RESTORE_DIR/postgres.sql.gz" \
      | docker exec -i devplatform-postgres psql -U postgres >/tmp/pg-restore.log 2>&1; then
    echo "  ❌ PG restore gagal:"
    tail -10 /tmp/pg-restore.log
    exit 1
  fi
  echo "  ✓ PostgreSQL restored"
else
  echo "  ⚠ PG dump kosong/missing — SKIP"
fi

# 8) Start sisanya
echo ""
echo "→ Start semua service..."
docker compose up -d

# 9) Re-create code-server containers untuk semua user di users.json
echo ""
echo "→ Re-create code-server containers untuk semua user..."
echo "  (Ini bisa makan beberapa menit bergantung jumlah user)"
sleep 10  # tunggu portal siap
if [ -f scripts/recreate-all-codeserver.sh ]; then
  bash scripts/recreate-all-codeserver.sh < /dev/null || echo "  ⚠ recreate-all-codeserver gagal sebagian — cek manual via admin UI."
else
  echo "  ⚠ Script recreate-all-codeserver.sh gak ada. Skip — user code-server akan di-create on-demand."
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ Restore SELESAI"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Cek:"
echo "  - Portal: https://${DOMAIN:-yourdomain}/"
echo "  - User dashboards: https://USERNAME.${DOMAIN:-yourdomain}/"
echo ""
echo "Kalau ada user 502, login admin → tombol 'Repair Container'."
