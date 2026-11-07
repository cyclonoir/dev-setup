#!/usr/bin/env bash
# Step: Noctalia shell from the project's APT repo (also hosts noctalia-greeter and umbriel).
# The repo definition ships in files/ (copied from pkg.noctalia.dev) rather than being downloaded into
# /etc/apt, so the server can't change which URIs or keyring apt trusts.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if pkg_installed "$NOCTALIA_KEYRING_PKG"; then
  ok "Noctalia repo signing key installed"
else
  deb="$TMP_DIR/$NOCTALIA_KEYRING_PKG.deb"
  run curl -fsSL -o "$deb" "$NOCTALIA_KEYRING_URL"
  # It runs maintainer scripts as root: make sure it's the keyring package before installing it.
  if ! is_dry_run && [[ "$(dpkg-deb -f "$deb" Package 2>/dev/null)" != "$NOCTALIA_KEYRING_PKG" ]]; then
    die "$NOCTALIA_KEYRING_URL didn't download the $NOCTALIA_KEYRING_PKG package; nothing was installed."
  fi
  sudo_run apt-get install -y "$deb"
fi

install_template "$FILES_DIR/apt/noctalia.sources" "$NOCTALIA_SOURCES_FILE" 0644 sudo "CODENAME=$UBUNTU_CODENAME"
# On a first run noctalia has no install candidate yet, so apt_install refreshes the lists itself.
apt_install "${PKGS_NOCTALIA[@]}"
