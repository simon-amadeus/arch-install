#!/usr/bin/env bash
# Run the user-space Ansible playbook on an installed, booted system.
#
# Run this after first boot, logged in as the primary user or as root.
# It will prompt once for the sudo password (-K).
#
# Usage: ./bootstrap/setup-user.sh <hostname>
# Example: ./bootstrap/setup-user.sh xps

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

host="${1:-}"
[[ -n "$host" ]] || { echo "usage: $0 <host>   (e.g. $0 xps)"; exit 1; }
shift

host_config="${REPO_ROOT}/hosts/${host}.yml"
[[ -f "$host_config" ]] || { echo "error: hosts/${host}.yml not found"; exit 1; }

command -v ansible-playbook >/dev/null \
    || { echo "error: ansible-playbook not found — is ansible installed?"; exit 1; }

echo "=== user setup — host: ${host} ==="

ANSIBLE_CONFIG="${REPO_ROOT}/ansible/ansible.cfg" \
ansible-playbook \
    -K \
    -i "${REPO_ROOT}/ansible/inventory.ini" \
    -e "@${host_config}" \
    "${REPO_ROOT}/ansible/user.yml" \
    "$@"
