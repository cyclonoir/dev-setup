#!/usr/bin/env bash
# Run the package-level steps for real in a throwaway Ubuntu 26.04 container. This catches wrong
# package names and broken repo setup. The desktop session, greetd switching and KVM can't be
# tested this way; use a VM or the laptop for those.
#
# Usage: tests/container-test.sh [steps]   (default: compliance,base,fonts,hyprland,browsers,noctalia,mise,podman,virt)
# Needs Docker or Podman; run with sudo if your user can't reach the Docker socket.
# Console output and the container's install.log are saved under tests/logs/.

set -euo pipefail

engine=${ENGINE:-$(command -v podman || command -v docker || true)}
[[ -n "$engine" ]] || { echo "Docker or Podman is required." >&2; exit 1; }

repo=$(cd "$(dirname "$0")/.." && pwd)
# compliance is included so the work-machine path (Edge) is tested; its checks just warn here.
steps=${1:-compliance,base,fonts,hyprland,browsers,noctalia,mise,podman,virt}
stamp=$(date +%Y%m%d-%H%M%S)
log_dir="$repo/tests/logs"
owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
mkdir -p "$log_dir"

set +e
"$engine" run --rm -t -v "$repo:/opt/dev-setup:ro" -v "$log_dir:/logs" ubuntu:26.04 bash -uo pipefail -c "
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo curl ca-certificates >/dev/null
  useradd -m -s /bin/bash adam.miller
  # Mimic an AD (SSSD) account, which has no subuid/subgid ranges, so the podman step's fix runs.
  sed -i '/^adam.miller:/d' /etc/subuid /etc/subgid
  echo 'adam.miller ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/container-test
  su - adam.miller -c 'cd /opt/dev-setup && ./install.sh --only $steps'
  first=\$?
  echo
  echo '=== second run (should change nothing) ==='
  su - adam.miller -c 'cd /opt/dev-setup && ./install.sh --only $steps'
  second=\$?
  cp /home/adam.miller/.local/state/dev-setup/install.log /logs/install-$stamp.log
  chown $owner /logs/install-$stamp.log
  echo \"first run exit: \$first, second run exit: \$second\"
  exit \$(( first || second ))
" 2>&1 | tee "$log_dir/console-$stamp.out"
status=${PIPESTATUS[0]}
set -e

chown "$owner" "$log_dir/console-$stamp.out" 2>/dev/null || true
echo "Saved: $log_dir/console-$stamp.out and $log_dir/install-$stamp.log (exit $status)"
exit "$status"
