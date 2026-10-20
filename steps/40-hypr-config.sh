#!/usr/bin/env bash
# Step: Hyprland keymap (ported from Omarchy) and Noctalia wiring. dev-setup.conf owns the whole keymap;
# hyprland.conf is created from Hyprland's default without its keybinds and only gets one `source =`
# line, so personal edits there are never overwritten.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

main_conf="$HYPR_DIR/hyprland.conf"
example_conf="/usr/share/hypr/hyprland.conf"
bind_pattern='^[[:space:]]*bind[a-z]*[[:space:]]*='

if [[ ! -f "$main_conf" ]]; then
  if [[ -f "$example_conf" ]] || is_dry_run; then
    info "No hyprland.conf yet; starting from Hyprland's default config without its keybinds"
    run mkdir -p "$HYPR_DIR"
    run sh -c "grep -vE '$bind_pattern' '$example_conf' > '$main_conf'"
  else
    warn "No $main_conf and no default at $example_conf."
    notice "Log into a Hyprland session once so it generates hyprland.conf, then run: ./install.sh --only hypr-config"
    exit 0
  fi
elif grep -qE "$bind_pattern" "$main_conf"; then
  warn "$main_conf has its own bind lines; they fire alongside dev-setup's keymap."
  notice "Remove the keybinding lines from $main_conf (dev-setup.conf defines the whole keymap), then: hyprctl reload"
fi

install_template "$FILES_DIR/hypr/dev-setup.conf" "$HYPR_MANAGED_CONF" 0644 "" \
  "HOME=$HOME" "TERMINAL=$TERMINAL_PKG"
ensure_line "$main_conf" "source = $HYPR_MANAGED_CONF"

for helper in "${HYPR_HELPERS[@]}"; do
  install_file "$FILES_DIR/bin/$helper" "$HOME/.local/bin/$helper" 0755
done

# The power button opens Noctalia's session menu (bound above) instead of logind powering off.
# Not applied live: restarting logind would end every session, so it takes effect on the next reboot.
if ! [[ -f "$LOGIND_POWER_KEY_CONF" ]] || ! cmp -s "$FILES_DIR/logind/10-dev-setup-power-key.conf" "$LOGIND_POWER_KEY_CONF"; then
  install_file "$FILES_DIR/logind/10-dev-setup-power-key.conf" "$LOGIND_POWER_KEY_CONF" 0644 sudo
  notice "Reboot before relying on the power button: until then it still powers off immediately instead of opening the session menu."
else
  ok "unchanged: $LOGIND_POWER_KEY_CONF"
fi

if pgrep -x Hyprland >/dev/null 2>&1; then
  run hyprctl reload >/dev/null || true
fi
notice "Log out and into the Hyprland session so the autostart lines (Noctalia, polkit agent) take effect."
