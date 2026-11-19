#!/usr/bin/env bash
# Check the machine against the setup guide's checklist. Read-only.
# Exit code is non-zero if any required check fails; "!!" items are warnings.
# Usage: ./verify.sh [--work]   (--work adds Edge and IT's work-machine baseline checks)

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
not() { ! "$@"; }   # for checks that pass when a command fails

WORK_MACHINE=0   # only --work sets it, as in install.sh
case "${1:-}" in
  --work) WORK_MACHINE=1 ;;
  "") ;;
  *) echo "Usage: ./verify.sh [--work]" >&2; exit 2 ;;
esac

section "Packages"
for p in "${PKGS_BASE[@]}" "${PKGS_SHELL[@]}" "${PKGS_HYPRLAND[@]}" "${PKGS_BROWSERS[@]}" "${PKGS_NOCTALIA[@]}" "${PKGS_PODMAN[@]}" "${PKGS_VIRT[@]}" "${PKGS_GREETD[@]}"; do
  check fail "installed: $p" pkg_installed "$p"
done
if [[ "$WORK_MACHINE" == 1 ]]; then
  for p in "${PKGS_WORK_BROWSERS[@]}"; do
    check fail "installed: $p (work laptop)" pkg_installed "$p"
  done
fi
check fail ".NET pinned away from packages.microsoft.com" test -f /etc/apt/preferences.d/dotnet-ubuntu-only

section "Fonts"
for family in "${NERD_FONTS[@]}"; do
  check fail "font installed: $family" font_installed "$family"
done
check fail "monospace resolves to JetBrainsMono Nerd Font" bash -c 'fc-match monospace | grep -qF "JetBrainsMono Nerd Font"'

section "Hyprland + Noctalia"
check fail "managed config exists: $HYPR_MANAGED_CONF" test -f "$HYPR_MANAGED_CONF"
check fail "hyprland.conf sources the managed config" grep -qxF "source = $HYPR_MANAGED_CONF" "$HYPR_DIR/hyprland.conf"
check fail "noctalia command available" have noctalia
check fail "power button left to the desktop (logind HandlePowerKey=ignore)" grep -qx 'HandlePowerKey=ignore' "$LOGIND_POWER_KEY_CONF"
for helper in "${HYPR_HELPERS[@]}"; do
  check fail "helper installed: $helper" test -x "$HOME/.local/bin/$helper"
done
check warn "hyprland.conf has no bind lines of its own (dev-setup.conf defines the whole keymap)" not grep -qE "$HYPR_BIND_PATTERN" "$HYPR_DIR/hyprland.conf"

section "Theme (Noctalia palette and app templates)"
check fail "managed config exists: $NOCTALIA_MANAGED_CONF" test -f "$NOCTALIA_MANAGED_CONF"
check fail "Noctalia accepts the managed config without warnings" noctalia_config_clean "$NOCTALIA_MANAGED_CONF"
for f in "$FOOT_CONF" "$BTOP_CONF" "$(tmux_conf_file)"; do
  check fail "config exists for its template: $f" test -f "$f"
done
# Written by Noctalia when it applies the templates (at its first start), not by install.sh.
later="(Noctalia writes this when it runs)"
check warn "foot.ini includes the theme $later" grep -q 'include.*noctalia' "$FOOT_CONF"
check warn "hyprland.conf sources the border colors $later" grep -qE 'source[[:space:]]*=.*noctalia\.conf' "$HYPR_DIR/hyprland.conf"
check warn "GTK 4 apps import the colors $later" grep -qF noctalia.css "$HOME/.config/gtk-4.0/gtk.css"
check warn "btop theme rendered $later" test -f "$HOME/.config/btop/themes/noctalia.theme"
check warn "tmux config sources the theme $later" grep -qF tmux/themes/noctalia.conf "$(tmux_conf_file)"
check warn "Claude Code theme rendered $later" test -f "$HOME/.claude/themes/noctalia.json"
check fail "helper installed: ${THEME_HELPER##*/}" test -x "$THEME_HELPER"
check warn "palette recorded for Neovim $later" test -s "$PALETTE_STATE_FILE"
check warn "Neovim follows the palette (needs a lazy.nvim config, then ./install.sh --only theme)" test -f "$NVIM_THEME_SPEC"
check warn "no Omarchy theme files left in $NVIM_PLUGINS_DIR" not omarchy_nvim_leftovers

section "mise"
check fail "mise installed" test -x "$MISE"
for tool in "${MISE_TOOLS[@]%%@*}"; do
  check fail "mise provides $tool" "$MISE" where "$tool"   # tool names, not commands (neovim, not nvim)
done
check fail "bash activates mise" grep -qF "mise activate bash" "$HOME/.bashrc"

section "Shell"
check fail "fish starts mise and starship: $FISH_DROPIN" test -f "$FISH_DROPIN"
check fail "bat link exists" test -x "$HOME/.local/bin/bat"
check fail "login shell is $LOGIN_SHELL (else ./install.sh --only shell)" test "$(login_shell)" = "$LOGIN_SHELL"

section "Dotfiles"
check fail "chezmoi source: $DOTFILES_SOURCE" test -d "$DOTFILES_SOURCE/.git"
check fail "age key present (written by the first apply)" test -f "$AGE_KEY"
check fail "dotfiles origin is $DOTFILES_REPO_SSH" test "$(git -C "$DOTFILES_SOURCE" remote get-url origin 2>/dev/null)" = "$DOTFILES_REPO_SSH"
check fail "personal SSH key is private (600)" test "$(stat -c %a "$HOME/.ssh/id_github_personal" 2>/dev/null)" = 600
check warn "no local changes chezmoi would overwrite (chezmoi status is empty)" \
  test -z "$("$MISE" exec -- chezmoi status 2>&1)"

section "Podman (rootless)"
check fail "/etc/subuid range for $DEV_USER" subid_has_range /etc/subuid
check fail "/etc/subgid range for $DEV_USER" subid_has_range /etc/subgid
# shellcheck disable=SC2016  # expanded by the inner bash
check fail "podman runs rootless" bash -c '[[ "$(podman info --format "{{.Host.Security.Rootless}}")" == true ]]'

section "Virtualization"
check fail "KVM acceleration available (else turn on AMD-V/SVM in the BIOS)" kvm-ok
check fail "$DEV_USER in libvirt group" user_in_group "$DEV_USER" libvirt
check fail "$DEV_USER in kvm group" user_in_group "$DEV_USER" kvm

section "Login screen"
check fail "greetd reads $GREETD_CONF (noctalia-greeter's drop-in)" \
  bash -c "systemctl cat greetd.service | grep -F -- '--config $GREETD_CONF' >/dev/null"
check fail "greetd starts noctalia-greeter" grep -q noctalia-greeter-session "$GREETD_CONF"
check fail "greeter pre-fills $DEV_USER" grep -qF "default = \"$DEV_USER\"" "$GREETER_CONF"
check warn "greeter lists the $GREETER_SESSION session (else fix GREETER_SESSION in lib/common.sh)" \
  bash -c "noctalia-greeter sessions 2>/dev/null | grep -qF '$GREETER_SESSION'"
check fail "greetd PAM unlocks the keyring at login" grep -qE "$KEYRING_AUTH_PATTERN" "$GREETD_PAM"
check fail "greetd PAM starts the keyring" grep -qE "$KEYRING_SESSION_PATTERN" "$GREETD_PAM"
check warn "greetd is the active login screen (switch with --switch-dm)" test "$(active_display_manager)" = greetd.service

# Only on machines where the fingerprint step ran, i.e. sudo has the pam_fprintd line it adds.
# (Not "libpam-fprintd is installed": stock Ubuntu desktop pulls that package in on its own.)
if grep -qsE "$FPRINT_PAM_PATTERN" /etc/pam.d/sudo; then
  section "Fingerprint"
  check warn "admin prompts (polkit) accept fingerprints" grep -qsE "$FPRINT_PAM_PATTERN" /etc/pam.d/polkit-1
  check fail "fingerprint kept out of the shared login stack (common-auth)" not grep -qsE "$FPRINT_PAM_PATTERN" /etc/pam.d/common-auth
  check warn "a finger is enrolled for $DEV_USER" bash -c "fprintd-list '$DEV_USER' 2>/dev/null | grep -qE '$FPRINT_ENROLLED_PATTERN'"
fi

if [[ "$WORK_MACHINE" == 1 ]]; then
  section "IT baseline (managed by IT)"
  check_it_baseline
fi

section "Check these by hand"
cat <<'EOF'
  - Noctalia Greeter accepts your username; Hyprland starts with the Noctalia bar
  - Power button opens the session menu (after a reboot)
  - Launcher, control center, volume and brightness keys work (keymap: ~/.config/hypr/dev-setup.conf)
  - foot, tmux, btop, Nautilus, Neovim and window borders follow Noctalia's palette
  - Claude Code uses the Noctalia theme (choose it once in /theme)
  - An admin password prompt appears for a privileged action (polkit)
  - Saved passwords persist across logins (keyring)
  - Browser screen sharing works in a test video call
  - Windows VM has network and is reachable over RDP
  - With --with fingerprint: a finger unlocks the lock screen and approves sudo
  - ssh -T git@personal.github.com greets your personal GitHub account
EOF
if [[ "$WORK_MACHINE" == 1 ]]; then
  cat <<'EOF'
  - FortiClient VPN connects from the Hyprland session
  - Intune app still shows Compliant
  - ssh -T git@work.github.com greets your work GitHub account; ssh -T git@ssh.dev.azure.com authenticates
EOF
fi

printf '\n%d passed, %d warnings, %d failed\n' "$CHECK_PASS" "$CHECK_WARN" "$CHECK_FAIL"
((CHECK_FAIL == 0))
