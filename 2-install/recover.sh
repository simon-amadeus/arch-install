#!/usr/bin/env bash
# Re-run the Ansible phase on an already-prepared chroot.
#
# Use this when the Ansible step fails but disk prep + pacstrap completed
# successfully. Syncs the latest 2-install/ and hosts/ into the chroot then
# reruns the playbook — no reboot, no repartitioning.
#
# Usage: ./2-install/recover.sh <hostname>
# Example: ./2-install/recover.sh xps

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${HERE}/lib/common.sh"
trap 'on_err $LINENO' ERR

# shellcheck source=lib/config.sh
source "${HERE}/lib/config.sh"
# shellcheck source=lib/system.sh
source "${HERE}/lib/system.sh"

MOUNT_ROOT="/mnt"

require_root

host="${1:-}"
[[ -n "$host" ]] || die "usage: $0 <host>   (e.g. $0 xps)"

host_config="${REPO_ROOT}/hosts/${host}.yml"
load_host_config "$host_config"

mountpoint -q "${MOUNT_ROOT}" \
    || die "${MOUNT_ROOT} is not mounted — has install.sh run yet?"
[[ -d "${MOUNT_ROOT}/usr/bin" ]] \
    || die "${MOUNT_ROOT}/usr/bin missing — pacstrap has not completed"

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
        /root/install/2-install/install.yml

setup_resolv_symlink
set_passwords_in_chroot

log "recover complete. Unmount with:  umount -R ${MOUNT_ROOT} && swapoff -a && reboot"
