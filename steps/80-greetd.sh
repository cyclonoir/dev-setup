#!/usr/bin/env bash
# Step: greetd + Noctalia Greeter as the login screen. Configures everything, but only switches away
# from the current display manager with --switch-dm, effective on reboot: nothing here restarts the
# display manager (that would end the current session).
#
# "Which login screen starts" = where display-manager.service points (active_display_manager); a
# `systemctl is-enabled gdm3` check can't tell, because gdm3.service is an alias of gdm.service.
# Debian's display-manager packages also re-point that link to the one named in
# /etc/X11/default-display-manager whenever they're upgraded, so a switch updates that file too.
#
# greetd's config isn't written here: the noctalia-greeter package points greetd at a config of its
# own (GREETD_CONF), which already starts the greeter.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

greetd_unit="greetd.service"
sync_rules="/etc/polkit-1/rules.d/49-noctalia-greeter-sync.rules"

# Installing a display manager package can take over the login screen. Remember what was active.
dm_before=$(active_display_manager)
default_dm_before=$(cat "$DEFAULT_DM_FILE" 2>/dev/null || true)

apt_install "${PKGS_GREETD[@]}"

dm_now=$(active_display_manager)
if [[ "$SWITCH_DM" != 1 ]]; then
  if [[ -n "$dm_before" && "$dm_now" != "$dm_before" ]]; then
    warn "Installing greetd made ${dm_now:-nothing} the login screen; restoring $dm_before (use --switch-dm to switch)."
    sudo_run systemctl enable --force "$dm_before"
    dm_now=$dm_before
  fi
  if [[ -n "$default_dm_before" && "$(cat "$DEFAULT_DM_FILE" 2>/dev/null || true)" != "$default_dm_before" ]]; then
    install_content "$default_dm_before" "$DEFAULT_DM_FILE" 0644 sudo
  fi
fi

# --- Greeter: pre-fill the user (AD users aren't listed) and the default session ---
# Only ever created, never rewritten: once it exists it may hold other settings.
read_prefix sudo
if ! "${READ_PREFIX[@]}" test -e "$GREETER_CONF"; then
  install_template "$FILES_DIR/noctalia-greeter/greeter.toml" "$GREETER_CONF" 0644 sudo \
    "DEV_USER=$DEV_USER" "SESSION=$GREETER_SESSION"
elif "${READ_PREFIX[@]}" grep -qF "default = \"$DEV_USER\"" "$GREETER_CONF"; then
  ok "$GREETER_CONF pre-fills $DEV_USER"
else
  warn "$GREETER_CONF exists but doesn't pre-fill $DEV_USER; leaving it as is."
  notice "Add to $GREETER_CONF: [user] default = \"$DEV_USER\" and [session] default = \"$GREETER_SESSION\""
fi

# --- PAM: SSSD logins and gnome-keyring unlock ---
if [[ -f "$GREETD_PAM" ]]; then
  # Debian's greetd file has "@include login", which pulls in the common-* stack.
  for inc in common-auth common-account common-session; do
    grep -qxE "@include ($inc|login)" "$GREETD_PAM" || warn "$GREETD_PAM doesn't include $inc; AD (SSSD) logins may fail."
  done
  pam_insert "$GREETD_PAM" "$KEYRING_AUTH_PATTERN" after '@include common-auth' \
    'auth     optional  pam_gnome_keyring.so'
  pam_insert "$GREETD_PAM" "$KEYRING_SESSION_PATTERN" after '@include common-session' \
    'session  optional  pam_gnome_keyring.so auto_start'
elif is_dry_run; then
  info "[dry-run] would add pam_gnome_keyring lines to $GREETD_PAM"
else
  warn "$GREETD_PAM not found; check the greetd package."
fi

# --- Share Noctalia's look with the greeter without an admin prompt each time ---
read_prefix sudo
if "${READ_PREFIX[@]}" grep -qsF -- "$DEV_USER" "$sync_rules"; then
  ok "passwordless greeter sync enabled for $DEV_USER"
else
  sudo_run noctalia-greeter passwordless-sync enable "$DEV_USER"
fi

# --- Switch display managers (opt-in) ---
if [[ "$SWITCH_DM" == 1 ]]; then
  if [[ "$dm_now" == "$greetd_unit" ]]; then
    ok "greetd is already the login screen"
  else
    previous_dm=${dm_now:-gdm.service}
    rollback="sudo systemctl enable --force $previous_dm"
    if [[ -n "$default_dm_before" ]]; then
      rollback+=" && echo $default_dm_before | sudo tee $DEFAULT_DM_FILE"
    fi
    # --force replaces the display-manager.service link in one go, before anything is turned off,
    # so a failure here never leaves the machine without a login screen.
    sudo_run systemctl enable --force "$greetd_unit"
    notice "Reboot to switch to Noctalia Greeter. Rollback: Ctrl+Alt+F3, log in, then: $rollback && sudo reboot"
  fi
  # Also when greetd is already active (an earlier switch stopped before this, or greetd was enabled
  # by hand): otherwise the next gdm3 upgrade switches back. Debian's greetd package installs it in
  # /usr/sbin (its postinst only compares the basename). debconf goes first, so if it fails the file
  # still differs and the next run retries both.
  if [[ "$(cat "$DEFAULT_DM_FILE" 2>/dev/null || true)" != /usr/sbin/greetd ]]; then
    run sh -c "echo 'greetd shared/default-x-display-manager select greetd' | sudo debconf-set-selections"
  fi
  install_content /usr/sbin/greetd "$DEFAULT_DM_FILE" 0644 sudo
elif [[ "$dm_now" != "$greetd_unit" ]] && ((CHANGED)); then
  notice "greetd is configured but ${dm_now:-another display manager} is still the login screen. To switch: ./install.sh --only greetd --switch-dm"
fi

if ((CHANGED)); then
  notice "In Noctalia: Settings > Security > Noctalia Greeter > Sync Now (optionally turn on Auto-Sync Greeter)."
fi
