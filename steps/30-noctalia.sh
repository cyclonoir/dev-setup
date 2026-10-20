#!/usr/bin/env bash
# Step: Noctalia shell from the project's APT repo (also hosts noctalia-greeter and umbriel).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if pkg_installed nickh-archive-keyring; then
  ok "Noctalia repo signing key installed"
else
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT
  run curl -fsSL -o "$tmp_dir/nickh-archive-keyring.deb" "$NOCTALIA_KEYRING_URL"
  sudo_run apt-get install -y "$tmp_dir/nickh-archive-keyring.deb"
fi

if [[ -f "$NOCTALIA_SOURCES_FILE" ]]; then
  ok "Noctalia repo configured: $NOCTALIA_SOURCES_FILE"
else
  sudo_run curl -fsSL -o "$NOCTALIA_SOURCES_FILE" "$NOCTALIA_SOURCES_URL"
  apt_update
fi

apt_install "${PKGS_NOCTALIA[@]}"
