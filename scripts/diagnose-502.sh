#!/usr/bin/env bash
# Diagnosa 502 Bad Gateway untuk subdomain user (e.g., test.dev.netprem.org).
# Cek: container ada/jalan, image up-to-date, network nyambung, nginx route benar.
#
# Pakai: sudo bash scripts/diagnose-502.sh <username>
#   atau: sudo bash scripts/diagnose-502.sh --all   (cek semua user)

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo: sudo bash scripts/diagnose-502.sh <username>"
  exit 1
fi

cd "$(dirname "$0")/.."

DOMAIN="${DOMAIN:-$(grep -E '^DOMAIN=' .env 2>/dev/null | cut -d= -f2 | tr -d '\"')}"
DOMAIN="${DOMAIN:-dev.example.com}"
NETWORK="${DOCKER_NETWORK:-dev-platform_devnet}"

check_user() {
  local user="$1"
  local container="codeserver-$user"
  local subdomain="$user.$DOMAIN"
  local issues=0

  echo ""
  echo "═══ User: $user ═══"
  echo "Subdomain: https://$subdomain"
  echo ""

  # 1) Container exists?
  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "  ❌ Container '$container' TIDAK ADA."
    echo "     Fix: login admin → tombol 'Repair Container', atau tambah ulang user."
    return 1
  fi
  echo "  ✓ Container ada"

  # 2) Container running?
  STATUS=$(docker inspect --format '{{.State.Status}}' "$container")
  if [ "$STATUS" != "running" ]; then
    echo "  ❌ Container status: $STATUS (bukan running)"
    echo "     Try: docker start $container"
    echo "     Atau cek log: docker logs --tail 50 $container"
    issues=$((issues+1))
  else
    echo "  ✓ Container running"
  fi

  # 3) Image yang dipake mana?
  IMAGE=$(docker inspect --format '{{.Config.Image}}' "$container")
  echo "  ℹ Image: $IMAGE"

  # 4) Network — sama dengan portal?
  NETWORKS=$(docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$container")
  if ! echo "$NETWORKS" | grep -q "$NETWORK"; then
    echo "  ❌ Container BUKAN di network '$NETWORK' (ada di: $NETWORKS)"
    echo "     Fix: docker network connect $NETWORK $container"
    issues=$((issues+1))
  else
    echo "  ✓ Network OK ($NETWORK)"
  fi

  # 5) Healthcheck dari portal — bisa reach container port 8443?
  if docker exec devplatform-portal sh -c "wget -q -T 5 -O /dev/null http://$container:8443/" 2>/dev/null; then
    echo "  ✓ Portal bisa reach $container:8443"
  else
    # Coba dari host
    IP=$(docker inspect --format "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}" "$container" 2>/dev/null)
    if [ -n "$IP" ]; then
      if curl -sf -m 5 -o /dev/null "http://$IP:8443/"; then
        echo "  ✓ Container respond di IP $IP:8443"
      else
        echo "  ⚠ Container TIDAK respond di IP $IP:8443"
        echo "     Cek log: docker logs --tail 50 $container"
        issues=$((issues+1))
      fi
    else
      echo "  ❌ Container gak punya IP di network $NETWORK"
      issues=$((issues+1))
    fi
  fi

  # 6) Nginx config — ada server_name untuk subdomain ini?
  if docker exec devplatform-nginx grep -rq "$subdomain" /etc/nginx/conf.d/ 2>/dev/null; then
    echo "  ✓ Nginx ada config untuk $subdomain (per-user)"
  else
    if docker exec devplatform-nginx grep -rq '\*\.'"$DOMAIN" /etc/nginx/conf.d/ 2>/dev/null; then
      echo "  ✓ Nginx ada wildcard config *.$DOMAIN (catch-all → routing pakai Host header)"
    else
      echo "  ❌ Nginx GAK ADA config untuk $subdomain dan GAK ADA wildcard *.$DOMAIN"
      issues=$((issues+1))
    fi
  fi

  echo ""
  if [ $issues -eq 0 ]; then
    echo "  ✅ Tidak ada issue terdeteksi. Kalau masih 502, cek:"
    echo "     - DNS Cloudflare untuk $subdomain (harus point ke VPS)"
    echo "     - SSL cert valid (cek di browser)"
    echo "     - Browser cache (try hard reload Ctrl+Shift+R)"
  else
    echo "  ⚠ $issues issue ditemukan. Fix dulu di atas."
  fi
  return $issues
}

if [ "$1" = "--all" ] || [ -z "$1" ]; then
  USERS=$(docker ps -a --filter "name=codeserver-" --format '{{.Names}}' | sed 's/^codeserver-//' | grep -v '^base$')
  if [ -z "$USERS" ]; then
    echo "Tidak ada user code-server."
    exit 0
  fi
  TOTAL_ISSUES=0
  for u in $USERS; do
    check_user "$u" || TOTAL_ISSUES=$((TOTAL_ISSUES+1))
  done
  echo ""
  echo "════════════════════════════════════════"
  if [ $TOTAL_ISSUES -eq 0 ]; then
    echo "✅ Semua user OK"
  else
    echo "⚠ $TOTAL_ISSUES user punya issue"
  fi
else
  check_user "$1"
fi
