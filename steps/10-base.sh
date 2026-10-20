#!/usr/bin/env bash
# Step: base build tools, plus the apt pin that keeps Microsoft's .NET packages out (mise provides .NET).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_update
apt_install "${PKGS_BASE[@]}"

# Ubuntu names the fd binary fdfind; give it its usual name.
if [[ -e "$HOME/.local/bin/fd" ]]; then
  ok "fd link exists"
else
  run mkdir -p "$HOME/.local/bin"
  run ln -s /usr/bin/fdfind "$HOME/.local/bin/fd"
fi

# The Intune app adds packages.microsoft.com, whose .NET packages conflict with Ubuntu's.
install_file "$FILES_DIR/apt/dotnet-ubuntu-only.pref" /etc/apt/preferences.d/dotnet-ubuntu-only 0644 sudo
