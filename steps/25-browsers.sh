#!/usr/bin/env bash
# Step: Vivaldi (main browser), plus Microsoft Edge on a work machine (--work): Intune and
# Conditional Access on Linux go through Edge. Each is bootstrapped from its vendor's apt repo; once
# installed, the vendor's package maintains its own repo entry (Edge replaces ours with a
# repos/edge-stable entry), so repo setup is skipped from then on to avoid configuring a repo twice.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Add a vendor apt repo unless its package is installed or the repo is fully configured (list file
# plus a non-empty keyring). The key is downloaded and checked before anything is written, and the
# list file is written last, so a failed download can't leave apt pointing at a missing key.
# Not called as an `if` condition (that would switch off set -e inside it).
# Usage: add_vendor_repo PACKAGE KEY_URL KEYRING LIST_FILE REPO_LINE
add_vendor_repo() {
  local package=$1 key_url=$2 keyring=$3 list_file=$4 repo_line=$5
  if pkg_installed "$package"; then
    ok "$package installed; its package maintains its own apt repo"
    return 0
  fi
  if [[ -f "$list_file" && -s "$keyring" ]]; then
    ok "repo configured: $list_file"
    return 0
  fi
  run curl -fsSL -o "$TMP_DIR/$package.key" "$key_url"
  if ! is_dry_run; then
    if ! { gpg --dearmor <"$TMP_DIR/$package.key" >"$TMP_DIR/$package.gpg" 2>/dev/null \
      && gpg --show-keys "$TMP_DIR/$package.gpg" >/dev/null 2>&1; }; then
      die "The signing key from $key_url isn't a valid OpenPGP key; nothing was written. Re-run to retry."
    fi
  fi
  backup_file "$keyring" sudo   # a keyring left behind without its list file
  # 0644 so apt's unprivileged _apt user can read it even under a strict umask.
  sudo_run install -D -m 0644 "$TMP_DIR/$package.gpg" "$keyring"
  install_content "$repo_line" "$list_file" 0644 sudo
}

pkgs=("${PKGS_BROWSERS[@]}")
add_vendor_repo vivaldi-stable "$VIVALDI_KEY_URL" "$VIVALDI_KEYRING" "$VIVALDI_LIST" \
  "deb [arch=amd64 signed-by=$VIVALDI_KEYRING] https://repo.vivaldi.com/archive/deb/ stable main"
if [[ "$WORK_MACHINE" == 1 ]]; then
  add_vendor_repo microsoft-edge-stable "$EDGE_KEY_URL" "$EDGE_KEYRING" "$EDGE_LIST" \
    "deb [arch=amd64 signed-by=$EDGE_KEYRING] https://packages.microsoft.com/repos/edge stable main"
  pkgs+=("${PKGS_WORK_BROWSERS[@]}")
else
  ok "Edge skipped: work machines only (--work)"
fi

# A newly added repo's package has no install candidate yet, so apt_install refreshes the lists.
apt_install "${pkgs[@]}"
