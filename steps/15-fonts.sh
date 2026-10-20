#!/usr/bin/env bash
# Step: Nerd Fonts for icons in TUIs (Neovim, btop, eza, prompts). Ubuntu doesn't package them, so they
# come from the nerd-fonts GitHub releases into ~/.local/share/fonts. A fontconfig rule makes
# JetBrainsMono Nerd Font the default "monospace" (foot's default font), with Symbols Nerd Font as an
# icon fallback for apps that use other fonts.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install fontconfig xz-utils

# grep without -q: an early exit would SIGPIPE fc-list, which pipefail reports as "not found".
font_installed() { fc-list : family 2>/dev/null | grep -F "$1" >/dev/null; }

fonts_added=0
for archive in "${!NERD_FONTS[@]}"; do
  family=${NERD_FONTS[$archive]}
  if font_installed "$family"; then
    ok "font installed: $family"
    continue
  fi
  dest="$FONTS_DIR/$archive"
  info "Installing $family"
  run mkdir -p "$dest"
  run sh -c "curl -fsSL '$NERD_FONTS_URL/$archive.tar.xz' | tar -xJ -C '$dest'"
  fonts_added=1
done

install_file "$FILES_DIR/fontconfig/50-dev-setup-monospace.conf" \
  "$HOME/.config/fontconfig/conf.d/50-dev-setup-monospace.conf" 0644

if ((fonts_added)); then
  run fc-cache -f "$FONTS_DIR"
fi
notice "Restart open terminals to pick up JetBrainsMono Nerd Font. To update the fonts later, delete their folders in $FONTS_DIR and re-run: ./install.sh --only fonts"
