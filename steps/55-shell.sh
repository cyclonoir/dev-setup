#!/usr/bin/env bash
# Step: fish with the starship prompt, as your login shell, plus the tools your fish config uses
# (zoxide, eza, bat, fzf, 7zip; atuin and vivid come from the mise step). A managed conf.d file starts mise and starship in fish;
# ~/.config/fish/config.fish stays yours.
# A local account gets fish through chsh. An AD (SSSD) account isn't in /etc/passwd, so chsh can't
# change it: sss_override sets the shell in SSSD's view of the account, on this machine only. SSSD
# keeps that in its cache, so deleting the cache drops it (re-run this step), and IT's override_shell
# in /etc/sssd/sssd.conf, if set, wins over it.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install "${PKGS_SHELL[@]}"

# Ubuntu names the bat binary batcat; give it its usual name.
if [[ -e "$HOME/.local/bin/bat" ]]; then
  ok "bat link exists"
else
  run mkdir -p "$HOME/.local/bin"
  run ln -s /usr/bin/batcat "$HOME/.local/bin/bat"
fi

install_template "$FILES_DIR/fish/dev-setup.fish" "$FISH_DROPIN" 0644 "" "MISE=$MISE"

if [[ "$(login_shell)" == "$LOGIN_SHELL" ]]; then
  ok "login shell: $LOGIN_SHELL"
elif awk -F: -v u="$DEV_USER" '$1 == u { f = 1 } END { exit !f }' /etc/passwd; then
  backup_file /etc/passwd sudo
  sudo_run chsh -s "$LOGIN_SHELL" "$DEV_USER"
  notice "Log out and back in to use fish as your login shell."
else
  apt_install "${PKGS_SHELL_AD[@]}"
  # user-add replaces the account's whole override (home, uid and so on), so only add one where there
  # is none. user-show prints the override as one passwd-style line, or nothing.
  read_prefix sudo
  override=$("${READ_PREFIX[@]}" sss_override user-show "$DEV_USER" 2>/dev/null || true)
  if [[ -n "$override" && "$(cut -d: -f7 <<<"$override")" != "$LOGIN_SHELL" ]]; then
    warn "$DEV_USER already has an SSSD override, which sss_override user-add would replace: $override. To keep it and change the shell, save that line with $LOGIN_SHELL as its 7th field to a file, run sudo sss_override user-import FILE, then sudo systemctl restart sssd."
  else
    if [[ -z "$override" ]]; then
      sudo_run sss_override user-add "$DEV_USER" --shell "$LOGIN_SHELL"
      sudo_run systemctl restart sssd   # overrides take effect when SSSD restarts
    fi
    if is_dry_run || [[ "$(login_shell)" == "$LOGIN_SHELL" ]]; then
      notice "Log out and back in to use fish as your login shell. SSSD keeps this setting in its cache: if the cache is ever deleted, run ./install.sh --only shell again."
    else
      warn "SSSD still reports $(login_shell) as your login shell. If sudo systemctl restart sssd doesn't change that, IT's override_shell in /etc/sssd/sssd.conf wins over sss_override."
    fi
  fi
fi
