#!/usr/bin/env bash
# Step: rootless Podman. useradd gives local users /etc/subuid and /etc/subgid ranges, but AD (SSSD)
# users are never created with useradd, so they have none. usermod can add them for an AD user (it looks
# the user up through SSSD), using a range that starts after every range already handed out.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install "${PKGS_PODMAN[@]}"

subid_range_size=65536

if subid_has_range /etc/subuid && subid_has_range /etc/subgid; then
  ok "subuid/subgid ranges exist for $DEV_USER"
else
  # usermod refuses to add ranges to a file that doesn't exist (possible on an AD-only machine).
  for f in /etc/subuid /etc/subgid; do
    [[ -e "$f" ]] || sudo_run install -m 0644 /dev/null "$f"
  done
  # Start after the highest range in either file (minimum 100000) so no two users' ranges overlap.
  first=$({ cat /etc/subuid /etc/subgid 2>/dev/null || true; } \
    | awk -F: 'BEGIN { m = 100000 } NF >= 3 { e = $2 + $3; if (e > m) m = e } END { print m }')
  last=$((first + subid_range_size - 1))
  args=()
  subid_has_range /etc/subuid || args+=(--add-subuids "$first-$last")
  subid_has_range /etc/subgid || args+=(--add-subgids "$first-$last")
  backup_file /etc/subuid sudo
  backup_file /etc/subgid sudo
  sudo_run usermod "${args[@]}" "$DEV_USER"
  ok "added subuid/subgid range $first-$last for $DEV_USER"
  run podman system migrate || warn "podman system migrate failed; it runs again on next login."
  notice "Log out and back in, then check rootless Podman: podman run --rm docker.io/library/hello-world"
fi
