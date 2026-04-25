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

CRON_LINE="0 2 * * * cd $PROJECT_DIR && bash $SCRIPT_PATH >> $LOG_PATH 2>&1"

# Add ke root crontab kalau belum ada
( crontab -l 2>/dev/null | grep -v "backup-to-r2.sh" ; echo "$CRON_LINE" ) | crontab -

echo "✅ Cron terpasang. Backup otomatis tiap hari jam 02:00."
echo "   Log: $LOG_PATH"
echo "   Cek crontab: crontab -l"
echo ""
echo "Test manual sekarang:"
echo "  sudo bash $SCRIPT_PATH"
