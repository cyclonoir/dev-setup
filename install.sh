#!/usr/bin/env bash
# Configure an Ubuntu 26.04 developer machine, work or personal. On a work machine it sits on top of
# IT's compliance baseline, which --with compliance checks (read-only).
# Safe to re-run: every step checks before it changes anything.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

# Every step in run order. Optional steps only run when named with --with (or --only).
ALL_STEPS=(preflight compliance base fonts hyprland browsers noctalia hypr-config mise claude podman virt greetd umbriel)
OPTIONAL_STEPS=(compliance umbriel)
default_steps=()
for s in "${ALL_STEPS[@]}"; do
  [[ " ${OPTIONAL_STEPS[*]} " == *" $s "* ]] || default_steps+=("$s")
done

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --only STEP[,STEP...]   Run only these steps (preflight still runs unless skipped)
  --skip STEP[,STEP...]   Skip these steps
  --with STEP[,STEP...]   Also run optional steps: compliance (work machine: check IT's
                          baseline, read-only, and install Edge), umbriel (extra login
                          session to trial)
  --dry-run               Print commands instead of running them
  --switch-dm             Let the greetd step replace GDM as the login screen (takes effect on reboot)
  -h, --help              Show this help

Default steps: ${default_steps[*]}
EOF
}

only=()
skip=()
with=()
while (($#)); do
  case $1 in
    --only) IFS=, read -ra only <<<"${2:?--only needs a value}"; shift 2 ;;
    --skip) IFS=, read -ra skip <<<"${2:?--skip needs a value}"; shift 2 ;;
    --with) IFS=, read -ra with <<<"${2:?--with needs a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --switch-dm) SWITCH_DM=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done
export DRY_RUN SWITCH_DM

contains() {
  local needle=$1 item
  shift
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

is_optional() { contains "$1" "${OPTIONAL_STEPS[@]}"; }

step_file() {
  local matches=("$DEV_SETUP_ROOT"/steps/*-"$1".sh)
  [[ -f "${matches[0]}" ]] || die "Unknown step: $1"
  printf '%s\n' "${matches[0]}"
}

# Work out which steps to run, in run order.
steps=()
for s in "${only[@]}" "${with[@]}"; do step_file "$s" >/dev/null; done
for s in "${ALL_STEPS[@]}"; do
  contains "$s" "${skip[@]}" && continue
  if ((${#only[@]})); then
    [[ "$s" == preflight ]] || contains "$s" "${only[@]}" "${with[@]}" || continue
  elif is_optional "$s"; then
    contains "$s" "${with[@]}" || continue
  fi
  steps+=("$s")
done

# The compliance option marks a work machine, which also gets Edge (browsers step).
WORK_MACHINE=0
if contains compliance "${steps[@]}"; then WORK_MACHINE=1; fi
export WORK_MACHINE

require_not_root
rm -f "$NOTICES_FILE"
_log INFO "=== install.sh start: steps=${steps[*]} dry_run=$DRY_RUN switch_dm=$SWITCH_DM work_machine=$WORK_MACHINE ==="

# Ask for the sudo password once and keep the timestamp fresh while steps run.
if ! is_dry_run; then
  sudo -v || die "sudo is required."
  while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
  trap 'kill $! 2>/dev/null || true' EXIT
fi

for s in "${steps[@]}"; do
  printf '\n\033[1m--- %s ---\033[0m\n' "$s"
  bash "$(step_file "$s")" || die "Step '$s' failed. See $LOG_FILE. Fix the problem and re-run; finished steps are skipped quickly."
done

printf '\n\033[1m--- done ---\033[0m\n'
if [[ -s "$NOTICES_FILE" ]]; then
  info "Follow-up needed:"
  while IFS= read -r line; do printf '  - %s\n' "$line"; done <"$NOTICES_FILE"
fi
info "Run ./verify.sh to check the result. Log: $LOG_FILE"
