#!/usr/bin/env bash
# Manual sync password admin ke File Browser & pgAdmin
# Berguna kalau:
#   - install pertama tidak pakai versi unified
#   - lupa password admin (sudah reset di .env, tinggal sync ke service)
#   - sync gagal saat ganti password lewat portal

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo: sudo bash scripts/sync-admin-password.sh"
  exit 1
fi

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "❌ File .env tidak ditemukan. Jalankan dari folder root project (~/dev-platform)"
  exit 1
fi

ADMIN_USERNAME=$(grep "^ADMIN_USERNAME=" .env | cut -d= -f2- | tr -d '"' | tr -d "'")
ADMIN_EMAIL=$(grep "^ADMIN_EMAIL=" .env | cut -d= -f2- | tr -d '"' | tr -d "'")
ADMIN_PASSWORD=$(grep "^ADMIN_PASSWORD=" .env | cut -d= -f2- | tr -d '"' | tr -d "'")

ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "❌ ADMIN_PASSWORD kosong di .env"
  exit 1
fi

echo "════════════════════════════════════════"
echo "Sync password admin tunggal"
echo "════════════════════════════════════════"
echo "Username : $ADMIN_USERNAME"
echo "Email    : ${ADMIN_EMAIL:-<kosong, pgAdmin akan di-skip>}"
echo "Password : ${ADMIN_PASSWORD:0:2}*****"
echo ""

# === File Browser ===
echo "→ Sync File Browser..."
FB_VOLUME=$(docker inspect devplatform-filebrowser --format '{{range .Mounts}}{{if eq .Destination "/database"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true)

if [ -z "$FB_VOLUME" ]; then
  echo "  ⚠ Container devplatform-filebrowser tidak ditemukan / belum jalan, skip"
else
  echo "  Volume terdeteksi: $FB_VOLUME"
  docker stop devplatform-filebrowser >/dev/null 2>&1 || true
  sleep 2

  # Helper: jalankan FB CLI di transient container.
  # WAJIB pakai image non-s6 (v2.30.0) — image :s6 binary-nya di subfolder
  # service s6, bukan di /filebrowser, jadi `--entrypoint /filebrowser` GAGAL.
  # Issue: https://github.com/filebrowser/filebrowser/issues/5167
  fb_cli() {
    docker run --rm \
      -v "${FB_VOLUME}":/database \
      --entrypoint /filebrowser \
      filebrowser/filebrowser:v2.30.0 \
      "$@" --database /database/filebrowser.db 2>&1
  }

  # Strategi paling solid: hapus user (kalau ada) lalu add ulang dengan password baru.
  # Ini selalu sukses tanpa tergantung apakah user sudah ada atau belum.
  fb_cli users rm "$ADMIN_USERNAME" >/dev/null 2>&1 || true
  FB_OUT=$(fb_cli users add "$ADMIN_USERNAME" "$ADMIN_PASSWORD" --perm.admin)
  FB_RC=$?

  docker start devplatform-filebrowser >/dev/null 2>&1 || true
  sleep 3

  if [ $FB_RC -ne 0 ] || echo "$FB_OUT" | grep -qiE "error|fatal|failed"; then
    echo "  ⚠ File Browser sync gagal:"
    echo "$FB_OUT" | tail -5 | sed 's/^/    /'
    echo "  Coba manual:"
    echo "    sudo docker stop devplatform-filebrowser"
    echo "    sudo docker run --rm -v ${FB_VOLUME}:/database --entrypoint /filebrowser \\"
    echo "      filebrowser/filebrowser:s6 users add $ADMIN_USERNAME 'PASSWORD_BARU' \\"
    echo "      --perm.admin --database /database/filebrowser.db"
    echo "    sudo docker start devplatform-filebrowser"
  else
    echo "  ✓ File Browser admin: $ADMIN_USERNAME (password baru aktif, login dgn user '$ADMIN_USERNAME')"
  fi
fi

echo ""

# === pgAdmin ===
if [ -z "$ADMIN_EMAIL" ]; then
  echo "→ pgAdmin: skip (ADMIN_EMAIL kosong di .env)"
else
  echo "→ Sync pgAdmin..."
  echo "  Tunggu pgAdmin siap..."
  for i in 1 2 3 4 5 6 7 8; do
    if docker exec devplatform-pgadmin test -f /pgadmin4/setup.py 2>/dev/null; then
      break
    fi
    sleep 4
  done

  PG_OUT=$(docker exec devplatform-pgadmin /venv/bin/python /pgadmin4/setup.py update-password \
    --user "$ADMIN_EMAIL" --password "$ADMIN_PASSWORD" 2>&1 || \
    docker exec devplatform-pgadmin python /pgadmin4/setup.py update-password \
    --user "$ADMIN_EMAIL" --password "$ADMIN_PASSWORD" 2>&1 || true)

  if echo "$PG_OUT" | grep -qiE "error|not found|no user"; then
    echo "  ⚠ pgAdmin sync gagal:"
    echo "$PG_OUT" | tail -3 | sed 's/^/    /'
    echo "  Mungkin user pgAdmin belum dibuat. Coba login manual ke pgAdmin dulu pakai PGADMIN_EMAIL/PASSWORD lama dari .env."
  else
    echo "  ✓ pgAdmin admin: $ADMIN_EMAIL (password baru aktif)"
  fi
fi

echo ""
echo "════════════════════════════════════════"
echo "✓ Selesai"
echo "════════════════════════════════════════"
echo ""
echo "Test login sekarang:"
echo "  Portal       : https://$(grep '^DOMAIN=' .env | cut -d= -f2-)              user: $ADMIN_USERNAME"
echo "  File Browser : https://files.$(grep '^DOMAIN=' .env | cut -d= -f2-)        user: $ADMIN_USERNAME"
[ -n "$ADMIN_EMAIL" ] && echo "  pgAdmin      : https://pgadmin.$(grep '^DOMAIN=' .env | cut -d= -f2-)      email: $ADMIN_EMAIL"
echo ""
echo "Semua pakai password yang sama (yang ada di ADMIN_PASSWORD .env)"
