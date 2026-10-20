#!/usr/bin/env bash
# Step: greetd + Noctalia Greeter as the login screen. Configures everything, but only switches away
# from GDM with --switch-dm, and never with --now (that would end the current session).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

dm_enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }

# Installing a display manager can change the default one. Remember the state to undo that.
gdm_was_enabled=0
dm_enabled gdm3 && gdm_was_enabled=1

apt_install "${PKGS_GREETD[@]}"

if ((gdm_was_enabled)) && [[ "$SWITCH_DM" != 1 ]] && ! is_dry_run && ! dm_enabled gdm3; then
  warn "Installing greetd changed the default display manager; restoring GDM (use --switch-dm to switch)."
  sudo_run systemctl disable greetd
  sudo_run systemctl enable gdm3
fi

# --- greetd: point it at the greeter ---
greeter_cmd=$(command -v noctalia-greeter-session || true)
if [[ -z "$greeter_cmd" ]]; then
  is_dry_run || die "noctalia-greeter-session not found after installing noctalia-greeter."
  greeter_cmd=/usr/bin/noctalia-greeter-session
fi

# Keep the greeter account and VT the package set up; fall back to known defaults.
greeter_user=""
vt=""
if [[ -f "$GREETD_CONF" ]]; then
  greeter_user=$(sed -nE 's/^[[:space:]]*user[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$GREETD_CONF" | head -n1)
  vt=$(sed -nE 's/^[[:space:]]*vt[[:space:]]*=[[:space:]]*([^[:space:]#]+).*/\1/p' "$GREETD_CONF" | head -n1)
fi
if [[ -z "$greeter_user" ]]; then
  for u in _greetd greeter; do
    if getent passwd "$u" >/dev/null; then greeter_user=$u; break; fi
  done
fi
if [[ -z "$greeter_user" ]]; then
  is_dry_run || die "No greeter account found (_greetd or greeter). Check the greetd package."
  greeter_user=_greetd
fi
vt=${vt:-1}

install_template "$FILES_DIR/greetd/config.toml" "$GREETD_CONF" 0644 sudo \
  "GREETER_CMD=$greeter_cmd" "GREETER_USER=$greeter_user" "VT=$vt"

# --- Greeter: pre-fill the AD user (SSSD users aren't listed) and the default session ---
if [[ -f "$GREETER_CONF" ]] && ! grep -qF "default = \"$DEV_USER\"" "$GREETER_CONF"; then
  warn "$GREETER_CONF already exists and doesn't pre-fill $DEV_USER. Not overwriting it."
  notice "Add to $GREETER_CONF: [user] default = \"$DEV_USER\" and [session] default = \"$GREETER_SESSION\""
else
  install_template "$FILES_DIR/noctalia-greeter/greeter.toml" "$GREETER_CONF" 0644 sudo \
    "DEV_USER=$DEV_USER" "SESSION=$GREETER_SESSION"
fi

if have noctalia-greeter && ! is_dry_run; then
  if noctalia-greeter sessions 2>/dev/null | grep -F "$GREETER_SESSION" >/dev/null; then
    ok "greeter lists the $GREETER_SESSION session"
  else
    warn "noctalia-greeter sessions doesn't list '$GREETER_SESSION'; fix GREETER_SESSION in lib/common.sh."
  fi
fi

# --- PAM: SSSD logins and gnome-keyring unlock ---
# Insert LINE after the ANCHOR line unless a pam_gnome_keyring line of the same TYPE exists.
pam_add_keyring() {
  local type=$1 anchor=$2 line=$3
  if grep -qE "^${type}[[:space:]].*pam_gnome_keyring\.so" "$GREETD_PAM"; then
    ok "$GREETD_PAM already unlocks the keyring ($type)"
    return 0
  fi
  if ! grep -qxF "$anchor" "$GREETD_PAM"; then
    warn "No '$anchor' line in $GREETD_PAM; add this manually: $line"
    return 0
  fi
  backup_file "$GREETD_PAM" sudo
  sudo_run sed -i "\|^${anchor}\$|a ${line}" "$GREETD_PAM"
}

if [[ -f "$GREETD_PAM" ]]; then
  for inc in common-auth common-account common-session; do
    grep -qxF "@include $inc" "$GREETD_PAM" || warn "$GREETD_PAM doesn't include $inc; AD (SSSD) logins may fail."
  done
  pam_add_keyring auth '@include common-auth' 'auth     optional  pam_gnome_keyring.so'
  pam_add_keyring session '@include common-session' 'session  optional  pam_gnome_keyring.so auto_start'
elif is_dry_run; then
  info "[dry-run] would add pam_gnome_keyring lines to $GREETD_PAM"
else
  warn "$GREETD_PAM not found; check the greetd package."
fi

# --- Share Noctalia's look with the greeter without an admin prompt each time ---
if have noctalia-greeter || is_dry_run; then
  sudo_run noctalia-greeter passwordless-sync enable "$DEV_USER"
fi
notice "In Noctalia: Settings > Security > Noctalia Greeter > Sync Now (optionally turn on Auto-Sync Greeter)."

# --- Switch display managers (opt-in) ---
if [[ "$SWITCH_DM" == 1 ]]; then
  if dm_enabled greetd; then
    ok "greetd is already the login screen"
  else
    if dm_enabled gdm3; then sudo_run systemctl disable gdm3; fi
    sudo_run systemctl enable greetd
    notice "Reboot to switch to Noctalia Greeter. Rollback: Ctrl+Alt+F3, log in, then: sudo systemctl disable greetd && sudo systemctl enable gdm3 && sudo reboot"
  fi
elif ! dm_enabled greetd; then
  notice "greetd is configured but GDM is still the login screen. To switch: ./install.sh --only greetd --switch-dm"
fi
