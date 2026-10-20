#!/usr/bin/env bash
# Step: Vivaldi (main browser) and Microsoft Edge (work browser: Intune and Conditional Access on Linux
# go through Edge). Each is bootstrapped from its vendor's apt repo; once installed, the vendor's package
# maintains its own repo entry (Edge replaces ours with a repos/edge-stable entry), so repo setup is
# skipped from then on to avoid configuring the same repo twice.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Add a vendor apt repo unless the package or the list file is already there. Returns 0 if it added one.
# Usage: add_vendor_repo PACKAGE KEY_URL KEYRING LIST_FILE REPO_LINE
add_vendor_repo() {
  local package=$1 key_url=$2 keyring=$3 list_file=$4 repo_line=$5
  if pkg_installed "$package"; then
    ok "$package installed; its package maintains its own apt repo"
    return 1
  fi
  if [[ -f "$list_file" ]]; then
    ok "repo configured: $list_file"
    return 1
  fi
  run sh -c "curl -fsSL '$key_url' | sudo gpg --dearmor --yes -o '$keyring'"
  if is_dry_run; then
    printf '\033[2m[dry-run]\033[0m write %s: %s\n' "$list_file" "$repo_line"
  else
    printf '%s\n' "$repo_line" | sudo tee "$list_file" >/dev/null
    ok "wrote: $list_file"
  fi
  return 0
}

repos_added=0
if add_vendor_repo vivaldi-stable "$VIVALDI_KEY_URL" "$VIVALDI_KEYRING" "$VIVALDI_LIST" \
  "deb [arch=amd64 signed-by=$VIVALDI_KEYRING] https://repo.vivaldi.com/archive/deb/ stable main"; then
  repos_added=1
fi
if add_vendor_repo microsoft-edge-stable "$EDGE_KEY_URL" "$EDGE_KEYRING" "$EDGE_LIST" \
  "deb [arch=amd64 signed-by=$EDGE_KEYRING] https://packages.microsoft.com/repos/edge stable main"; then
  repos_added=1
fi
if ((repos_added)); then
  apt_update
fi

apt_install "${PKGS_BROWSERS[@]}"
