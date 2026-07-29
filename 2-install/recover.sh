#!/usr/bin/env bash
# Re-run the Ansible phase on an already-prepared chroot.
#
# Use this when the Ansible step fails but disk prep + pacstrap completed
# successfully. Syncs the latest 2-install/ and hosts/ into the chroot then
# reruns the playbook — no repartitioning. Works from a fresh live session
# too: if /mnt is not mounted it re-opens the LUKS container (by label) and
# re-mounts the subvolumes first.
#
# Extra arguments are passed through to ansible-playbook.
#
# Usage: ./2-install/recover.sh <hostname> [ansible args]
# Example: ./2-install/recover.sh xps --tags dns

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

require_root

host="${1:-}"
[[ -n "$host" ]] || die "usage: $0 <host> [ansible args]   (e.g. $0 xps --tags dns)"
shift

host_config="${REPO_ROOT}/hosts/${host}.yml"
load_host_config "$host_config"

# Fresh live session (e.g. rebooted back into the ISO): reassemble the
# LUKS container and subvolume mounts. Partitions are found by the labels
# install.sh created (FAT label ESP, LUKS2 label cryptsystem).
if ! mountpoint -q "${MOUNT_ROOT}"; then
    log "${MOUNT_ROOT} is not mounted — reassembling from disk"
    ESP_PART="$(blkid -L ESP || true)"
    LUKS_PART="$(blkid -L cryptsystem || true)"
    [[ -n "$ESP_PART" && -n "$LUKS_PART" ]] \
        || die "no partitions labelled ESP/cryptsystem found — has install.sh completed disk prep?"
    if [[ ! -e "/dev/mapper/${CRYPT_NAME}" ]]; then
        log "opening LUKS container on ${LUKS_PART} (passphrase prompt)"
        cryptsetup open "$LUKS_PART" "$CRYPT_NAME"
    fi
    btrfs_mount_all
fi

[[ -d "${MOUNT_ROOT}/usr/bin" ]] \
    || die "${MOUNT_ROOT}/usr/bin missing — pacstrap has not completed; re-run install.sh"

log "syncing repo into chroot"
install -d -m 0700 "${MOUNT_ROOT}/root/install"
for d in 2-install 3-first-boot 4-customize hosts; do
    rm -rf "${MOUNT_ROOT}/root/install/${d}"
    [[ -d "${REPO_ROOT}/${d}" ]] && cp -r "${REPO_ROOT}/${d}" "${MOUNT_ROOT}/root/install/"
done
[[ -f "${REPO_ROOT}/README.md" ]] && cp "${REPO_ROOT}/README.md" "${MOUNT_ROOT}/root/install/" || true

log "running ansible playbook inside chroot"
arch-chroot "$MOUNT_ROOT" \
    env ANSIBLE_CONFIG=/root/install/2-install/ansible.cfg \
    ansible-playbook \
        -i /root/install/2-install/inventory.ini \
        -e "@/root/install/hosts/${host}.yml" \
        /root/install/2-install/install.yml \
        "$@"

setup_resolv_symlink
set_passwords_in_chroot

log "recover complete. Unmount with:  swapoff -a && umount -R ${MOUNT_ROOT} && reboot"
