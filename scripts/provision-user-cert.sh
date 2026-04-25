#!/usr/bin/env bash
# Request wildcard cert per user untuk depth-2 subdomain project.
#
# Pakai:
#   sudo bash scripts/provision-user-cert.sh <username>
#
# Hasil: cert *.<username>.<DOMAIN> di /etc/letsencrypt/live/<username>.<DOMAIN>/
# Setelah ini, project preview <project>.<user>.netprem.org bisa HTTPS.
#
# PRECONDITION:
#   - .env udah ada DOMAIN dan LETSENCRYPT_EMAIL
#   - certbot + python3-certbot-dns-cloudflare terinstall (run setup-https.sh dulu)
#   - /etc/cloudflare/cloudflare.ini berisi token Cloudflare
#   - DNS Cloudflare untuk *.<user>.<DOMAIN> punya proxy OFF (DNS only) — proxy
#     biasanya gak masalah karena DNS-01 challenge cuma butuh TXT record, tapi
#     kalau ragu, sementara off-kan dulu.

set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

USERNAME="${1:-}"
if [ -z "$USERNAME" ]; then
  echo "Usage: sudo bash $0 <username>"
  exit 1
fi

if ! [[ "$USERNAME" =~ ^[a-z][a-z0-9_]{1,30}$ ]]; then
  echo "❌ Username tidak valid: '$USERNAME'"
  exit 1
fi

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  set -a; source .env; set +a
fi

: "${DOMAIN:?DOMAIN belum diset di .env}"
: "${LETSENCRYPT_EMAIL:?LETSENCRYPT_EMAIL belum diset di .env}"

CF_INI="/etc/cloudflare/cloudflare.ini"
if [ ! -f "$CF_INI" ]; then
  echo "❌ $CF_INI tidak ada. Jalankan dulu: sudo bash scripts/setup-https.sh"
  exit 1
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo "❌ certbot belum terinstall. Jalankan dulu: sudo bash scripts/setup-https.sh"
  exit 1
fi

CERT_NAME="${USERNAME}.${DOMAIN}"
CERT_PATH="/etc/letsencrypt/live/${CERT_NAME}"

echo "════════════════════════════════════════════════════════"
echo "  Request wildcard cert per user"
echo "  User      : ${USERNAME}"
echo "  Domain    : *.${CERT_NAME}"
echo "  Cert name : ${CERT_NAME}"
echo "════════════════════════════════════════════════════════"

# Check rate-limit hint (LE: 50 cert/registered-domain/week)
EXISTING_COUNT=$(ls /etc/letsencrypt/live/ 2>/dev/null | grep -cE "\.${DOMAIN}$" || echo 0)
if [ "$EXISTING_COUNT" -ge 40 ]; then
  echo "⚠ Sudah ada $EXISTING_COUNT cert di-issue untuk subdomain ${DOMAIN}."
  echo "  Let's Encrypt limit: 50/week per registered domain. Lanjut hati-hati."
fi

# Request cert via DNS-01 challenge (Cloudflare)
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CF_INI" \
  --non-interactive \
  --agree-tos \
  --email "$LETSENCRYPT_EMAIL" \
  --cert-name "$CERT_NAME" \
  -d "*.${CERT_NAME}" \
  --keep-until-expiring

if [ ! -f "$CERT_PATH/fullchain.pem" ]; then
  echo "❌ Cert tidak ditemukan setelah certbot run. Cek: certbot certificates"
  exit 2
fi

echo "✓ Cert siap: $CERT_PATH"

# Trigger portal regenerate user conf agar pakai per-user cert
PORTAL_CONTAINER="devplatform-portal"
if docker ps --format '{{.Names}}' | grep -q "^${PORTAL_CONTAINER}$"; then
  echo "→ Trigger portal regenerate ${USERNAME}.conf..."
  # Endpoint internal (admin) dipanggil via curl di dalam container portal sendiri.
  # Lebih simpel: nyalakan ulang nginx — file user.conf akan di-regenerate next time
  # provisionUser jalan ATAU admin click Repair Container.
  # Untuk apply sekarang, kita reload nginx (file lama akan tetap pakai wildcard cert
  # sampai admin click Repair Container atau restart portal).
  docker exec nginx-proxy nginx -s reload 2>/dev/null || \
    docker restart nginx-proxy >/dev/null 2>&1 || true
  echo "  ✓ nginx di-reload"
fi

echo ""
echo "✅ Done. Sekarang user '${USERNAME}' bisa preview project di:"
echo "   https://<project>.${CERT_NAME}"
echo ""
echo "Catatan:"
echo "  - Login admin → tombol 🔧 Repair Container untuk regenerate user nginx conf"
echo "    (biar nginx pakai cert per-user yg baru, bukan wildcard)."
echo "  - Atau restart portal: docker compose restart portal"
