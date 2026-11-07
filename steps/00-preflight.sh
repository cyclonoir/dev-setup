#!/usr/bin/env bash
# Step: check this is Ubuntu 26.04 and install curl if it's missing. With --work, also check IT's
# compliance baseline (read-only: missing items only warn, and nothing here ever changes them).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

require_ubuntu

ok "setting up for user: $DEV_USER"

# Stock Ubuntu desktop ships wget but not curl, which later steps need.
have curl || apt_install curl ca-certificates

if [[ "$WORK_MACHINE" == 1 ]]; then
  info "Checking IT compliance baseline (read-only; missing items are IT's part)"
  check_it_baseline
fi
