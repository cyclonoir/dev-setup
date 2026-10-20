#!/usr/bin/env bash
# Step: rootless Podman. AD (SSSD) users don't get /etc/subuid and /etc/subgid ranges automatically,
# and usermod can't add them, so this step appends a non-overlapping range itself.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install "${PKGS_PODMAN[@]}"

subid_range_size=65536
needs_migrate=0

if grep -qs "^${DEV_USER}:" /etc/subuid && grep -qs "^${DEV_USER}:" /etc/subgid; then
  ok "subuid/subgid ranges exist for $DEV_USER"
else
  # Start after the highest range already handed out in either file (minimum 100000).
  next=$(cat /etc/subuid /etc/subgid 2>/dev/null | awk -F: 'BEGIN { m = 100000 } NF >= 3 { e = $2 + $3; if (e > m) m = e } END { print m }')
  for f in /etc/subuid /etc/subgid; do
    if grep -qs "^${DEV_USER}:" "$f"; then
      ok "$f already has a range for $DEV_USER"
    else
      ensure_line "$f" "${DEV_USER}:${next}:${subid_range_size}" sudo
      needs_migrate=1
    fi
  done
fi

if ((needs_migrate)); then
  run podman system migrate || warn "podman system migrate failed; it runs again on next login."
  notice "Log out and back in, then check rootless Podman: podman run --rm docker.io/library/hello-world"
fi
