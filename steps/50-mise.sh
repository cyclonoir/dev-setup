#!/usr/bin/env bash
# Step: mise for per-user, per-project dev tools (Neovim, Node, Go, .NET, GitHub CLI, Claude Code,
# chezmoi, tree-sitter, CSharpier, uv, atuin, vivid).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if [[ -x "$MISE" ]]; then
  ok "mise installed: $("$MISE" --version)"
else
  info "Installing mise to $MISE"
  # Download the installer first rather than piping it into sh: a failed or cut-off download stops
  # here instead of running half a script (or succeeding silently with nothing installed).
  run curl -fsSL -o "$TMP_DIR/mise-install.sh" "$MISE_INSTALLER_URL"
  run sh "$TMP_DIR/mise-install.sh"
  if ! is_dry_run && [[ ! -x "$MISE" ]]; then
    die "The mise installer finished but $MISE doesn't exist."
  fi
fi

# --- Shell activation ---
ensure_line "$HOME/.bashrc" "eval \"\$($MISE activate bash)\""

# --- Global tools ---
# Only add tools missing from the global config: `mise use -g name@latest` on every run would
# upgrade them and overwrite versions pinned since. mise rewrites that file itself, so it's backed
# up before each mise write, like any file the steps edit.
mise_config="${MISE_GLOBAL_CONFIG_FILE:-$HOME/.config/mise/config.toml}"
configured=$("$MISE" ls --global --json 2>/dev/null | jq -r 'keys[]' 2>/dev/null || true)
missing=()
for tool in "${MISE_TOOLS[@]}"; do
  grep -qxF "${tool%%@*}" <<<"$configured" || missing+=("$tool")
done
if ((${#missing[@]})); then
  backup_file "$mise_config"
  run "$MISE" use -g "${missing[@]}"
  if [[ " ${missing[*]} " == *" claude@"* ]]; then
    notice "Run 'claude' in a new terminal to sign in to Claude Code."
  fi
else
  ok "mise global tools configured: ${MISE_TOOLS[*]%%@*}"
fi

# Let mise read the SDK version from a repo's global.json.
current=$("$MISE" settings get idiomatic_version_file_enable_tools 2>/dev/null || true)
if [[ "$current" == *dotnet* ]]; then
  ok "mise reads global.json for dotnet"
else
  backup_file "$mise_config"
  run "$MISE" settings add idiomatic_version_file_enable_tools dotnet
fi

if ((CHANGED)); then
  notice "Open a new terminal so mise activation takes effect. Run 'mise upgrade' regularly: .NET and other mise tools don't get Ubuntu's automatic security updates."
fi
