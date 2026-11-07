#!/usr/bin/env bash
# Step: Nerd Fonts for icons in TUIs (Neovim, btop, eza, prompts). Ubuntu doesn't package them, so they
# come from the nerd-fonts GitHub releases into ~/.local/share/fonts. A fontconfig rule makes
# JetBrainsMono Nerd Font the default "monospace" (foot's default font), with Symbols Nerd Font as an
# icon fallback for apps that use other fonts.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install fontconfig xz-utils

fonts_added=0
for archive in "${!NERD_FONTS[@]}"; do
  family=${NERD_FONTS[$archive]}
  if font_installed "$family"; then
    ok "font installed: $family"
    continue
  fi
  info "Installing $family"
  # Download and extract it aside (which fails on a damaged archive), then move it into place: an
  # interrupted download never leaves a half-installed family that later runs would count as installed.
  run curl -fsSL -o "$TMP_DIR/$archive.tar.xz" "$NERD_FONTS_URL/$archive.tar.xz"
  if ! is_dry_run; then
    mkdir -p "$TMP_DIR/$archive"
    tar -xJf "$TMP_DIR/$archive.tar.xz" -C "$TMP_DIR/$archive" || die "Downloaded $archive.tar.xz is damaged; re-run to retry."
  fi
  run mkdir -p "$FONTS_DIR"
  run rm -rf "${FONTS_DIR:?}/$archive"
  run mv "$TMP_DIR/$archive" "$FONTS_DIR/$archive"
  fonts_added=1
done

install_file "$FILES_DIR/fontconfig/50-dev-setup-monospace.conf" \
  "$HOME/.config/fontconfig/conf.d/50-dev-setup-monospace.conf" 0644

if ((fonts_added)); then
  run fc-cache -f "$FONTS_DIR"
fi
if ((CHANGED)); then
  notice "Restart open terminals to pick up JetBrainsMono Nerd Font. To update the fonts later, delete their folders in $FONTS_DIR and re-run: ./install.sh --only fonts"
fi
