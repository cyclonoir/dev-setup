#!/usr/bin/env bash
# Step (optional, run with --with umbriel): Umbriel as an extra login session to trial. Hyprland stays.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if [[ ! -f "$NOCTALIA_SOURCES_FILE" ]] && ! is_dry_run; then
  die "Noctalia repo not configured. Run: ./install.sh --only noctalia"
fi

apt_install umbriel
if ((CHANGED)); then
  notice "Umbriel is installed as an extra session. Check screen sharing works before using it for real work (it relies on xdg-desktop-portal-umbriel)."
fi
