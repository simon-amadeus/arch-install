#!/usr/bin/env bash
# Re-run the Ansible phase on an already-prepared chroot.
#
# Use this when the Ansible step fails but disk prep + pacstrap completed
# successfully. Syncs the latest ansible/ and hosts/ into the chroot then
# reruns the playbook — no reboot, no repartitioning.
#
# Usage: ./bootstrap/rerun-ansible.sh <hostname>
# Example: ./bootstrap/rerun-ansible.sh xps

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${HERE}/lib/common.sh"
trap 'on_err $LINENO' ERR

MOUNT_ROOT="/mnt"

require_root

host="${1:-}"
[[ -n "$host" ]] || die "usage: $0 <host>   (e.g. $0 xps)"

mountpoint -q "${MOUNT_ROOT}" \
    || die "${MOUNT_ROOT} is not mounted — has install.sh run yet?"
[[ -d "${MOUNT_ROOT}/usr/bin" ]] \
    || die "${MOUNT_ROOT}/usr/bin missing — pacstrap has not completed"

log "syncing ansible + host config into chroot"
install -d -m 0700 "${MOUNT_ROOT}/root/install"
rm -rf "${MOUNT_ROOT}/root/install/ansible" "${MOUNT_ROOT}/root/install/hosts"
cp -r "${REPO_ROOT}/ansible" "${MOUNT_ROOT}/root/install/"
cp -r "${REPO_ROOT}/hosts"   "${MOUNT_ROOT}/root/install/"

log "running ansible playbook inside chroot"
arch-chroot "$MOUNT_ROOT" \
    env ANSIBLE_CONFIG=/root/install/ansible/ansible.cfg \
    ansible-playbook \
        -i /root/install/ansible/inventory.ini \
        -e "@/root/install/hosts/${host}.yml" \
        /root/install/ansible/system.yml
