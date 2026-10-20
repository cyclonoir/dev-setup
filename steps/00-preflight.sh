#!/usr/bin/env bash
# Step: check the machine before changing anything. IT baseline items only warn; they're never modified.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

require_not_root
require_ubuntu

if [[ "$(id -un)" != "$DEV_USER" ]]; then
  warn "Running as $(id -un), but DEV_USER in lib/common.sh is $DEV_USER."
fi

info "Checking network access to package sources"
for url in "https://archive.ubuntu.com/ubuntu/" "$NOCTALIA_SOURCES_URL" "https://mise.run"; do
  if curl -fsSL --max-time 15 -o /dev/null "$url"; then
    ok "reachable: $url"
  else
    die "Can't reach $url. Check the network or VPN and try again."
  fi
done

info "Checking IT compliance baseline (read-only)"
check warn "Disk encrypted (LUKS)" bash -c 'lsblk -rno FSTYPE | grep -qx crypto_LUKS'
check warn "Domain joined (realm list)" bash -c 'realm list --name-only | grep -q .'
check warn "Sophos running (sophos-spl)" systemctl is-active --quiet sophos-spl
check warn "FortiClient installed" pkg_installed forticlient
check warn "Intune app installed" pkg_installed intune-portal
check warn "GNOME installed (fallback session)" pkg_installed gnome-shell

if ((CHECK_WARN > 0)); then
  warn "$CHECK_WARN baseline item(s) missing. That's IT's part of the setup; this script continues without them."
fi
