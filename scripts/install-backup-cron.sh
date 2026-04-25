#!/bin/bash
# ================================================================
# install-backup-cron.sh — Daftarkan backup.sh ke cron root
#
# Pakai: sudo bash scripts/install-backup-cron.sh
#
# Default schedule: setiap hari jam 02:30 waktu server.
# Edit BACKUP_HOUR/BACKUP_MIN di bawah kalau mau ganti.
# ================================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Harap jalankan sebagai root: sudo bash scripts/install-backup-cron.sh"
  exit 1
fi

BACKUP_HOUR=${BACKUP_HOUR:-2}
BACKUP_MIN=${BACKUP_MIN:-30}
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/backup.sh"
LOG_PATH="/var/log/devplatform-backup.log"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "ERROR: $SCRIPT_PATH tidak ditemukan."
  exit 1
fi

chmod +x "$SCRIPT_PATH"

# Compose dir = parent dari scripts/
COMPOSE_DIR="$(dirname "$(dirname "$SCRIPT_PATH")")"
CRON_LINE="$BACKUP_MIN $BACKUP_HOUR * * * COMPOSE_DIR=$COMPOSE_DIR DATA_DIR=/opt/devplatform/data BACKUP_ROOT=/opt/devplatform/backups $SCRIPT_PATH >> $LOG_PATH 2>&1"
TAG="# devplatform-backup"

# Hapus entry lama, tambah baru
( crontab -l 2>/dev/null | grep -v "$TAG" ; echo "$CRON_LINE $TAG" ) | crontab -

touch "$LOG_PATH" && chmod 640 "$LOG_PATH"

# Pastikan logrotate untuk log backup
cat > /etc/logrotate.d/devplatform-backup <<EOF
$LOG_PATH {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "✓ Cron backup terpasang: setiap hari $BACKUP_HOUR:$(printf %02d $BACKUP_MIN)"
echo "✓ Output log: $LOG_PATH"
echo "✓ Backup tersimpan di: /opt/devplatform/backups/{daily,weekly,monthly}/"
echo ""
echo "Cek crontab:  sudo crontab -l"
echo "Test manual:  sudo bash $SCRIPT_PATH"
echo "Lihat log  :  tail -f $LOG_PATH"
