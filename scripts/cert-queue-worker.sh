#!/usr/bin/env bash
# Worker yang dipanggil cron (tiap 5 menit) untuk proses queue cert per-user.
#
# Portal nulis username ke server/data/cert-queue.txt setiap kali user baru di-provision.
# Worker ini baca file, request cert untuk tiap user, hapus dari queue kalau sukses.
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
LOCK_FILE="/tmp/devplatform-cert-queue.lock"

# Lock biar gak race condition kalau cron tumpang tindih
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date)] worker lain masih jalan, skip"; exit 0; }

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

# Dedup queue, simpan ke temp
TMP_QUEUE=$(mktemp)
sort -u "$QUEUE_FILE" | grep -E '^[a-z][a-z0-9_]{1,30}$' > "$TMP_QUEUE" || true

# Truncate original (kita rebuild kalau ada yg gagal)
> "$QUEUE_FILE"

PROCESSED=0
FAILED=0

while read -r USERNAME; do
  [ -z "$USERNAME" ] && continue
  CERT_NAME="${USERNAME}.${DOMAIN}"
  CERT_PATH="/etc/letsencrypt/live/${CERT_NAME}/fullchain.pem"

  if [ -f "$CERT_PATH" ]; then
    echo "[$(date)] cert ${CERT_NAME} already exists — skip"
    continue
  fi

  echo "[$(date)] processing $USERNAME..."
  if bash scripts/provision-user-cert.sh "$USERNAME" 2>&1; then
    echo "[$(date)]   ✓ cert issued for $USERNAME"
    PROCESSED=$((PROCESSED+1))
  else
    echo "[$(date)]   ❌ cert failed for $USERNAME — re-queuing"
    echo "$USERNAME" >> "$QUEUE_FILE"
    FAILED=$((FAILED+1))
  fi
done < "$TMP_QUEUE"

rm -f "$TMP_QUEUE"

echo "[$(date)] queue worker done — processed: $PROCESSED, failed (re-queued): $FAILED"
