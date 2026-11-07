#!/usr/bin/env bash
# Configure an Ubuntu 26.04 developer machine, work or personal. On a work machine (--work) it sits on
# top of IT's compliance baseline, which preflight then checks (read-only).
# Safe to re-run: every step checks before it changes anything.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Every step in run order. Optional steps only run when named with --with (or --only).
ALL_STEPS=(preflight base fonts hyprland browsers noctalia hypr-config mise podman virt greetd fingerprint umbriel)
OPTIONAL_STEPS=(fingerprint umbriel)

contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

default_steps=()
for s in "${ALL_STEPS[@]}"; do
  contains "$s" "${OPTIONAL_STEPS[@]}" || default_steps+=("$s")
done

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --only STEP[,STEP...]   Run only these steps (preflight still runs unless skipped)
  --skip STEP[,STEP...]   Skip these steps
  --with STEP[,STEP...]   Also run optional steps: fingerprint (fingerprint for sudo, admin
                          prompts and the lock screen), umbriel (extra login session to trial)
  --work                  Work laptop: install Edge; preflight also checks IT's baseline (read-only)
  --dry-run               Print commands instead of running them
  --switch-dm             Let the greetd step replace GDM as the login screen (takes effect on reboot)
  -h, --help              Show this help

Default steps: ${default_steps[*]}
EOF
}

only=()
skip=()
with=()
# Only the options set these, never the environment: a stray export must not switch the login
# screen or add Microsoft's repo. (DRY_RUN may come from the environment; it only makes runs safer.)
SWITCH_DM=0
WORK_MACHINE=0
while (($#)); do
  case $1 in
    --only) IFS=, read -ra only <<<"${2:?--only needs a value}"; shift 2 ;;
    --skip) IFS=, read -ra skip <<<"${2:?--skip needs a value}"; shift 2 ;;
    --with) IFS=, read -ra with <<<"${2:?--with needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --switch-dm) SWITCH_DM=1; shift ;;
    --work) WORK_MACHINE=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done
export DRY_RUN SWITCH_DM WORK_MACHINE RUN_ID
set_notices_file   # --dry-run may have just been set

# Work out which steps to run, in run order.
steps=()
for s in "${only[@]}" "${skip[@]}" "${with[@]}"; do
  contains "$s" "${ALL_STEPS[@]}" || die "Unknown step: $s (steps: ${ALL_STEPS[*]})"
done
for s in "${ALL_STEPS[@]}"; do
  contains "$s" "${skip[@]}" && continue
  if ((${#only[@]})); then
    [[ "$s" == preflight ]] || contains "$s" "${only[@]}" "${with[@]}" || continue
  elif contains "$s" "${OPTIONAL_STEPS[@]}"; then
    contains "$s" "${with[@]}" || continue
  fi
  steps+=("$s")
done

require_not_root
rm -f "$NOTICES_FILE"
_log INFO "=== install.sh start: steps=${steps[*]} dry_run=$DRY_RUN switch_dm=$SWITCH_DM work_machine=$WORK_MACHINE ==="

# Ask for the sudo password once and keep the timestamp fresh while steps run.
if ! is_dry_run; then
  sudo -v || die "sudo is required."
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  trap 'kill $! 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT
fi

# Also shown when a step fails: the next run deletes the notices file, and the finished steps have
# nothing left to change, so they won't repeat their notices (e.g. greetd's rollback command).
show_notices() {
  if [[ -s "$NOTICES_FILE" ]]; then
    info "Follow-up needed:"
    while IFS= read -r line; do printf '  - %s\n' "$line"; done <"$NOTICES_FILE"
  fi
}

for s in "${steps[@]}"; do
  printf '\n\033[1m--- %s ---\033[0m\n' "$s"
  bash "$DEV_SETUP_ROOT"/steps/[0-9][0-9]-"$s".sh || {
    show_notices
    die "Step '$s' failed. See $LOG_FILE. Fix the problem and re-run; finished steps are skipped quickly."
  }
done

printf '\n\033[1m--- done ---\033[0m\n'
show_notices
for d in "$SYSTEM_BACKUP_DIR" "$USER_BACKUP_DIR"; do
  if [[ -d "$d" ]]; then info "Originals of files changed in this run: $d"; fi
done
info "Run ./verify.sh to check the result. Log: $LOG_FILE"
