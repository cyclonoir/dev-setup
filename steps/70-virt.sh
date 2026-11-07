#!/usr/bin/env bash
# Step: KVM/libvirt for Windows test VMs (Windows 11 needs swtpm for the TPM and ovmf for UEFI).
# Whether the CPU's virtualization is switched on (kvm-ok) is for verify.sh to report.

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

# Add DEV_USER to a local group. Fine for SSSD (AD) users: only /etc/group and /etc/gshadow change.
add_user_to_group() {
  local group=$1
  if user_in_group "$DEV_USER" "$group"; then
    ok "$DEV_USER already in $group"
    return 0
  fi
  backup_file /etc/group sudo
  backup_file /etc/gshadow sudo
  sudo_run gpasswd -a "$DEV_USER" "$group"
  notice "Log out and back in so $DEV_USER picks up the '$group' group."
}

apt_install "${PKGS_VIRT[@]}"
add_user_to_group libvirt
add_user_to_group kvm
