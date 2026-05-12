#!/usr/bin/env bash
# Arch Linux installer — phase 2.
#
# Runs from the live ISO. Prepares disk, installs the base system, then hands
# off to Ansible inside the chroot for everything else.
#
# Usage:  ./2-install/install.sh <hostname>
# Example: ./2-install/install.sh xps   (reads hosts/xps.yml)

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${HERE}/lib/common.sh"
trap 'on_err $LINENO' ERR

# shellcheck source=lib/config.sh
source "${HERE}/lib/config.sh"
# shellcheck source=lib/disk.sh
source "${HERE}/lib/disk.sh"
# shellcheck source=lib/system.sh
source "${HERE}/lib/system.sh"

main() {
    require_root

    local host="${1:-}"
    [[ -n "$host" ]] || die "usage: $0 <host>   (e.g. $0 xps — reads hosts/xps.yml)"

    local host_config="${REPO_ROOT}/hosts/${host}.yml"
    load_host_config "$host_config"

    require_cmd parted sgdisk wipefs cryptsetup mkfs.btrfs btrfs \
                pacstrap genfstab arch-chroot reflector

    log "==========================================="
    log "Arch install — host: ${host}"
    log "Disk:     ${CFG_DISK}"
    log "Hostname: ${CFG_HOSTNAME}"
    log "User:     ${CFG_USERNAME}"
    log "Kernel:   ${CFG_KERNEL}"
    log "==========================================="

    timedatectl set-ntp true || warn "could not enable NTP (continuing)"

    prepare_disk
    run_pacstrap
    write_fstab
    copy_iwd_state
    stage_ansible "$REPO_ROOT"
    run_ansible_in_chroot "$host"
    setup_resolv_symlink
    set_passwords_in_chroot

    log "install complete. Unmount with:  umount -R ${MOUNT_ROOT} && swapoff -a && reboot"
}

main "$@"
