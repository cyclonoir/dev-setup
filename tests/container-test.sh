#!/usr/bin/env bash
# Run the package-level steps for real in a throwaway Ubuntu 26.04 container, twice. The first run
# catches wrong package names and broken repo setup; the second must change nothing (any logged
# change other than apt-get update fails the test). The desktop session, greetd switching and KVM
# can't be tested this way; use a VM or the laptop for those.
#
# Usage: tests/container-test.sh [steps]   (default: base,fonts,hyprland,browsers,noctalia,theme,mise,shell,podman,virt)
#        WORK_FLAG= tests/container-test.sh [steps]   (personal path: no --work, so no Edge)
# By default it passes --work to test the work-machine path (Edge); the IT checks just warn here.
# Needs Docker or Podman; run with sudo if your user can't reach the Docker socket.
# Console output and the container's install.log are saved under tests/logs/.

set -euo pipefail

engine=${ENGINE:-$(command -v podman || command -v docker || true)}
[[ -n "$engine" ]] || { echo "Docker or Podman is required." >&2; exit 1; }

repo=$(cd "$(dirname "$0")/.." && pwd)
steps=${1:-base,fonts,hyprland,browsers,noctalia,theme,mise,shell,podman,virt}
work_flag=${WORK_FLAG---work}
stamp=$(date +%Y%m%d-%H%M%S)
log_dir="$repo/tests/logs"
owner="${SUDO_UID:-$(id -u)}:${SUDO_GID:-$(id -g)}"
mkdir -p "$log_dir"

# A throwaway account inside the container. The dot mimics AD-style names like first.last; the
# scripts themselves always use whoever runs them.
test_user="test.user"

inner="$log_dir/inner-$stamp.sh"
cat >"$inner" <<EOF
set -uo pipefail
# Only sudo: curl is deliberately left out, as on a stock Ubuntu desktop, so preflight must cope.
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo >/dev/null
useradd -m -s /bin/bash $test_user
# Mimic an AD-only machine: no subuid/subgid files at all, so the podman step must create them.
rm -f /etc/subuid /etc/subgid
echo '$test_user ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/container-test

log=/home/$test_user/.local/state/dev-setup/install.log
su - $test_user -c 'cd /opt/dev-setup && ./install.sh $work_flag --only $steps'
first=\$?
echo
echo '=== second run (must change nothing) ==='
start=\$(wc -l <"\$log")
su - $test_user -c 'cd /opt/dev-setup && ./install.sh $work_flag --only $steps'
second=\$?
changes=\$(tail -n +"\$((start + 1))" "\$log" | grep -F '[RUN]' | grep -v 'apt-get update' || true)
if [[ -n "\$changes" ]]; then
  echo "Second run made changes:"
  printf '  %s\n' "\$changes"
  second=1
fi
cp "\$log" /logs/install-$stamp.log
chown $owner /logs/install-$stamp.log
echo "first run exit: \$first, second run exit: \$second"
exit \$(( first || second ))
EOF

set +e
"$engine" run --rm -t -v "$repo:/opt/dev-setup:ro" -v "$log_dir:/logs" ubuntu:26.04 bash "/logs/inner-$stamp.sh" \
  2>&1 | tee "$log_dir/console-$stamp.out"
status=${PIPESTATUS[0]}
set -e

rm -f "$inner"
chown "$owner" "$log_dir/console-$stamp.out" 2>/dev/null || true
echo "Saved: $log_dir/console-$stamp.out and $log_dir/install-$stamp.log (exit $status)"
exit "$status"
