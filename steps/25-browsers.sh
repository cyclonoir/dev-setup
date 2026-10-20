#!/usr/bin/env bash
# Step: Vivaldi (main browser) and Microsoft Edge (work browser: Intune and Conditional Access on Linux
# go through Edge). Both come from their vendors' apt repos, under the file names their packages use,
# so the vendors' own repo-maintenance scripts don't add duplicates.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Add a vendor apt repo unless its list file exists. Usage: add_vendor_repo KEY_URL KEYRING LIST_FILE REPO_LINE
add_vendor_repo() {
  local key_url=$1 keyring=$2 list_file=$3 repo_line=$4
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
if add_vendor_repo "$VIVALDI_KEY_URL" "$VIVALDI_KEYRING" "$VIVALDI_LIST" \
  "deb [arch=amd64 signed-by=$VIVALDI_KEYRING] https://repo.vivaldi.com/archive/deb/ stable main"; then
  repos_added=1
fi
if add_vendor_repo "$EDGE_KEY_URL" "$EDGE_KEYRING" "$EDGE_LIST" \
  "deb [arch=amd64 signed-by=$EDGE_KEYRING] https://packages.microsoft.com/repos/edge stable main"; then
  repos_added=1
fi
((repos_added)) && apt_update

apt_install "${PKGS_BROWSERS[@]}"
