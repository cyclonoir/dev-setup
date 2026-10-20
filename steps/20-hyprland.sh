#!/usr/bin/env bash
# Step: Hyprland session (Ubuntu's 0.53 package) and the pieces a session needs.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install "${PKGS_HYPRLAND[@]}"
