#!/usr/bin/env bash
# Step: check the machine can run the setup before changing anything: not root, Ubuntu 26.04, network.
# Work-machine compliance checks live in the opt-in compliance step (--with compliance).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

require_not_root
require_ubuntu

if [[ "$(id -un)" != "$DEV_USER" ]]; then
  warn "Running as $(id -un), but DEV_USER is set to $DEV_USER."
fi
ok "setting up for user: $DEV_USER"

info "Checking network access to package sources"
for url in "https://archive.ubuntu.com/ubuntu/" "$NOCTALIA_SOURCES_URL" "https://mise.run"; do
  if curl -fsSL --max-time 15 -o /dev/null "$url"; then
    ok "reachable: $url"
  else
    die "Can't reach $url. Check the network or VPN and try again."
  fi
done
