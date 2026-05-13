#!/usr/bin/env bash
# Personal environment — phase 4. Runs after first-boot setup.
# Installs the desktop environment, personal dotfiles, and user packages.
#
# Usage:   ./4-customize/customize.sh <hostname>
# Example: ./4-customize/customize.sh xps

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

echo "=== customize — host: ${host} ==="

ANSIBLE_CONFIG="${HERE}/ansible.cfg" \
ansible-playbook \
    -i "${HERE}/inventory.ini" \
    -e "@${host_config}" \
    "${HERE}/customize.yml" \
    "$@"
