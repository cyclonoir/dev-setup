#!/usr/bin/env bash
# Step: Claude Code, through mise. mise's "claude" tool installs Anthropic's release binaries
# (aqua:anthropics/claude-code, checksum-verified) into mise's global config, like the other dev tools.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

if [[ ! -x "$MISE" ]] && ! is_dry_run; then
  die "mise isn't installed. Run: ./install.sh --only mise"
fi

# mise which only looks (mise exec would install a missing tool, even in a dry run).
if claude_bin=$("$MISE" which claude 2>/dev/null); then
  ok "Claude Code installed: $("$claude_bin" --version 2>/dev/null || echo "version unknown")"
else
  info "Installing Claude Code through mise"
  run "$MISE" use -g "$CLAUDE_CODE_TOOL"
fi

notice "Run 'claude' in a new terminal to sign in. Update it with 'mise upgrade claude'; 'mise prune' removes old versions."
