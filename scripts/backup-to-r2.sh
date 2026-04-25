#!/usr/bin/env bash
# Push backup harian ke Cloudflare R2 (S3-compatible storage).
# 
# Setup sekali:
#   1. Login Cloudflare → R2 → Create Bucket: 'devplatform-backups'
#   2. R2 → Manage R2 API Tokens → Create Token (Object Read & Write, scope ke bucket di atas)
#   3. Catat: Access Key ID, Secret Access Key, dan Account ID (URL endpoint)
#   4. Edit /opt/devplatform/.env, tambahkan:
#         R2_ACCOUNT_ID=xxxxxxxxxxxx
#         R2_ACCESS_KEY=xxxxxxxxxxxx
#         R2_SECRET_KEY=xxxxxxxxxxxx
#         R2_BUCKET=devplatform-backups
#   5. Install: sudo apt install awscli -y
#   6. Test manual: sudo bash scripts/backup-to-r2.sh
#   7. Pasang ke cron: sudo bash scripts/install-backup-cron.sh

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

cd "$(dirname "$0")/.."

# Load .env
if [ -f .env ]; then
  set -a; source .env; set +a
fi

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID belum diset di .env}"
: "${R2_ACCESS_KEY:?R2_ACCESS_KEY belum diset di .env}"
: "${R2_SECRET_KEY:?R2_SECRET_KEY belum diset di .env}"

R2_BUCKET="${R2_BUCKET:-devplatform-backups}"
R2_ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
HOSTNAME=$(hostname)
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/devplatform-backup-$DATE"

echo "════════════════════════════════════════════════════════"
echo "  Backup DevPlatform → Cloudflare R2"
echo "  Bucket: $R2_BUCKET | Host: $HOSTNAME | Time: $DATE"
echo "════════════════════════════════════════════════════════"

cleanup() { rm -rf "$BACKUP_DIR" 2>/dev/null || true; }
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"
ERRORS=0

# Helper: validate file is non-empty (>1KB minimum, otherwise dump kosong/error)
require_nonempty() {
  local f="$1"; local min="${2:-1024}"; local label="$3"
  if [ ! -f "$f" ]; then
    echo "  ❌ $label: file tidak ada ($f)"
    ERRORS=$((ERRORS+1))
    return 1
  fi
  local size; size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
  if [ "$size" -lt "$min" ]; then
    echo "  ❌ $label: file terlalu kecil ($size byte, min $min) — dump kemungkinan gagal"
    ERRORS=$((ERRORS+1))
    return 1
  fi
  echo "  ✓ $label: $(numfmt --to=iec --suffix=B "$size" 2>/dev/null || echo "${size}B")"
}

# 1) Dump MySQL semua database
echo "→ Dump MySQL..."
if docker exec devplatform-mysql sh -c \
    'exec mysqldump --all-databases --single-transaction --quick --lock-tables=false -uroot -p"$MYSQL_ROOT_PASSWORD"' \
    2>/tmp/mysql-dump.err | gzip > "$BACKUP_DIR/mysql.sql.gz"; then
  require_nonempty "$BACKUP_DIR/mysql.sql.gz" 2048 "MySQL dump" || true
else
  echo "  ❌ MySQL dump gagal: $(head -3 /tmp/mysql-dump.err)"
  ERRORS=$((ERRORS+1))
fi

# 2) Dump PostgreSQL semua database
echo "→ Dump PostgreSQL..."
if docker exec devplatform-postgres pg_dumpall -U postgres 2>/tmp/pg-dump.err | gzip > "$BACKUP_DIR/postgres.sql.gz"; then
  require_nonempty "$BACKUP_DIR/postgres.sql.gz" 2048 "PG dump" || true
else
  echo "  ❌ PG dump gagal: $(head -3 /tmp/pg-dump.err)"
  ERRORS=$((ERRORS+1))
fi

# 3) Tar workspace user
echo "→ Tar workspace user..."
if [ -d /opt/devplatform/data ]; then
  if tar czf "$BACKUP_DIR/workspace.tar.gz" \
      --exclude='*/node_modules' \
      --exclude='*/.git/objects' \
      --exclude='*/__pycache__' \
      --exclude='*/.cache' \
      --exclude='*/.local/share/code-server/CachedExtensionVSIXs' \
      -C /opt/devplatform data/ 2>/tmp/ws-tar.err; then
    require_nonempty "$BACKUP_DIR/workspace.tar.gz" 1024 "Workspace tar" || true
  else
    echo "  ❌ Workspace tar gagal: $(head -3 /tmp/ws-tar.err)"
    ERRORS=$((ERRORS+1))
  fi
fi

# 4) Backup config files
echo "→ Backup config..."
CFG_FILES=(server/data/users.json docker-compose.yml)
[ -f .env ] && CFG_FILES+=(.env)
[ -f server/data/audit.log ] && CFG_FILES+=(server/data/audit.log)
if tar czf "$BACKUP_DIR/config.tar.gz" -C "$(pwd)" "${CFG_FILES[@]}" 2>/tmp/cfg-tar.err; then
  require_nonempty "$BACKUP_DIR/config.tar.gz" 256 "Config tar" || true
else
  echo "  ❌ Config tar gagal: $(head -3 /tmp/cfg-tar.err)"
  ERRORS=$((ERRORS+1))
fi

# 5) Nginx site configs
echo "→ Backup nginx configs..."
if [ -d nginx ]; then
  tar czf "$BACKUP_DIR/nginx.tar.gz" -C "$(pwd)" nginx/
  require_nonempty "$BACKUP_DIR/nginx.tar.gz" 256 "Nginx tar" || true
fi

# 6) SSL certs
echo "→ Backup SSL..."
if [ -d /etc/letsencrypt ]; then
  tar czf "$BACKUP_DIR/letsencrypt.tar.gz" -C /etc letsencrypt/
  require_nonempty "$BACKUP_DIR/letsencrypt.tar.gz" 1024 "SSL tar" || true
fi

# 7) Manifest
cat > "$BACKUP_DIR/manifest.json" <<EOF
{
  "hostname": "$HOSTNAME",
  "timestamp": "$DATE",
  "domain": "${DOMAIN:-unknown}",
  "files": {
    "mysql": "$(ls -lh $BACKUP_DIR/mysql.sql.gz 2>/dev/null | awk '{print $5}')",
    "postgres": "$(ls -lh $BACKUP_DIR/postgres.sql.gz 2>/dev/null | awk '{print $5}')",
    "workspace": "$(ls -lh $BACKUP_DIR/workspace.tar.gz 2>/dev/null | awk '{print $5}')",
    "config": "$(ls -lh $BACKUP_DIR/config.tar.gz 2>/dev/null | awk '{print $5}')",
    "nginx": "$(ls -lh $BACKUP_DIR/nginx.tar.gz 2>/dev/null | awk '{print $5}')",
    "letsencrypt": "$(ls -lh $BACKUP_DIR/letsencrypt.tar.gz 2>/dev/null | awk '{print $5}')"
  },
  "errors_during_backup": $ERRORS
}
EOF

# 8) Critical artefacts gate — kalau MySQL+PG dump gagal, jangan upload latest pointer
CRITICAL_FAIL=0
if [ ! -s "$BACKUP_DIR/mysql.sql.gz" ] || [ ! -s "$BACKUP_DIR/postgres.sql.gz" ]; then
  CRITICAL_FAIL=1
  echo ""
  echo "⚠ CRITICAL: salah satu DB dump kosong/missing. Latest pointer TIDAK akan diupdate."
fi

# 9) Push ke R2 — strict, ANY upload failure = fatal
echo "→ Upload ke R2 ($R2_BUCKET)..."
command -v aws >/dev/null 2>&1 || { echo "❌ aws cli belum terinstall. Install: sudo apt install awscli -y"; exit 1; }

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_KEY"
export AWS_DEFAULT_REGION="auto"

REMOTE_PREFIX="$HOSTNAME/$DATE"
UPLOADED=0

for f in "$BACKUP_DIR"/*; do
  fname=$(basename "$f")
  echo "  ↑ $fname → s3://$R2_BUCKET/$REMOTE_PREFIX/$fname"
  if aws s3 cp "$f" "s3://$R2_BUCKET/$REMOTE_PREFIX/$fname" \
      --endpoint-url "$R2_ENDPOINT" --no-progress >/dev/null; then
    UPLOADED=$((UPLOADED+1))
  else
    echo "  ❌ Upload gagal: $fname"
    ERRORS=$((ERRORS+1))
    CRITICAL_FAIL=1
  fi
done

# 10) Verify upload — list remote folder & confirm manifest exists
if ! aws s3 ls "s3://$R2_BUCKET/$REMOTE_PREFIX/manifest.json" \
    --endpoint-url "$R2_ENDPOINT" >/dev/null 2>&1; then
  echo "❌ Verifikasi gagal: manifest.json tidak ada di R2 setelah upload."
  exit 2
fi

# 11) Latest pointer — HANYA kalau backup sukses kritis
if [ "$CRITICAL_FAIL" -eq 0 ]; then
  echo "$REMOTE_PREFIX" > /tmp/latest.txt
  if ! aws s3 cp /tmp/latest.txt "s3://$R2_BUCKET/$HOSTNAME/latest.txt" \
      --endpoint-url "$R2_ENDPOINT" --no-progress >/dev/null; then
    echo "❌ Latest pointer upload gagal."
    rm -f /tmp/latest.txt
    exit 3
  fi
  rm -f /tmp/latest.txt
  echo "  ✓ Latest pointer updated → $REMOTE_PREFIX"
else
  echo "  ⚠ Latest pointer NOT updated karena ada critical error."
fi

# 12) Retention: hapus backup di R2 yg lebih lama dari 14 hari (kecuali tanggal 1)
echo "→ Cleanup retention (keep 14 hari + monthly anchors)..."
CUTOFF=$(date -d '14 days ago' +%Y%m%d)
RETENTION_LIST=$(aws s3 ls "s3://$R2_BUCKET/$HOSTNAME/" \
  --endpoint-url "$R2_ENDPOINT" 2>/dev/null \
  | awk '{print $2}' | sed 's:/$::' | grep -E '^[0-9]{8}_[0-9]{6}$' || true)

if [ -n "$RETENTION_LIST" ]; then
  echo "$RETENTION_LIST" | while read -r folder; do
    DATE_PART="${folder%%_*}"
    DAY_OF_MONTH="${DATE_PART:6:2}"
    [ "$DAY_OF_MONTH" = "01" ] && continue
    if [ "$DATE_PART" -lt "$CUTOFF" ]; then
      echo "  🗑 Hapus old backup: $folder"
      aws s3 rm "s3://$R2_BUCKET/$HOSTNAME/$folder/" \
        --endpoint-url "$R2_ENDPOINT" --recursive --no-progress >/dev/null \
        || echo "    ⚠ retention delete failed for $folder (lanjut)"
    fi
  done
fi

echo ""
if [ "$CRITICAL_FAIL" -eq 0 ] && [ "$ERRORS" -eq 0 ]; then
  echo "✅ Backup selesai → s3://$R2_BUCKET/$REMOTE_PREFIX/ ($UPLOADED file)"
  exit 0
elif [ "$CRITICAL_FAIL" -eq 0 ]; then
  echo "⚠ Backup selesai dengan $ERRORS warning → s3://$R2_BUCKET/$REMOTE_PREFIX/"
  exit 0
else
  echo "❌ Backup FAILED dengan $ERRORS error. Latest pointer TIDAK diupdate."
  echo "   Folder partial tetap di s3://$R2_BUCKET/$REMOTE_PREFIX/ untuk inspeksi manual."
  exit 1
fi
