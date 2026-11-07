#!/usr/bin/env bash
# Shared constants and helpers for dev-setup. Sourced by install.sh, verify.sh and every step.
# shellcheck disable=SC2034  # constants are used by the scripts that source this file

set -euo pipefail

# --- Constants (edit these for a different user or machine) ---------------------------------

# The account running the scripts, AD or local (they refuse to run as root). Every per-user change
# goes to this account's $HOME, so it can't be overridden to point somewhere else.
DEV_USER="$(id -un)"
TERMINAL_PKG="foot"
UBUNTU_VERSION_ID="26.04"
UBUNTU_CODENAME="resolute"
GREETER_SESSION="Hyprland"
# claude = Claude Code (aqua:anthropics/claude-code release binaries)
MISE_TOOLS=(neovim@latest node@lts go@latest dotnet@10 gh@latest claude@latest)

PKGS_BASE=(build-essential git curl ca-certificates gpg jq unzip ripgrep fd-find tmux btop)
PKGS_HYPRLAND=(hyprland xdg-desktop-portal-hyprland hyprpolkitagent wl-clipboard brightnessctl "$TERMINAL_PKG")
PKGS_BROWSERS=(vivaldi-stable)
PKGS_WORK_BROWSERS=(microsoft-edge-stable)   # only with --work (work laptop)
PKGS_NOCTALIA=(noctalia)
PKGS_PODMAN=(podman podman-compose uidmap)
PKGS_VIRT=(qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager ovmf swtpm swtpm-tools cpu-checker)
PKGS_GREETD=(greetd noctalia-greeter)
PKGS_FPRINTD=(fprintd)                 # the service; installed first so the reader can be checked
PKGS_FPRINTD_PAM=(libpam-fprintd)      # the PAM module; only once a reader is confirmed
# Added to sudo and polkit-1 only: a finger, or the password after 10 seconds or 2 failed tries.
FPRINT_PAM_LINE="auth    sufficient    pam_fprintd.so max-tries=2 timeout=10"
FPRINT_PAM_PATTERN='^[^#]*pam_fprintd\.so'   # an active (uncommented) pam_fprintd line
FPRINT_ENROLLED_PATTERN='^ +- #[0-9]+:'      # an enrolled finger in fprintd-list output
# gnome-keyring lines in greetd's PAM file; -? also matches PAM's "-auth" form (skipped if missing).
KEYRING_AUTH_PATTERN='^-?auth[[:space:]].*pam_gnome_keyring\.so'
KEYRING_SESSION_PATTERN='^-?session[[:space:]].*pam_gnome_keyring\.so'

NOCTALIA_KEYRING_URL="https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb"
NOCTALIA_KEYRING_PKG="nickh-archive-keyring"
NOCTALIA_SOURCES_FILE="/etc/apt/sources.list.d/noctalia-${UBUNTU_CODENAME}.sources"

VIVALDI_KEY_URL="https://repo.vivaldi.com/archive/linux_signing_key.pub"
VIVALDI_KEYRING="/usr/share/keyrings/vivaldi-browser.gpg"
VIVALDI_LIST="/etc/apt/sources.list.d/vivaldi.list"
EDGE_KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
EDGE_KEYRING="/usr/share/keyrings/microsoft-edge.gpg"
EDGE_LIST="/etc/apt/sources.list.d/microsoft-edge.list"

NERD_FONTS_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download"
declare -A NERD_FONTS=([JetBrainsMono]="JetBrainsMono Nerd Font" [NerdFontsSymbolsOnly]="Symbols Nerd Font")
FONTS_DIR="$HOME/.local/share/fonts"

MISE="$HOME/.local/bin/mise"
MISE_INSTALLER_URL="https://mise.run"
HYPR_HELPERS=(dev-hypr-keybinds dev-hypr-pop dev-hypr-gaps dev-hypr-zoom)
LOGIND_POWER_KEY_CONF="/etc/systemd/logind.conf.d/10-dev-setup-power-key.conf"
HYPR_DIR="$HOME/.config/hypr"
HYPR_MANAGED_CONF="$HYPR_DIR/dev-setup.conf"
HYPR_BIND_PATTERN='^[[:space:]]*bind[a-z]*[[:space:]]*='   # a keybinding line in a Hyprland config
# noctalia-greeter ships this greetd config and points greetd.service at it with a drop-in, so
# /etc/greetd/config.toml is never read.
GREETD_CONF="/etc/greetd/noctalia-greeter.toml"
GREETER_CONF="/var/lib/noctalia-greeter/greeter.toml"
GREETD_PAM="/etc/pam.d/greetd"
DISPLAY_MANAGER_LINK="/etc/systemd/system/display-manager.service"
DEFAULT_DM_FILE="/etc/X11/default-display-manager"

# --- Paths and run state --------------------------------------------------------------------

DEV_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$DEV_SETUP_ROOT/files"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dev-setup"
LOG_FILE="$STATE_DIR/install.log"

# install.sh exports these to the steps; it sets SWITCH_DM and WORK_MACHINE only from its options.
DRY_RUN="${DRY_RUN:-0}"
SWITCH_DM="${SWITCH_DM:-0}"
WORK_MACHINE="${WORK_MACHINE:-0}"
# One ID per install.sh run (exported by it). Backups for the run go under a folder with this name.
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
USER_BACKUP_DIR="$STATE_DIR/backups/$RUN_ID"
SYSTEM_BACKUP_DIR="/var/backups/dev-setup/$RUN_ID"

# Dry runs keep their own notices, so they never clobber the follow-ups from the last real run.
set_notices_file() {
  NOTICES_FILE="$STATE_DIR/notices"
  if [[ "$DRY_RUN" == 1 ]]; then NOTICES_FILE="$STATE_DIR/notices.dry-run"; fi
}
set_notices_file

# CHANGED counts the changes this step has made through run/sudo_run and ensure_line (in a dry run,
# the changes it would make). Steps test ((CHANGED)), or compare it with a saved value, to print
# follow-up notices only when something changed. apt-get update counts too, so a step that reads
# CHANGED must not call apt_update unconditionally.
CHANGED=0

mkdir -p "$STATE_DIR"

# Scratch space for this process, removed on exit. Steps use it and must not set their own EXIT trap.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# --- Logging --------------------------------------------------------------------------------

_log() {
  local level=$1
  shift
  printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$*" >>"$LOG_FILE"
}
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; _log INFO "$*"; }
ok()   { printf '\033[1;32m ok\033[0m %s\n' "$*"; _log OK "$*"; }
warn() { printf '\033[1;33m !!\033[0m %s\n' "$*" >&2; _log WARN "$*"; }
die()  { printf '\033[1;31merr\033[0m %s\n' "$*" >&2; _log ERROR "$*"; exit 1; }

# Record something the user must do after the run (log out, reboot, a manual step). Also logged:
# the notices file is replaced on the next run, and some notices (greetd's rollback) matter later.
notice() {
  touch "$NOTICES_FILE"
  grep -qxF -- "$*" "$NOTICES_FILE" && return 0
  printf '%s\n' "$*" >>"$NOTICES_FILE"
  _log NOTICE "$*"
}

# --- Command execution ----------------------------------------------------------------------

is_dry_run() { [[ "$DRY_RUN" == 1 ]]; }

# Run a command, or only print it in dry-run mode. Either way it counts as a change.
run() {
  CHANGED=$((CHANGED + 1))
  if is_dry_run; then
    printf '\033[2m[dry-run]\033[0m %s\n' "$(printf '%q ' "$@")"
    return 0
  fi
  _log RUN "$*"
  "$@"
}

sudo_run() { run sudo "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Prefix for reading a file that may be root-only: `sudo -n` when sudo is already unlocked (install.sh
# unlocks it for real runs), otherwise a plain read, so dry runs never prompt for a password.
# Usage: read_prefix sudo|"" → sets the global READ_PREFIX array.
read_prefix() {
  READ_PREFIX=()
  if [[ "${1:-}" == sudo ]] && sudo -n true 2>/dev/null; then READ_PREFIX=(sudo -n); fi
}

# --- Checks ---------------------------------------------------------------------------------

require_not_root() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root. Steps use sudo where needed."
}

require_ubuntu() {
  local id="" version_id="" pretty_name="unknown"
  # Sourced in a subshell, so its UBUNTU_CODENAME doesn't overwrite ours.
  # shellcheck source=/dev/null
  [[ -r /etc/os-release ]] && IFS='|' read -r id version_id pretty_name \
    < <(. /etc/os-release && printf '%s|%s|%s\n' "${ID:-}" "${VERSION_ID:-}" "${PRETTY_NAME:-unknown}")
  if [[ "$id" == ubuntu && "$version_id" == "$UBUNTU_VERSION_ID" ]]; then
    return 0
  fi
  if [[ "${FORCE_OS:-0}" == 1 ]]; then
    warn "Expected Ubuntu $UBUNTU_VERSION_ID, found $pretty_name. Continuing because FORCE_OS=1."
    return 0
  fi
  die "Expected Ubuntu $UBUNTU_VERSION_ID, found $pretty_name."
}

CHECK_PASS=0
CHECK_WARN=0
CHECK_FAIL=0

# Run a check command and report it. A failing "warn" check is reported but not counted as a failure.
# Usage: check fail|warn "description" command [args...]
check() {
  local level=$1 desc=$2
  shift 2
  if "$@" >/dev/null 2>&1; then
    ok "$desc"
    CHECK_PASS=$((CHECK_PASS + 1))
  elif [[ "$level" == warn ]]; then
    warn "$desc"
    CHECK_WARN=$((CHECK_WARN + 1))
  else
    printf '\033[1;31mFAIL\033[0m %s\n' "$desc"
    _log FAIL "$desc"
    CHECK_FAIL=$((CHECK_FAIL + 1))
  fi
}

# IT's compliance baseline on a work machine: only ever checked, never changed. Missing items warn.
# Used by preflight (install.sh --work) and by verify.sh --work.
check_it_baseline() {
  check warn "Disk encrypted (LUKS)" bash -c 'lsblk -rno FSTYPE | grep -qx crypto_LUKS'
  check warn "Domain joined (realm list)" bash -c 'realm list --name-only | grep -q .'
  check warn "Sophos running (sophos-spl)" systemctl is-active --quiet sophos-spl
  check warn "FortiClient installed" pkg_installed forticlient
  check warn "Intune app installed" pkg_installed intune-portal
  check warn "GNOME installed (fallback session for IT and FortiClient)" pkg_installed gnome-shell
}

# The unit behind display-manager.service (e.g. gdm.service, greetd.service), or nothing. This is
# what actually starts at boot; `systemctl is-enabled gdm3` can't tell, because gdm3 is an alias.
active_display_manager() {
  local target
  target=$(readlink -f "$DISPLAY_MANAGER_LINK" 2>/dev/null) || return 0
  [[ -e "$target" ]] && basename "$target"
  return 0
}

# grep without -q: an early exit would SIGPIPE fc-list, which pipefail reports as "not found".
font_installed() { fc-list : family 2>/dev/null | grep -F "$1" >/dev/null; }

# --- Packages -------------------------------------------------------------------------------

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep 'install ok installed' >/dev/null; }

# True if apt knows an installable version of the package (i.e. its repo's lists are present).
pkg_has_candidate() {
  local candidate
  candidate=$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')
  [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

apt_update() { sudo_run apt-get update; }

# Install only the packages that aren't installed yet. Refreshes the package lists first if one has
# no install candidate (its repo was just added, or an earlier apt-get update failed), so steps that
# add a repo don't run apt-get update themselves.
apt_install() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    ok "already installed: $*"
    return 0
  fi
  for p in "${missing[@]}"; do
    if ! pkg_has_candidate "$p"; then
      apt_update
      break
    fi
  done
  info "installing: ${missing[*]}"
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# --- Files ----------------------------------------------------------------------------------

# Back up PATH once per run, before its first change, into a per-run folder outside the directory
# tools read (so no stray *.bak files in /etc/apt/preferences.d or /etc/pam.d). Symlinks are
# followed, so a stowed dotfile is copied, not just its link. BACKED_UP covers dry runs, which copy
# nothing, so they show each backup once too. Usage: backup_file PATH [sudo]
declare -A BACKED_UP=()
backup_file() {
  local path=$1 use_sudo=${2:-} base dest
  [[ -e "$path" ]] || return 0
  if [[ "$use_sudo" == sudo ]]; then base=$SYSTEM_BACKUP_DIR; else base=$USER_BACKUP_DIR; fi
  dest="$base$(readlink -f "$path")"
  [[ -e "$dest" || -n "${BACKED_UP[$dest]:-}" ]] && return 0
  BACKED_UP[$dest]=1
  local pre=()
  [[ "$use_sudo" == sudo ]] && pre=(sudo)
  run "${pre[@]}" mkdir -p "$(dirname "$dest")"
  run "${pre[@]}" cp -aL "$path" "$dest"
}

# Install SRC at DEST only if the content differs, backing up the old DEST first. In a dry run,
# show the diff. The new file goes to a dot-file beside DEST and is renamed over it: `install` alone
# writes DEST in place, so an interrupted run could leave /etc/pam.d/sudo empty and lock out sudo.
# Usage: install_file SRC DEST MODE [sudo]
install_file() {
  local src=$1 dest=$2 mode=$3 use_sudo=${4:-}
  local new="${dest%/*}/.${dest##*/}.dev-setup-new" pre=()
  [[ "$use_sudo" == sudo ]] && pre=(sudo)
  read_prefix "$use_sudo"
  if "${READ_PREFIX[@]}" test -f "$dest" && "${READ_PREFIX[@]}" cmp -s "$src" "$dest"; then
    ok "unchanged: $dest"
    return 0
  fi
  if is_dry_run; then
    if "${READ_PREFIX[@]}" test -f "$dest"; then
      "${READ_PREFIX[@]}" diff -u "$dest" "$src" | sed 's/^/    /' || true
    else
      sed 's/^/    + /' "$src"
    fi
  fi
  backup_file "$dest" "$use_sudo"
  run "${pre[@]}" install -D -m "$mode" "$src" "$new"
  run "${pre[@]}" mv -f "$new" "$dest"
  if is_dry_run; then ok "would write: $dest"; else ok "wrote: $dest"; fi
}

# Install CONTENT plus a newline at DEST, like install_file. Never pass CONTENT as a $(...) that can
# fail: set -e doesn't catch a failed substitution used as an argument, so the file would be written
# with whatever the substitution printed. Usage: install_content CONTENT DEST MODE [sudo]
install_content() {
  local tmp
  tmp=$(mktemp -p "$TMP_DIR")
  printf '%s\n' "$1" >"$tmp"
  install_file "$tmp" "${@:2}"
}

# Install a template with its @KEY@ placeholders replaced.
# Usage: install_template TEMPLATE DEST MODE sudo|"" KEY=VALUE...
install_template() {
  local content kv
  content=$(<"$1")
  for kv in "${@:5}"; do
    # Quoted replacement: with bash 5.2+ patsub_replacement, an unquoted & would expand to the match.
    content=${content//"@${kv%%=*}@"/"${kv#*=}"}
  done
  install_content "$content" "$2" "$3" "$4"
}

# Append LINE to a user file unless an identical line exists. Adds a newline first if the file doesn't
# end in one, so the line isn't glued onto the last line. Appends with >> rather than install_file,
# which would replace a stowed (symlinked) dotfile with a plain file. Usage: ensure_line FILE LINE
ensure_line() {
  local file=$1 line=$2
  if grep -qxsF -- "$line" "$file"; then
    ok "already in $file: $line"
    return 0
  fi
  backup_file "$file"
  CHANGED=$((CHANGED + 1))   # appended with >> below, not through run
  if is_dry_run; then
    printf '\033[2m[dry-run]\033[0m append to %s: %s\n' "$file" "$line"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  if [[ -s "$file" && -n "$(tail -c1 "$file")" ]]; then printf '\n' >>"$file"; fi
  printf '%s\n' "$line" >>"$file"
  _log RUN "append to $file: $line"
  ok "added to $file: $line"
}

# Add LINE before or after the first exact ANCHOR line of a PAM file, unless a line matching
# PRESENT_REGEX exists. A service with only a vendor file in /usr/lib/pam.d gets an edited copy in
# /etc (which overrides the vendor file from then on). ANCHOR and LINE must not contain / & or regex
# metacharacters. The sed output goes to a temp file; never pass it as a $(...) argument.
# Usage: pam_insert FILE PRESENT_REGEX before|after ANCHOR LINE
pam_insert() {
  local file=$1 present=$2 where=$3 anchor=$4 line=$5 src=$1 tmp
  [[ -f "$src" ]] || src=/usr/lib/pam.d/${file##*/}
  if grep -qsE "$present" "$src"; then
    ok "$file already has: $line"
    return 0
  fi
  if ! grep -qxsF "$anchor" "$src"; then
    warn "No '$anchor' line in $src; add this by hand: $line"
    return 0
  fi
  tmp=$(mktemp -p "$TMP_DIR")
  if [[ "$where" == before ]]; then
    sed "0,/^${anchor}\$/s//${line}\n&/" "$src" >"$tmp"
  else
    sed "0,/^${anchor}\$/s//&\n${line}/" "$src" >"$tmp"
  fi
  install_file "$tmp" "$file" 0644 sudo
}

# --- Users and groups -----------------------------------------------------------------------

user_in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -xF "$2" >/dev/null; }

# True if a subuid/subgid FILE has a range for DEV_USER: exact match on the user's name or numeric ID
# (both forms are valid in these files). Usage: subid_has_range FILE
subid_has_range() {
  [[ -f "$1" ]] && awk -F: -v u="$DEV_USER" -v id="$(id -u)" '$1 == u || $1 == id { f = 1 } END { exit !f }' "$1"
}
