#!/usr/bin/env bash
# Step: your dotfiles, from the chezmoi repo. The first run clones it over HTTPS and applies it, which
# asks for the age passphrase once: that decrypts the key for the repo's encrypted files (SSH keys, the
# work server list). Then origin switches to SSH, through the personal.github.com host the repo's SSH
# config just set up, so you can push. From then on the dotfiles are chezmoi's to manage (chezmoi
# update, chezmoi apply); later runs of this step don't apply them again.
# Runs before the theme step, which adds its Neovim spec to the config this step brings.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

chezmoi() { "$MISE" exec -- chezmoi "$@"; }

if [[ -d "$DOTFILES_SOURCE/.git" ]]; then
  ok "dotfiles source exists: $DOTFILES_SOURCE"
else
  work=false
  if [[ "$WORK_MACHINE" == 1 ]]; then work=true; fi
  run chezmoi init --promptBool "Work machine=$work" "$DOTFILES_REPO_HTTPS"
fi

# The repo's decrypt script writes the age key on the first apply, so without it the dotfiles were
# never applied here (or the passphrase was mistyped, which stops the apply before any file changes).
if [[ -f "$AGE_KEY" ]]; then
  ok "dotfiles applied before (age key present); manage them with chezmoi"
else
  if ! is_dry_run; then
    # Back up what chezmoi is about to replace, like every other file these steps change.
    while IFS= read -r target; do
      if [[ -f "$target" ]]; then backup_file "$target"; fi
    done < <(chezmoi managed --path-style absolute --include files)
  fi
  info "Applying your dotfiles: enter the age passphrase when chezmoi asks for it"
  run chezmoi apply
fi

origin=$(git -C "$DOTFILES_SOURCE" remote get-url origin 2>/dev/null || true)
if [[ "$origin" == "$DOTFILES_REPO_SSH" ]]; then
  ok "dotfiles origin: $DOTFILES_REPO_SSH"
elif [[ "$origin" == "$DOTFILES_REPO_HTTPS" ]] || is_dry_run; then
  run git -C "$DOTFILES_SOURCE" remote set-url origin "$DOTFILES_REPO_SSH"
else
  warn "dotfiles origin is ${origin:-not set}, not $DOTFILES_REPO_HTTPS; left as it is."
fi
