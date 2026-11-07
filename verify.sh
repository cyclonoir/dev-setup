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
for p in "${PKGS_BASE[@]}" "${PKGS_HYPRLAND[@]}" "${PKGS_BROWSERS[@]}" "${PKGS_NOCTALIA[@]}" "${PKGS_PODMAN[@]}" "${PKGS_VIRT[@]}" "${PKGS_GREETD[@]}"; do
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

section "mise"
check fail "mise installed" test -x "$MISE"
for tool in "${MISE_TOOLS[@]%%@*}"; do
  check fail "mise provides $tool" "$MISE" where "$tool"   # tool names, not commands (neovim, not nvim)
done
check fail "bash activates mise" grep -qF "mise activate bash" "$HOME/.bashrc"

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
  - An admin password prompt appears for a privileged action (polkit)
  - Saved passwords persist across logins (keyring)
  - Browser screen sharing works in a test video call
  - Windows VM has network and is reachable over RDP
  - With --with fingerprint: a finger unlocks the lock screen and approves sudo
EOF
if [[ "$WORK_MACHINE" == 1 ]]; then
  cat <<'EOF'
  - FortiClient VPN connects from the Hyprland session
  - Intune app still shows Compliant
EOF
fi

printf '\n%d passed, %d warnings, %d failed\n' "$CHECK_PASS" "$CHECK_WARN" "$CHECK_FAIL"
((CHECK_FAIL == 0))
