#!/usr/bin/env bash
# First-boot setup — phase 3. Runs on the booted system as the primary user.
# Sets up a working minimal system: AUR helper, CLI tools, system services.
#
# Usage:   ./3-first-boot/first-boot.sh <hostname>
# Example: ./3-first-boot/first-boot.sh xps

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

echo "=== first-boot — host: ${host} ==="

ANSIBLE_CONFIG="${HERE}/ansible.cfg" \
ansible-playbook -K \
    -i "${HERE}/inventory.ini" \
    -e "@${host_config}" \
    "${HERE}/first-boot.yml" \
    "$@"
