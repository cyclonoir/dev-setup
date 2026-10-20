#!/usr/bin/env bash
# Configure a new Ubuntu 26.04 developer machine on top of IT's compliance baseline.
# Safe to re-run: every step checks before it changes anything.

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

DEFAULT_STEPS=(preflight base fonts hyprland browsers noctalia hypr-config mise podman virt greetd)
OPTIONAL_STEPS=(umbriel)

usage() {
  cat <<EOF
Usage: ./install.sh [options]

Options:
  --only STEP[,STEP...]   Run only these steps (preflight still runs unless skipped)
  --skip STEP[,STEP...]   Skip these steps
  --with STEP[,STEP...]   Also run optional steps: ${OPTIONAL_STEPS[*]}
  --dry-run               Print commands instead of running them
  --switch-dm             Let the greetd step replace GDM as the login screen (takes effect on reboot)
  -h, --help              Show this help

Default steps: ${DEFAULT_STEPS[*]}
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

step_file() {
  local matches=("$DEV_SETUP_ROOT"/steps/*-"$1".sh)
  [[ -f "${matches[0]}" ]] || die "Unknown step: $1"
  printf '%s\n' "${matches[0]}"
}

# Work out which steps to run, in canonical order.
steps=()
if ((${#only[@]})); then
  for s in "${only[@]}"; do step_file "$s" >/dev/null; done
  contains preflight "${skip[@]}" || steps+=(preflight)
  for s in "${DEFAULT_STEPS[@]}" "${OPTIONAL_STEPS[@]}"; do
    [[ "$s" == preflight ]] && continue
    contains "$s" "${only[@]}" && steps+=("$s")
  done
else
  for s in "${with[@]}"; do step_file "$s" >/dev/null; done
  for s in "${DEFAULT_STEPS[@]}" "${OPTIONAL_STEPS[@]}"; do
    contains "$s" "${skip[@]}" && continue
    if contains "$s" "${OPTIONAL_STEPS[@]}" && ! contains "$s" "${with[@]}"; then continue; fi
    steps+=("$s")
  done
fi

require_not_root
rm -f "$NOTICES_FILE"
_log INFO "=== install.sh start: steps=${steps[*]} dry_run=$DRY_RUN switch_dm=$SWITCH_DM ==="

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
