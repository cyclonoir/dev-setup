#!/usr/bin/env bash
# Check the machine against the setup guide's checklist. Read-only.
# Exit code is non-zero if any required check fails; "!!" items are warnings.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

section() { printf '\n\033[1m%s\033[0m\n' "$*"; }

section "Packages"
for p in "${PKGS_BASE[@]}" "${PKGS_HYPRLAND[@]}" "${PKGS_BROWSERS[@]}" "${PKGS_NOCTALIA[@]}" "${PKGS_PODMAN[@]}" "${PKGS_VIRT[@]}" "${PKGS_GREETD[@]}"; do
  check fail "installed: $p" pkg_installed "$p"
done
check fail ".NET pinned away from packages.microsoft.com" test -f /etc/apt/preferences.d/dotnet-ubuntu-only

section "Fonts"
for family in "${NERD_FONTS[@]}"; do
  check fail "font installed: $family" bash -c "fc-list : family | grep -qF \"$family\""
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
check warn "hyprland.conf has no bind lines of its own" bash -c "! grep -qE '^[[:space:]]*bind[a-z]*[[:space:]]*=' \"$HYPR_DIR/hyprland.conf\""

section "mise"
check fail "mise installed" test -x "$MISE"
for tool in nvim node go dotnet; do
  check fail "mise provides $tool" "$MISE" which "$tool"
done
check fail "bash activates mise" grep -qF "mise activate bash" "$HOME/.bashrc"

section "Podman (rootless)"
check fail "/etc/subuid range for $DEV_USER" grep -q "^${DEV_USER}:" /etc/subuid
check fail "/etc/subgid range for $DEV_USER" grep -q "^${DEV_USER}:" /etc/subgid
# shellcheck disable=SC2016  # expanded by the inner bash
check fail "podman runs rootless" bash -c '[[ "$(podman info --format "{{.Host.Security.Rootless}}")" == true ]]'

section "Virtualization"
check fail "KVM acceleration available" kvm-ok
check fail "$DEV_USER in libvirt group" user_in_group "$DEV_USER" libvirt
check fail "$DEV_USER in kvm group" user_in_group "$DEV_USER" kvm

section "Login screen"
check fail "greetd starts noctalia-greeter" grep -q noctalia-greeter-session "$GREETD_CONF"
check fail "greeter pre-fills $DEV_USER" grep -qF "default = \"$DEV_USER\"" "$GREETER_CONF"
check fail "greetd PAM unlocks the keyring at login" grep -qE '^auth[[:space:]].*pam_gnome_keyring\.so' "$GREETD_PAM"
check fail "greetd PAM starts the keyring" grep -qE '^session[[:space:]].*pam_gnome_keyring\.so' "$GREETD_PAM"
check warn "greetd is the active login screen (switch with --switch-dm)" systemctl is-enabled --quiet greetd

section "IT baseline (managed by IT)"
check warn "Disk encrypted (LUKS)" bash -c 'lsblk -rno FSTYPE | grep -qx crypto_LUKS'
check warn "Domain joined" bash -c 'realm list --name-only | grep -q .'
check warn "Sophos running" systemctl is-active --quiet sophos-spl
check warn "FortiClient installed" pkg_installed forticlient
check warn "Intune app installed" pkg_installed intune-portal

section "Check these by hand"
cat <<'EOF'
  - Noctalia Greeter accepts your AD short name; Hyprland starts with the Noctalia bar
  - Power button opens the session menu (after a reboot)
  - Launcher, control center, volume and brightness keys work (keymap: ~/.config/hypr/dev-setup.conf)
  - An admin password prompt appears for a privileged action (polkit)
  - Saved passwords persist across logins (keyring)
  - Browser screen sharing works in a test Teams/Zoom call
  - FortiClient VPN connects from the Hyprland session
  - Intune app still shows Compliant
  - Windows VM has network and is reachable over RDP
EOF

printf '\n%d passed, %d warnings, %d failed\n' "$CHECK_PASS" "$CHECK_WARN" "$CHECK_FAIL"
((CHECK_FAIL == 0))
