#!/usr/bin/env bash
# Step: mise for per-user, per-project dev tools (Neovim, Node, Go, .NET).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if [[ -x "$MISE" ]]; then
  ok "mise installed: $("$MISE" --version)"
else
  info "Installing mise to $MISE"
  run sh -c 'curl -fsSL https://mise.run | sh'
fi

# --- Shell activation ---
ensure_line "$HOME/.bashrc" "eval \"\$($MISE activate bash)\""

if have nu; then
  # shellcheck disable=SC2016  # literal nushell code
  nu_dir=$(nu -c '$nu.default-config-dir')
  if [[ -x "$MISE" ]]; then
    tmp=$(mktemp)
    "$MISE" activate nu >"$tmp"
    install_file "$tmp" "$nu_dir/mise.nu" 0644
    rm -f "$tmp"
  else
    run sh -c "$MISE activate nu > $nu_dir/mise.nu"
  fi
  # shellcheck disable=SC2016  # literal nushell code
  ensure_line "$nu_dir/config.nu" 'use ($nu.default-config-dir | path join mise.nu)'
else
  notice "nushell isn't installed, so only bash got mise activation. Re-run --only mise after installing nu."
fi

# --- Global tools ---
run "$MISE" use -g "${MISE_TOOLS[@]}"

# Let mise read the SDK version from a repo's global.json.
current=$("$MISE" settings get idiomatic_version_file_enable_tools 2>/dev/null || true)
if [[ "$current" == *dotnet* ]]; then
  ok "mise reads global.json for dotnet"
else
  run "$MISE" settings add idiomatic_version_file_enable_tools dotnet
fi

notice "Open a new terminal so mise activation takes effect. Run 'mise upgrade' regularly: .NET and other mise tools don't get Ubuntu's automatic security updates."
