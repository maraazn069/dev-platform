#!/usr/bin/env bash
# Pasang backup-to-r2.sh ke cron (jalan tiap hari jam 2 pagi).

set -e
if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

cd "$(dirname "$0")/.."
PROJECT_DIR="$(pwd)"
SCRIPT_PATH="$PROJECT_DIR/scripts/backup-to-r2.sh"
LOG_PATH="/var/log/devplatform-backup.log"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "❌ Script backup-to-r2.sh tidak ditemukan."
  exit 1
fi

BACKUP_CRON="0 2 * * * cd $PROJECT_DIR && bash $SCRIPT_PATH >> $LOG_PATH 2>&1"

# Cert queue worker — jalan tiap 5 menit, request *.<user>.DOMAIN cert untuk
# user baru yg di-queue oleh portal di server/data/cert-queue.txt.
CERT_WORKER="$PROJECT_DIR/scripts/cert-queue-worker.sh"
CERT_LOG="/var/log/devplatform-cert-queue.log"
CERT_CRON="*/5 * * * * cd $PROJECT_DIR && bash $CERT_WORKER >> $CERT_LOG 2>&1"

# Add ke root crontab (replace baris lama kalau ada)
( crontab -l 2>/dev/null \
  | grep -v "backup-to-r2.sh" \
  | grep -v "cert-queue-worker.sh" \
  ; echo "$BACKUP_CRON" \
  ; [ -f "$CERT_WORKER" ] && echo "$CERT_CRON" \
) | crontab -

echo "✅ Cron terpasang:"
echo "   - Backup R2:   tiap hari 02:00 → $LOG_PATH"
[ -f "$CERT_WORKER" ] && echo "   - Cert queue:  tiap 5 menit → $CERT_LOG"
echo ""
echo "Cek crontab: crontab -l"
echo ""
echo "Test manual:"
echo "  sudo bash $SCRIPT_PATH"
[ -f "$CERT_WORKER" ] && echo "  sudo bash $CERT_WORKER"
