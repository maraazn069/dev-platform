#!/bin/bash
# ================================================================
# backup.sh — Backup harian: MySQL + PostgreSQL + workspace + audit log
#
# Auto-run via cron: lihat scripts/install-backup-cron.sh
# Manual: sudo bash scripts/backup.sh
#
# Retention default:
#   - 7 backup harian (terakhir)
#   - 4 backup mingguan (Minggu)
#   - 6 backup bulanan (tanggal 1)
#
# Backup disimpan di: /opt/devplatform/backups/
# ================================================================

set -uo pipefail

ERRORS=0
fail() { echo "[backup] ERROR: $1"; ERRORS=$((ERRORS+1)); }

# Lokasi & retention
BACKUP_ROOT="${BACKUP_ROOT:-/opt/devplatform/backups}"
DATA_DIR="${DATA_DIR:-/opt/devplatform/data}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/devplatform/platform}"
KEEP_DAILY=7
KEEP_WEEKLY=4
KEEP_MONTHLY=6

TS=$(date +%Y%m%d-%H%M%S)
DOW=$(date +%u)   # 1=Senin .. 7=Minggu
DOM=$(date +%d)   # tanggal 01-31

# Pilih kategori folder
CATEGORY="daily"
if [ "$DOM" = "01" ]; then CATEGORY="monthly"
elif [ "$DOW" = "7" ]; then CATEGORY="weekly"
fi

OUT_DIR="$BACKUP_ROOT/$CATEGORY/$TS"
mkdir -p "$OUT_DIR"

echo "[backup] mulai $TS → $OUT_DIR"

# Load .env supaya tahu password DB
if [ -f "$COMPOSE_DIR/.env" ]; then
  set -a; source "$COMPOSE_DIR/.env"; set +a
else
  echo "[backup] WARNING: $COMPOSE_DIR/.env tidak ditemukan, dump DB pakai default credentials di .env compose."
fi

# 1) PostgreSQL — semua database via pg_dumpall (logical, portable)
echo "[backup] dump PostgreSQL..."
set +e
docker exec -e PGPASSWORD="${POSTGRES_PASSWORD:-postgres}" devplatform-postgres \
  pg_dumpall -U postgres --clean --if-exists 2>/tmp/backup-pg.err | gzip > "$OUT_DIR/postgres-all.sql.gz"
PG_RC=${PIPESTATUS[0]}
set -e
if [ "$PG_RC" -ne 0 ] || [ ! -s "$OUT_DIR/postgres-all.sql.gz" ]; then
  fail "postgres dump gagal (rc=$PG_RC). Detail: $(head -3 /tmp/backup-pg.err 2>/dev/null)"
  rm -f "$OUT_DIR/postgres-all.sql.gz"
fi

# 2) MySQL — semua database
echo "[backup] dump MySQL..."
set +e
docker exec devplatform-mysql \
  sh -c "exec mysqldump -uroot -p\"\$MYSQL_ROOT_PASSWORD\" --all-databases --single-transaction --quick --routines --events 2>/tmp/backup-mysql.err" \
  | gzip > "$OUT_DIR/mysql-all.sql.gz"
MY_RC=${PIPESTATUS[0]}
set -e
if [ "$MY_RC" -ne 0 ] || [ ! -s "$OUT_DIR/mysql-all.sql.gz" ]; then
  fail "mysql dump gagal (rc=$MY_RC). Detail: $(docker exec devplatform-mysql cat /tmp/backup-mysql.err 2>/dev/null | head -3)"
  rm -f "$OUT_DIR/mysql-all.sql.gz"
fi

# 3) Workspace user (project files, config code-server). Skip .trash supaya hemat space.
echo "[backup] tar workspace..."
if [ -d "$DATA_DIR" ]; then
  set +e
  tar --warning=no-file-changed --exclude='*/.trash/*' --exclude='*/node_modules/*' --exclude='*/.cache/*' \
      -czf "$OUT_DIR/workspace.tar.gz" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>/tmp/backup-tar.err
  TAR_RC=$?
  set -e
  # tar exit 1 = "file changed while reading" → masih usable, tapi log warning.
  # tar exit 2 = error fatal → fail.
  if [ "$TAR_RC" -ge 2 ]; then
    fail "workspace tar gagal (rc=$TAR_RC). Detail: $(head -3 /tmp/backup-tar.err 2>/dev/null)"
  fi
fi

# 4) Portal data (users.json, audit.log, settings)
if [ -d "$COMPOSE_DIR/server/data" ]; then
  tar -czf "$OUT_DIR/portal-data.tar.gz" -C "$COMPOSE_DIR/server" data 2>/dev/null || fail "portal-data tar gagal"
fi

# 5) .env (kredensial — chmod 600)
if [ -f "$COMPOSE_DIR/.env" ]; then
  cp "$COMPOSE_DIR/.env" "$OUT_DIR/.env.backup"
  chmod 600 "$OUT_DIR/.env.backup"
fi

# Manifest
{
  echo "Backup time   : $TS"
  echo "Category      : $CATEGORY"
  echo "Hostname      : $(hostname)"
  echo "Files:"
  ls -lh "$OUT_DIR"
} > "$OUT_DIR/MANIFEST.txt"

# Total size
TOTAL=$(du -sh "$OUT_DIR" | awk '{print $1}')
echo "[backup] selesai. Ukuran $CATEGORY backup: $TOTAL"

# Rotation: hapus backup lama berdasarkan kategori
prune() {
  local CAT=$1
  local KEEP=$2
  local CAT_DIR="$BACKUP_ROOT/$CAT"
  if [ ! -d "$CAT_DIR" ]; then return; fi
  ls -1dt "$CAT_DIR"/*/ 2>/dev/null | tail -n +"$((KEEP+1))" | while read -r OLD; do
    echo "[backup] hapus lama: $OLD"
    rm -rf "$OLD"
  done
}
prune daily "$KEEP_DAILY"
prune weekly "$KEEP_WEEKLY"
prune monthly "$KEEP_MONTHLY"

if [ "$ERRORS" -gt 0 ]; then
  echo "[backup] SELESAI dengan $ERRORS error → $OUT_DIR"
  exit 1
fi
echo "[backup] DONE (tanpa error)."
