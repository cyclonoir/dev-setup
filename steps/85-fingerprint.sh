#!/usr/bin/env bash
# Step (optional, run with --with fingerprint): fingerprint authentication for sudo and admin (polkit)
# prompts. Noctalia's lock screen reads the sensor itself over D-Bus, so pam_fprintd must stay out of
# the shared login stack (common-auth): there the two fight over the sensor and password entry at the
# greeter stalls. Ubuntu's fprintd pam-auth-update profile is "Default: no", so common-auth only has
# it if someone enabled it; this step removes it if so. The login screen stays password-only, which
# also unlocks the keyring and, for AD accounts, fetches a Kerberos ticket.
#
# Editing /etc/pam.d/sudo (a conffile) means a future sudo update that changes that file needs
# manual review; unattended-upgrades holds such packages back.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# --- A supported reader, checked before the PAM module is installed ---
apt_install "${PKGS_FPRINTD[@]}"
devices=""
if ! is_dry_run; then
  devices=$(fprintd-list "$DEV_USER" 2>&1 || true)
  if ! grep -q 'Device at' <<<"$devices"; then
    die "No supported fingerprint reader found (fprintd-list: ${devices//$'\n'/ }). Some OEM readers need libfprint-2-tod1 plus a vendor driver. Nothing in PAM was changed."
  fi
  ok "fingerprint reader found"
fi
apt_install "${PKGS_FPRINTD_PAM[@]}"

# --- Keep pam_fprintd out of the shared login stack ---
if grep -qsE "$FPRINT_PAM_PATTERN" /etc/pam.d/common-auth; then
  info "Removing fingerprint from the shared login stack (it conflicts with Noctalia's lock screen)"
  for f in /etc/pam.d/common-{auth,account,password,session,session-noninteractive}; do
    backup_file "$f" sudo
  done
  sudo_run env DEBIAN_FRONTEND=noninteractive pam-auth-update --disable fprintd
  # pam-auth-update declines (and still exits 0) if the common-* files were edited by hand.
  if ! is_dry_run && grep -qsE "$FPRINT_PAM_PATTERN" /etc/pam.d/common-auth; then
    die "pam_fprintd is still in /etc/pam.d/common-auth (pam-auth-update won't change hand-edited files). Run 'sudo pam-auth-update' and untick Fingerprint authentication, or remove that line by hand, then re-run."
  fi
else
  ok "fingerprint kept out of the shared login stack (common-auth)"
fi

# --- Fingerprint for sudo and admin prompts ---
# FPRINT_PAM_LINE goes before each service's "@include common-auth", so a finger (or, after the
# timeout, the usual password) authenticates. Not every release ships a sudo-i service.
before=$CHANGED   # pam_insert only warns if a file has no anchor line
for service in sudo sudo-i polkit-1; do
  if [[ -f /etc/pam.d/$service || -f /usr/lib/pam.d/$service ]]; then
    pam_insert "/etc/pam.d/$service" "$FPRINT_PAM_PATTERN" before '@include common-auth' "$FPRINT_PAM_LINE"
  elif [[ $service != sudo-i ]]; then
    warn "No PAM file for $service; it won't accept fingerprints."
  fi
done

# --- Enrollment (interactive, so only a reminder) ---
if ! is_dry_run && ! grep -qE "$FPRINT_ENROLLED_PATTERN" <<<"$devices"; then
  notice "Enroll a finger: run fprintd-enroll and touch the sensor until it reports done, then test with fprintd-verify."
fi
if ((CHANGED > before)); then
  notice "Fingerprint now works for sudo, admin prompts and Noctalia's lock screen (its fingerprint setting is on by default). The login screen stays password-only."
fi
