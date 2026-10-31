#!/usr/bin/env bash
# Shared constants and helpers for dev-setup. Sourced by install.sh, verify.sh and every step.
# shellcheck disable=SC2034  # constants are used by the scripts that source this file

set -euo pipefail

# --- Constants (edit these for a different user or machine) ---------------------------------

# The account running the scripts, AD or local (they refuse to run as root). Override: DEV_USER=name
DEV_USER="${DEV_USER:-$(id -un)}"
TERMINAL_PKG="foot"
UBUNTU_VERSION_ID="26.04"
UBUNTU_CODENAME="resolute"
GREETER_SESSION="Hyprland"
MISE_TOOLS=(neovim@latest node@lts go@latest dotnet@10)

PKGS_BASE=(build-essential git curl ca-certificates gpg jq unzip ripgrep fd-find tmux btop)
PKGS_HYPRLAND=(hyprland xdg-desktop-portal-hyprland hyprpolkitagent wl-clipboard brightnessctl "$TERMINAL_PKG")
PKGS_BROWSERS=(vivaldi-stable)
PKGS_WORK_BROWSERS=(microsoft-edge-stable)   # only with --with compliance (work laptop)
PKGS_NOCTALIA=(noctalia)
PKGS_PODMAN=(podman podman-compose uidmap)
PKGS_VIRT=(qemu-system-x86 libvirt-daemon-system libvirt-clients virt-manager ovmf swtpm swtpm-tools cpu-checker)
PKGS_GREETD=(greetd noctalia-greeter)

NOCTALIA_KEYRING_URL="https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb"
NOCTALIA_SOURCES_URL="https://pkg.noctalia.dev/deb/noctalia-${UBUNTU_CODENAME}.sources"
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
HYPR_HELPERS=(dev-hypr-keybinds dev-hypr-pop dev-hypr-gaps dev-hypr-zoom)
LOGIND_POWER_KEY_CONF="/etc/systemd/logind.conf.d/10-dev-setup-power-key.conf"
HYPR_DIR="$HOME/.config/hypr"
HYPR_MANAGED_CONF="$HYPR_DIR/dev-setup.conf"
GREETD_CONF="/etc/greetd/config.toml"
GREETER_CONF="/var/lib/noctalia-greeter/greeter.toml"
GREETD_PAM="/etc/pam.d/greetd"

# --- Paths and run state --------------------------------------------------------------------

DEV_SETUP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILES_DIR="$DEV_SETUP_ROOT/files"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dev-setup"
LOG_FILE="$STATE_DIR/install.log"
NOTICES_FILE="$STATE_DIR/notices"

DRY_RUN="${DRY_RUN:-0}"
SWITCH_DM="${SWITCH_DM:-0}"
WORK_MACHINE="${WORK_MACHINE:-0}"   # set by install.sh when the compliance step is selected

mkdir -p "$STATE_DIR"

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

# Record something the user must do after the run (log out, reboot, a manual step).
notice() {
  touch "$NOTICES_FILE"
  grep -qxF -- "$*" "$NOTICES_FILE" || printf '%s\n' "$*" >>"$NOTICES_FILE"
}

# --- Command execution ----------------------------------------------------------------------

is_dry_run() { [[ "$DRY_RUN" == 1 ]]; }

# Run a command, or only print it in dry-run mode.
run() {
  if is_dry_run; then
    printf '\033[2m[dry-run]\033[0m %s\n' "$(printf '%q ' "$@")"
    return 0
  fi
  _log RUN "$*"
  "$@"
}

sudo_run() { run sudo "$@"; }

have() { command -v "$1" >/dev/null 2>&1; }

# --- Checks ---------------------------------------------------------------------------------

require_not_root() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user ($DEV_USER), not root. Steps use sudo where needed."
}

require_ubuntu() {
  local id="" version_id="" pretty_name="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    id=$(. /etc/os-release && echo "${ID:-}")
    # shellcheck source=/dev/null
    version_id=$(. /etc/os-release && echo "${VERSION_ID:-}")
    # shellcheck source=/dev/null
    pretty_name=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")
  fi
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
# Used by the opt-in compliance step (--with compliance) and by verify.sh --compliance.
check_it_baseline() {
  check warn "Disk encrypted (LUKS)" bash -c 'lsblk -rno FSTYPE | grep -qx crypto_LUKS'
  check warn "Domain joined (realm list)" bash -c 'realm list --name-only | grep -q .'
  check warn "Sophos running (sophos-spl)" systemctl is-active --quiet sophos-spl
  check warn "FortiClient installed" pkg_installed forticlient
  check warn "Intune app installed" pkg_installed intune-portal
  check warn "GNOME installed (fallback session for IT and FortiClient)" pkg_installed gnome-shell
}

# --- Packages -------------------------------------------------------------------------------

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep 'install ok installed' >/dev/null; }

apt_update() { sudo_run apt-get update; }

# Install only the packages that aren't installed yet.
apt_install() {
  local missing=() p
  for p in "$@"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if ((${#missing[@]} == 0)); then
    ok "already installed: $*"
    return 0
  fi
  info "installing: ${missing[*]}"
  sudo_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

# --- Files ----------------------------------------------------------------------------------

# Copy PATH to PATH.bak-<timestamp> if it exists. Usage: backup_file PATH [sudo]
backup_file() {
  local path=$1 use_sudo=${2:-}
  [[ -e "$path" ]] || return 0
  local pre=()
  [[ "$use_sudo" == sudo ]] && pre=(sudo)
  run "${pre[@]}" cp -a "$path" "$path.bak-$(date +%Y%m%d-%H%M%S)"
}

# Install SRC at DEST only if the content differs, backing up the old DEST first.
# Usage: install_file SRC DEST MODE [sudo]
install_file() {
  local src=$1 dest=$2 mode=$3 use_sudo=${4:-}
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    ok "unchanged: $dest"
    return 0
  fi
  local pre=()
  [[ "$use_sudo" == sudo ]] && pre=(sudo)
  backup_file "$dest" "$use_sudo"
  run "${pre[@]}" install -D -m "$mode" "$src" "$dest"
  if is_dry_run; then ok "would write: $dest"; else ok "wrote: $dest"; fi
}

# Print a template with @KEY@ placeholders replaced. Usage: render_template FILE KEY=VALUE...
render_template() {
  local file=$1 content kv
  shift
  content=$(<"$file")
  for kv in "$@"; do
    content=${content//@${kv%%=*}@/${kv#*=}}
  done
  printf '%s\n' "$content"
}

# Render a template and install it. Usage: install_template TEMPLATE DEST MODE sudo|"" KEY=VALUE...
install_template() {
  local tpl=$1 dest=$2 mode=$3 use_sudo=$4 tmp
  shift 4
  tmp=$(mktemp)
  render_template "$tpl" "$@" >"$tmp"
  install_file "$tmp" "$dest" "$mode" "$use_sudo"
  rm -f "$tmp"
}

# Append LINE to FILE unless an identical line exists. Usage: ensure_line FILE LINE [sudo]
ensure_line() {
  local file=$1 line=$2 use_sudo=${3:-}
  if [[ -f "$file" ]] && grep -qxF -- "$line" "$file"; then
    ok "already in $file: $line"
    return 0
  fi
  backup_file "$file" "$use_sudo"
  if is_dry_run; then
    printf '\033[2m[dry-run]\033[0m append to %s: %s\n' "$file" "$line"
    return 0
  fi
  if [[ "$use_sudo" == sudo ]]; then
    printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
  else
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$line" >>"$file"
  fi
  ok "added to $file: $line"
}

# --- Users and groups -----------------------------------------------------------------------

user_in_group() { id -nG "$1" 2>/dev/null | tr ' ' '\n' | grep -xF "$2" >/dev/null; }

# Add a user to a local group. Works for SSSD (AD) users too: the user is looked up through SSSD and
# only /etc/group changes.
add_user_to_group() {
  local user=$1 group=$2
  if ! getent group "$group" >/dev/null; then
    if is_dry_run; then
      sudo_run gpasswd -a "$user" "$group"
      notice "Log out and back in so $user picks up the '$group' group."
      return 0
    fi
    warn "group '$group' doesn't exist; skipping"
    return 0
  fi
  if user_in_group "$user" "$group"; then
    ok "$user already in $group"
    return 0
  fi
  sudo_run gpasswd -a "$user" "$group"
  notice "Log out and back in so $user picks up the '$group' group."
}
