#!/usr/bin/env bash
# Step: KVM/libvirt for Windows test VMs (Windows 11 needs swtpm for the TPM and ovmf for UEFI).

# shellcheck source=../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

apt_install "${PKGS_VIRT[@]}"

if have kvm-ok; then
  if kvm-ok >/dev/null 2>&1; then
    ok "KVM acceleration available"
  else
    warn "KVM acceleration unavailable. Turn on AMD-V/SVM in the BIOS."
  fi
fi

add_user_to_group "$DEV_USER" libvirt
add_user_to_group "$DEV_USER" kvm
