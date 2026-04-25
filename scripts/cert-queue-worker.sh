#!/usr/bin/env bash
# Worker yang dipanggil cron (tiap 5 menit) untuk proses queue cert per-user.
#
# Portal nulis username ke server/data/cert-queue.txt setiap kali user baru di-provision.
# Worker ini baca file, request cert untuk tiap user, hapus dari queue kalau sukses.
#
# CRASH-SAFE design:
#   1. Lock untuk prevent concurrent run
#   2. Recovery: kalau ada .processing file orphan dari run sebelumnya yg crash, append balik ke queue
#   3. Atomic rename queue → .processing → exclusive copy untuk worker, queue file kosong lagi siap menerima request baru
#   4. Tiap user yg gagal, append KEMBALI ke queue (lock-protected) untuk retry next cron tick
#   5. .processing dihapus setelah loop selesai (semua entry tertangani: sukses atau re-queued)
#
# Setup cron sekali:
#   sudo bash scripts/install-backup-cron.sh   # script ini juga install cert-queue cron
# Atau manual:
#   echo "*/5 * * * * root cd /opt/devplatform && bash scripts/cert-queue-worker.sh >> /var/log/devplatform-cert-queue.log 2>&1" \
#     | sudo tee /etc/cron.d/devplatform-cert-queue
#   sudo chmod 644 /etc/cron.d/devplatform-cert-queue

set -uo pipefail

cd "$(dirname "$0")/.."

QUEUE_FILE="server/data/cert-queue.txt"
PROCESSING_FILE="server/data/cert-queue.processing"
LOCK_FILE="/tmp/devplatform-cert-queue.lock"

# Lock biar gak race condition kalau cron tumpang tindih
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date)] worker lain masih jalan, skip"; exit 0; }

# Pastikan queue file ada (touch idempotent)
touch "$QUEUE_FILE"

# RECOVERY: kalau ada .processing dari run sebelumnya yg crash, append balik ke queue
# (urutan: dedup terjadi nanti, jadi gpp ada duplicate sementara)
if [ -f "$PROCESSING_FILE" ]; then
  echo "[$(date)] recovering orphaned .processing file → re-queue"
  cat "$PROCESSING_FILE" >> "$QUEUE_FILE"
  rm -f "$PROCESSING_FILE"
fi

# Kalau queue masih kosong setelah recovery, exit
[ -s "$QUEUE_FILE" ] || exit 0

if [ -f .env ]; then
  set -a; source .env; set +a
fi

if [ -z "${DOMAIN:-}" ]; then
  echo "[$(date)] DOMAIN belum diset di .env, skip"
  exit 1
fi

if [ ! -f /etc/cloudflare/cloudflare.ini ]; then
  echo "[$(date)] /etc/cloudflare/cloudflare.ini tidak ada — setup-https.sh dulu"
  exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo "[$(date)] certbot tidak terinstall — setup-https.sh dulu"
  exit 1
fi

# CRASH-SAFE: atomic rename queue → processing. Queue file kembali kosong (touch),
# siap menerima request baru dari portal selama worker berjalan.
#
# Race window note: antara mv & touch ada gap mikrodetik di mana QUEUE_FILE belum ada.
# Portal pakai fs.appendFileSync(..., 'a') dengan flag default O_APPEND|O_CREAT, jadi
# kalau portal append tepat di gap ini, kernel akan auto-create file baru → entry
# tetap survive (worker proses next tick). TIDAK terjadi data loss.
mv "$QUEUE_FILE" "$PROCESSING_FILE"
touch "$QUEUE_FILE"

# Dedup processing (sort -u + valid pattern only)
TMP_DEDUP=$(mktemp)
sort -u "$PROCESSING_FILE" | grep -E '^[a-z][a-z0-9_]{1,30}$' > "$TMP_DEDUP" || true
mv "$TMP_DEDUP" "$PROCESSING_FILE"

PROCESSED=0
FAILED=0
SKIPPED=0

while read -r USERNAME; do
  [ -z "$USERNAME" ] && continue
  CERT_NAME="${USERNAME}.${DOMAIN}"
  CERT_PATH="/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem"

  if [ -f "$CERT_PATH" ]; then
    echo "[$(date)] cert ${CERT_NAME} already exists — skip"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  echo "[$(date)] processing $USERNAME..."
  if bash scripts/provision-user-cert.sh "$USERNAME" 2>&1; then
    echo "[$(date)]   ✓ cert issued for $USERNAME"
    PROCESSED=$((PROCESSED+1))
  else
    echo "[$(date)]   ❌ cert failed for $USERNAME — re-queuing for next tick"
    # Append back ke queue (file lock not strictly needed: portal append+flush sebelum we read,
    # but echo >> is atomic untuk single line < PIPE_BUF=4096 di Linux).
    echo "$USERNAME" >> "$QUEUE_FILE"
    FAILED=$((FAILED+1))
  fi
done < "$PROCESSING_FILE"

# Hapus processing file — semua entry sudah tertangani
rm -f "$PROCESSING_FILE"

echo "[$(date)] queue worker done — processed: $PROCESSED, skipped (already exists): $SKIPPED, failed (re-queued): $FAILED"
