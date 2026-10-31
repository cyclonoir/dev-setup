#!/usr/bin/env bash
# Step (optional, run with --with compliance): on a work machine, check IT's compliance baseline
# (LUKS, AD join, Sophos, FortiClient, Intune, GNOME fallback). Read-only: missing items only warn,
# and nothing here is ever changed. Skip it on a personal machine.
# Selecting this step also marks the run as a work machine, so the browsers step installs Edge.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

info "Checking IT compliance baseline (read-only)"
check_it_baseline

if ((CHECK_WARN > 0)); then
  warn "$CHECK_WARN baseline item(s) missing. That's IT's part of the setup; this script continues without them."
else
  ok "IT baseline complete"
fi
