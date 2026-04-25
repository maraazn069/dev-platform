#!/usr/bin/env bash
# Rebuild image devplatform-codeserver:latest dari Dockerfile.codeserver,
# lalu recreate SEMUA container codeserver-* user supaya pake image baru.
#
# Kapan dipakai:
#   - Setelah edit Dockerfile.codeserver (tambah runtime, dll)
#   - Setelah pull update dev-platform yg ngasih image baru
#   - Kalau container user error & perlu refresh
#
# CATATAN: data user (folder projects/) AMAN — di-mount dari /opt/devplatform/data,
# jadi recreate container TIDAK menghapus file user.

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Jalankan dengan sudo: sudo bash scripts/recreate-all-codeserver.sh"
  exit 1
fi

cd "$(dirname "$0")/.."

if [ ! -f Dockerfile.codeserver ]; then
  echo "❌ Dockerfile.codeserver tidak ditemukan."
  exit 1
fi

echo "════════════════════════════════════════════════════════"
echo "  Rebuild & recreate semua container code-server"
echo "════════════════════════════════════════════════════════"
echo ""

echo "→ [1/3] Build image devplatform-codeserver:latest..."
docker build -t devplatform-codeserver:latest -f Dockerfile.codeserver . || {
  echo "❌ Build gagal. Cek output di atas."
  exit 1
}
echo "  ✓ Image baru siap"
echo ""

USER_CONTAINERS=$(docker ps -a --filter "name=codeserver-" --format '{{.Names}}' | grep -v '^codeserver-base$' || true)

if [ -z "$USER_CONTAINERS" ]; then
  echo "→ [2/3] Tidak ada container codeserver-* user yang aktif. Skip recreate."
  echo ""
  echo "✓ Selesai. Saat user login berikutnya, container baru pake image terbaru."
  exit 0
fi

echo "→ [2/3] Container yang akan di-recreate:"
echo "$USER_CONTAINERS" | sed 's/^/    /'
echo ""

read -p "Lanjut recreate (y/N)? " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Dibatalkan."; exit 0; }

echo ""
echo "→ [3/3] Stop & recreate satu per satu..."
FAILED=()
for c in $USER_CONTAINERS; do
  username=${c#codeserver-}
  echo "  • $c (user: $username)..."

  # Capture full run config from existing container, then rm & recreate.
  # Cara paling aman: extract env+volume+name, lalu rm, lalu portal akan auto-create
  # waktu user login berikutnya. Tapi karena user mungkin lagi pakai, kita
  # restart in-place dengan image baru pakai docker rm + docker run yang sama.
  #
  # Strategi simpler: cuma stop+rm — biarkan portal recreate saat user login
  # berikutnya. Kalau user lagi aktif, mereka tinggal refresh halaman portal
  # dan klik buka project lagi → portal panggil createCodeServerContainer otomatis.
  docker stop "$c" >/dev/null 2>&1 || true
  docker rm "$c" >/dev/null 2>&1 || FAILED+=("$c")
done

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "⚠ Gagal hapus: ${FAILED[*]}"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "✓ Selesai."
echo "════════════════════════════════════════════════════════"
echo ""
echo "User yang sedang login akan otomatis dapat container baru saat"
echo "buka project dari dashboard. File user tidak hilang (di-mount)."
echo ""
echo "Kalau mau force-recreate sekarang juga:"
echo "  Login ke admin panel → tombol 'Repair' di tabel user → 'Repair All'"
