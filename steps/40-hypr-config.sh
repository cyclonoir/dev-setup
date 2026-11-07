#!/usr/bin/env bash
# Step: Hyprland keymap (ported from Omarchy) and Noctalia wiring. dev-setup.conf owns the whole keymap;
# hyprland.conf is created from Hyprland's default without its keybinds and only gets one `source =`
# line, so personal edits there are never overwritten (verify.sh warns if it has bind lines of its own).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

main_conf="$HYPR_DIR/hyprland.conf"
example_conf="/usr/share/hypr/hyprland.conf"

if [[ ! -f "$main_conf" ]]; then
  [[ -f "$example_conf" ]] || is_dry_run \
    || die "Hyprland isn't installed ($example_conf is missing). Run: ./install.sh --only hyprland"
  info "No hyprland.conf yet; starting from Hyprland's default config without its keybinds"
  run mkdir -p "$HYPR_DIR"
  run sh -c "grep -vE '$HYPR_BIND_PATTERN' '$example_conf' > '$main_conf'"
fi

install_template "$FILES_DIR/hypr/dev-setup.conf" "$HYPR_MANAGED_CONF" 0644 "" \
  "HOME=$HOME" "TERMINAL=$TERMINAL_PKG"
ensure_line "$main_conf" "source = $HYPR_MANAGED_CONF"
hypr_changed=$CHANGED   # the keymap or its source line changed (helpers below don't need a reload)

for helper in "${HYPR_HELPERS[@]}"; do
  install_file "$FILES_DIR/bin/$helper" "$HOME/.local/bin/$helper" 0755
done

# The power button opens Noctalia's session menu (bound above) instead of logind powering off.
# Not applied live: restarting logind would end every session, so it takes effect on the next reboot.
before=$CHANGED
install_file "$FILES_DIR/logind/10-dev-setup-power-key.conf" "$LOGIND_POWER_KEY_CONF" 0644 sudo
if ((CHANGED > before)); then
  notice "Reboot before relying on the power button: until then it still powers off immediately instead of opening the session menu."
fi

if ((hypr_changed)); then
  if pgrep -x Hyprland >/dev/null 2>&1; then
    # The redirect sits inside sh -c so a dry run still prints the command.
    run sh -c 'hyprctl reload >/dev/null' || true
  fi
  notice "Log out and into the Hyprland session so the autostart lines (Noctalia, polkit agent) take effect."
fi
