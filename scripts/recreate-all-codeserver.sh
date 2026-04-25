#!/usr/bin/env bash
# Rebuild image devplatform-codeserver:latest dari Dockerfile.codeserver,
# lalu IN-PLACE UPGRADE semua container codeserver-* user pake image baru.
#
# IN-PLACE UPGRADE = inspect container existing (env, mount, network, label) →
# stop+rm container lama → run container baru pakai konfigurasi yg sama TAPI image baru.
# Hasilnya: subdomain user langsung kerja lagi, tanpa harus login portal lagi.
#
# Data user (folder projects/) AMAN — di-mount dari /opt/devplatform/data, tidak ke-hapus.

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

NEW_IMAGE="${1:-devplatform-codeserver:latest}"

echo "════════════════════════════════════════════════════════"
echo "  Rebuild & in-place upgrade semua container code-server"
echo "════════════════════════════════════════════════════════"
echo ""

echo "→ [1/3] Build image $NEW_IMAGE..."
docker build -t "$NEW_IMAGE" -f Dockerfile.codeserver . || {
  echo "❌ Build gagal. Cek output di atas."
  exit 1
}
echo "  ✓ Image baru siap"
echo ""

USER_CONTAINERS=$(docker ps -a --filter "name=codeserver-" --format '{{.Names}}' | grep -v '^codeserver-base$' || true)

if [ -z "$USER_CONTAINERS" ]; then
  echo "→ [2/3] Tidak ada container codeserver-* user yang ada. Skip recreate."
  echo "✓ Selesai. User berikutnya yang bikin akun langsung pake image baru."
  exit 0
fi

echo "→ [2/3] Container yang akan di in-place upgrade:"
echo "$USER_CONTAINERS" | sed 's/^/    /'
echo ""

if [ -t 0 ]; then
  read -p "Lanjut (y/N)? " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Dibatalkan."; exit 0; }
else
  echo "(non-interactive — auto y)"
fi

echo ""
echo "→ [3/3] Inspect → stop → rm → run satu per satu..."

FAILED=()
SUCCESS=()

for c in $USER_CONTAINERS; do
  echo ""
  echo "  ▶ Processing $c..."

  # Inspect existing container untuk dapet semua config (env, mounts, network, restart, limits)
  INSPECT=$(docker inspect "$c" 2>/dev/null) || {
    echo "    ⚠ Container $c gak bisa di-inspect, skip."
    FAILED+=("$c")
    continue
  }

  # Extract config penting dari inspect output (pakai jq biar reliable)
  ENV_ARGS=$(echo "$INSPECT" | jq -r '.[0].Config.Env[]? | "-e\u0000" + .' | tr '\n' '\0' | xargs -0 -I{} echo {})
  # NB: kita pake null delimiter biar value yg ada spasi/newline tetap aman.

  # Bind mounts (host:container[:ro])
  MOUNT_ARGS=()
  while IFS= read -r mount; do
    [ -z "$mount" ] && continue
    MOUNT_ARGS+=(-v "$mount")
  done < <(echo "$INSPECT" | jq -r '.[0].Mounts[]? | select(.Type=="bind") | "\(.Source):\(.Destination)" + (if .Mode == "ro" then ":ro" else "" end)')

  # Network — ambil network pertama yg bukan default bridge
  NETWORK=$(echo "$INSPECT" | jq -r '.[0].NetworkSettings.Networks | keys[0] // "bridge"')

  # Resource limits
  MEMORY=$(echo "$INSPECT" | jq -r '.[0].HostConfig.Memory // 0')
  CPU_QUOTA=$(echo "$INSPECT" | jq -r '.[0].HostConfig.CpuQuota // 0')
  CPU_PERIOD=$(echo "$INSPECT" | jq -r '.[0].HostConfig.CpuPeriod // 100000')
  PIDS_LIMIT=$(echo "$INSPECT" | jq -r '.[0].HostConfig.PidsLimit // 0')
  RESTART_POLICY=$(echo "$INSPECT" | jq -r '.[0].HostConfig.RestartPolicy.Name // "no"')

  # Labels
  LABEL_ARGS=()
  while IFS= read -r label; do
    [ -z "$label" ] && continue
    LABEL_ARGS+=(--label "$label")
  done < <(echo "$INSPECT" | jq -r '.[0].Config.Labels // {} | to_entries[] | "\(.key)=\(.value)"')

  # Env args (preserved completely — ini yg bawa PASSWORD code-server)
  ENV_ARG_LIST=()
  while IFS= read -r ev; do
    [ -z "$ev" ] && continue
    ENV_ARG_LIST+=(-e "$ev")
  done < <(echo "$INSPECT" | jq -r '.[0].Config.Env[]?')

  # Stop & rm container lama
  docker stop "$c" >/dev/null 2>&1 || true
  docker rm -f "$c" >/dev/null 2>&1 || true

  # Build docker run command
  RUN_ARGS=(
    run -d
    --name "$c"
    --restart "$RESTART_POLICY"
    --network "$NETWORK"
    --security-opt no-new-privileges:true
    --log-opt max-size=10m
    --log-opt max-file=3
  )

  # Resource limits (kalau ada)
  if [ "$MEMORY" -gt 0 ]; then
    RUN_ARGS+=(--memory "$MEMORY" --memory-swap "$MEMORY")
  fi
  if [ "$CPU_QUOTA" -gt 0 ] && [ "$CPU_PERIOD" -gt 0 ]; then
    RUN_ARGS+=(--cpu-quota "$CPU_QUOTA" --cpu-period "$CPU_PERIOD")
  fi
  if [ "$PIDS_LIMIT" -gt 0 ]; then
    RUN_ARGS+=(--pids-limit "$PIDS_LIMIT")
  fi

  # Add env, mounts, labels
  RUN_ARGS+=("${ENV_ARG_LIST[@]}")
  RUN_ARGS+=("${MOUNT_ARGS[@]}")
  RUN_ARGS+=("${LABEL_ARGS[@]}")

  # Final: image
  RUN_ARGS+=("$NEW_IMAGE")

  if docker "${RUN_ARGS[@]}" >/dev/null; then
    echo "    ✓ $c berhasil di-upgrade ke image baru"
    SUCCESS+=("$c")
  else
    echo "    ✗ Gagal recreate $c"
    FAILED+=("$c")
  fi
done

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Hasil: ${#SUCCESS[@]} sukses, ${#FAILED[@]} gagal"
echo "════════════════════════════════════════════════════════"

if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Container yg gagal:"
  printf '    %s\n' "${FAILED[@]}"
  echo ""
  echo "Untuk recreate manual: login ke admin panel → tombol 'Repair' per user,"
  echo "atau dari portal: panel admin → Layanan → Restart Portal lalu user re-login."
  exit 1
fi

echo ""
echo "Semua container user udah pake image baru. User tinggal refresh browser:"
echo "  https://USERNAME.<DOMAIN>"
