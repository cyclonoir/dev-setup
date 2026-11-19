#!/usr/bin/env bash
# Step: the desktop theme. Noctalia's palette already covers the bar, launcher, notifications, lock
# screen and greeter; its templates carry it to other apps (foot, Hyprland borders, GTK, btop, tmux,
# Claude Code). The managed config picks the palette and templates. Noctalia renders and updates the
# template files itself and adds each app's include line, but only to a config that already exists,
# so this step creates the missing ones (and leaves them alone after that).
# Neovim gets a real colorscheme per palette instead, Omarchy-style: a Noctalia hook records the
# palette, and a lazy.nvim spec (files/nvim/noctalia-theme.lua, where the mapping lives) applies it.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Install SRC at DEST only if nothing is there: after that the file belongs to you and Noctalia.
# Usage: seed_file SRC DEST
seed_file() {
  if [[ -e "$2" || -L "$2" ]]; then
    ok "exists: $2"
  else
    install_file "$1" "$2" 0644
  fi
}

# Quoted, comma-separated TOML strings: a b → "a", "b"
toml_strings() {
  local out="" s
  for s in "$@"; do out+="${out:+, }\"$s\""; done
  printf '%s' "$out"
}

# Created before the managed config, so Noctalia finds them when it applies the templates.
seed_file "$FILES_DIR/foot/foot.ini" "$FOOT_CONF"
seed_file "$FILES_DIR/btop/btop.conf" "$BTOP_CONF"
tmux_conf=$(tmux_conf_file)
seed_file "$FILES_DIR/tmux/tmux.conf" "$tmux_conf"

# Neovim: the hook's helper always; the spec only into an existing lazy.nvim config (creating
# ~/.config/nvim here would make `git clone <your config> ~/.config/nvim` fail).
install_file "$FILES_DIR/bin/dev-theme-sync" "$THEME_HELPER" 0755
if [[ -d "$NVIM_PLUGINS_DIR" ]]; then
  install_file "$FILES_DIR/nvim/noctalia-theme.lua" "$NVIM_THEME_SPEC" 0644
  if leftovers=$(omarchy_nvim_leftovers); then
    notice "Neovim: delete Omarchy's theme files from $NVIM_PLUGINS_DIR (${leftovers//$'\n'/, }); noctalia-theme.lua replaces them, and theme.lua points at a file that only exists on Omarchy."
  fi
else
  notice "Neovim won't follow the palette yet: it needs a lazy.nvim config with a lua/plugins folder in ~/.config/nvim (LazyVim's starter has one). Set that up, then run: ./install.sh --only theme"
fi

builtin_ids=$(toml_strings "${NOCTALIA_BUILTIN_TEMPLATES[@]}")
community_ids=$(toml_strings "${NOCTALIA_COMMUNITY_TEMPLATES[@]}")
before=$CHANGED
install_template "$FILES_DIR/noctalia/dev-setup.toml" "$NOCTALIA_MANAGED_CONF" 0644 "" \
  "PALETTE=$NOCTALIA_PALETTE" "BUILTIN_IDS=$builtin_ids" "COMMUNITY_IDS=$community_ids" \
  "THEME_HELPER=$THEME_HELPER"
conf_changed=$((CHANGED > before))

if have noctalia && ! is_dry_run; then
  noctalia_config_clean "$NOCTALIA_MANAGED_CONF" \
    || die "Noctalia doesn't accept everything in $NOCTALIA_MANAGED_CONF (see above); check the theme settings in lib/common.sh."
  ok "Noctalia accepts $NOCTALIA_MANAGED_CONF"
fi

# A running Noctalia reloads its config on its own, but its hooks only fire on the next palette
# change: re-render the templates (picking up newly created configs) and record the palette now.
if ((CHANGED)) && pgrep -x noctalia >/dev/null 2>&1; then
  run sh -c 'noctalia msg templates-apply >/dev/null' || true
  run "$THEME_HELPER" || true
fi

if ((conf_changed)); then
  notice "Claude Code: once Noctalia has run, choose Noctalia in /theme (one time; it follows the palette after that)."
fi
