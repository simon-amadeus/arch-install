#!/usr/bin/env bash
# User environment setup. Runs on the booted system as the primary user.
#
# Run after first boot, connected to wifi. Prompts once for sudo password (-K).
#
# Usage: ./3-setup/setup.sh <hostname>
# Example: ./3-setup/setup.sh xps

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

host="${1:-}"
[[ -n "$host" ]] || { echo "usage: $0 <host>   (e.g. $0 xps)"; exit 1; }
shift

host_config="${REPO_ROOT}/hosts/${host}.yml"
[[ -f "$host_config" ]] || { echo "error: hosts/${host}.yml not found"; exit 1; }

command -v ansible-playbook >/dev/null \
    || { echo "error: ansible-playbook not found — is ansible installed?"; exit 1; }

echo "=== setup — host: ${host} ==="

ANSIBLE_CONFIG="${REPO_ROOT}/ansible/ansible.cfg" \
ansible-playbook \
    -K \
    -i "${REPO_ROOT}/ansible/inventory.ini" \
    -e "@${host_config}" \
    "${REPO_ROOT}/ansible/setup.yml" \
    "$@"
