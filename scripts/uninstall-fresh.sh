#!/usr/bin/env bash
# Uninstall TOTAL — bersihkan semua jejak dev platform di VPS untuk persiapan install fresh.
#
# Yang dihapus:
#   - Semua container devplatform-* (portal, nginx, mysql, postgres, code-server-<user>, dll)
#   - Semua docker volume terkait (mysql_data, postgres_data, dst)
#   - Semua docker network terkait (devplatform_default)
#   - Semua user data /opt/devplatform/data/<user>/* (workspace, .trash)
#   - Semua nginx user conf /etc/nginx/users/*.conf (lewat mount)
#   - Cron jobs cert-queue, backup
#   - File log /var/log/devplatform-*.log
#
# Yang DIPERTAHANKAN (untuk fresh install lebih cepat):
#   - Cert Let's Encrypt /etc/letsencrypt/live/* (biar gak rate-limit)
#   - /etc/cloudflare/cloudflare.ini (API token)
#   - File .env (biar password DB sama setelah reinstall — kalau mau full reset, hapus manual)
#
# Pakai:
#   sudo bash scripts/uninstall-fresh.sh           # interactive, butuh ketik YES
#   sudo bash scripts/uninstall-fresh.sh --force   # skip prompt
#   sudo bash scripts/uninstall-fresh.sh --nuke    # hapus juga cert + .env (full nuclear)

set -uo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo."
  exit 1
fi

cd "$(dirname "$0")/.."

FORCE=0
NUKE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --nuke)  NUKE=1; FORCE=1 ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

echo "════════════════════════════════════════════════════════"
echo "  UNINSTALL TOTAL — DEV PLATFORM"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Yang akan dihapus:"
echo "  • Semua container devplatform-* + codeserver-*"
echo "  • Semua docker volume (mysql_data, postgres_data, dll)"
echo "  • Semua data user di /opt/devplatform/data/"
echo "  • Semua nginx user conf"
echo "  • Cron jobs (cert-queue, backup)"
if [ "$NUKE" = "1" ]; then
  echo "  • [NUKE] Cert Let's Encrypt /etc/letsencrypt/live/*.${DOMAIN:-DOMAIN}"
  echo "  • [NUKE] /etc/cloudflare/cloudflare.ini"
  echo "  • [NUKE] File .env"
fi
echo ""
echo "Yang DIPERTAHANKAN:"
if [ "$NUKE" = "0" ]; then
  echo "  • Cert Let's Encrypt (untuk hindari rate-limit saat reinstall)"
  echo "  • /etc/cloudflare/cloudflare.ini"
  echo "  • File .env"
fi
echo "  • Source code repo (file-file ini)"
echo "  • Docker engine & nginx host"
echo ""

if [ "$FORCE" != "1" ]; then
  read -p "LANJUT? Ketik 'UNINSTALL' (huruf besar): " C
  [ "$C" = "UNINSTALL" ] || { echo "Dibatalkan."; exit 0; }
fi

echo ""
echo "[1/7] Stop & remove docker compose stack..."
docker compose down -v --remove-orphans 2>&1 | sed 's/^/  /' || true

echo ""
echo "[2/7] Remove sisa container code-server / phantom..."
# NOTE: docker --filter berturut-turut adalah AND, bukan OR. Jadi kita panggil 2x lalu uniq.
CONTAINERS=$( {
  docker ps -aq --filter "name=codeserver-" 2>/dev/null
  docker ps -aq --filter "name=devplatform-" 2>/dev/null
} | sort -u | tr -d ' ')
if [ -n "$CONTAINERS" ]; then
  echo "$CONTAINERS" | xargs -r docker rm -f 2>&1 | sed 's/^/  /'
else
  echo "  (tidak ada)"
fi

echo ""
echo "[3/7] Remove docker volume sisa..."
VOLUMES=$(docker volume ls -q --filter "name=devplatform" 2>/dev/null || true)
if [ -n "$VOLUMES" ]; then
  echo "$VOLUMES" | xargs -r docker volume rm -f 2>&1 | sed 's/^/  /'
else
  echo "  (tidak ada)"
fi
# Volume ekstra: codeserver-<user>-config
EXTRA_VOL=$(docker volume ls -q --filter "name=codeserver-" 2>/dev/null || true)
if [ -n "$EXTRA_VOL" ]; then
  echo "$EXTRA_VOL" | xargs -r docker volume rm -f 2>&1 | sed 's/^/  /'
fi

echo ""
echo "[4/7] Remove docker network..."
docker network rm devplatform_default 2>/dev/null && echo "  ✓ devplatform_default removed" || echo "  (tidak ada)"

echo ""
echo "[5/7] Hapus data user /opt/devplatform/data/..."
if [ -d /opt/devplatform/data ]; then
  rm -rf /opt/devplatform/data/*
  echo "  ✓ /opt/devplatform/data/* dihapus"
else
  echo "  (tidak ada)"
fi

echo ""
echo "[6/7] Hapus nginx user conf + cron jobs + log..."
rm -f nginx/users/*.conf 2>/dev/null && echo "  ✓ nginx/users/*.conf cleared" || true
rm -f server/data/cert-queue.txt server/data/cert-queue.processing 2>/dev/null || true
rm -f /etc/cron.d/devplatform-cert-queue /etc/cron.d/devplatform-backup 2>/dev/null && \
  echo "  ✓ cron jobs cleared" || true
rm -f /var/log/devplatform-*.log 2>/dev/null && echo "  ✓ log files cleared" || true

# Reset users.json ke admin-only kalau ada
if [ -f server/data/users.json ]; then
  # Backup ke .uninstalled biar bisa rescue manual
  cp server/data/users.json "server/data/users.json.uninstalled-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  echo "[]" > server/data/users.json
  echo "  ✓ users.json di-reset (backup .uninstalled-* dibuat)"
fi
rm -f server/data/audit.log* 2>/dev/null && echo "  ✓ audit.log cleared" || true

echo ""
echo "[7/7] Optional --nuke: cert + .env + cloudflare token..."
if [ "$NUKE" = "1" ]; then
  if [ -f .env ]; then source .env; fi
  if [ -n "${DOMAIN:-}" ]; then
    # Hapus cert untuk DOMAIN apex (=$DOMAIN) + per-user (=*.user.$DOMAIN, certbot
    # default name-nya jadi <user>.$DOMAIN). HANYA cert yg cocok EXACT pattern berikut:
    #   1) Nama persis = $DOMAIN  (cert apex *.$DOMAIN)
    #   2) Nama = <subdomain-tunggal>.$DOMAIN  (cert per-user *.<user>.$DOMAIN)
    # Pakai grep -Ex (anchored) supaya cert lain di VPS yg KEBETULAN mengandung
    # substring $DOMAIN tidak ikut terhapus.
    if command -v certbot >/dev/null 2>&1; then
      ESC_DOMAIN=$(printf '%s\n' "$DOMAIN" | sed 's/[.[\*^$()+?{|]/\\&/g')
      ANCHORED_REGEX="^(${ESC_DOMAIN}|[a-z][a-z0-9_-]*\.${ESC_DOMAIN})$"
      echo "  → cari cert yg match: $ANCHORED_REGEX"
      certbot certificates 2>/dev/null \
        | awk '/Certificate Name:/ {print $3}' \
        | grep -Ex "$ANCHORED_REGEX" \
        | while read -r CN; do
            echo "  → delete cert: $CN"
            certbot delete --cert-name "$CN" --non-interactive 2>&1 | sed 's/^/    /'
          done
    fi
  fi
  rm -f /etc/cloudflare/cloudflare.ini && echo "  ✓ /etc/cloudflare/cloudflare.ini deleted" || true
  rm -f .env && echo "  ✓ .env deleted" || true
else
  echo "  (skip — pakai --nuke untuk hapus cert+env)"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ UNINSTALL SELESAI"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Untuk install fresh, jalankan:"
echo "  sudo bash scripts/install-vps.sh        # bootstrap docker, cert, nginx"
echo "  sudo bash scripts/setup-https.sh        # issue wildcard cert"
echo "  sudo bash scripts/migrate-to-opsi-c.sh  # set struktur Opsi C"
echo "  sudo bash scripts/install-backup-cron.sh"
echo ""
echo "Atau cek PERINTAH.md untuk panduan lengkap."
