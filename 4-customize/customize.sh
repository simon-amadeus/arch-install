#!/usr/bin/env bash
# Personal environment — phase 4. Runs after first-boot setup.
#
# Two passes:
#   1. ansible-playbook (system-level config: desktop, dotfiles, official
#      pacman packages). Uses -K to prompt for the sudo password.
#   2. aur-install.sh (interactive AUR install — paru shows each PKGBUILD).
#      Only runs when features.packages is true and an AUR list exists.
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
ansible-playbook -K \
    -i "${HERE}/inventory.ini" \
    -e "@${host_config}" \
    "${HERE}/customize.yml" \
    "$@"

# AUR pass — interactive, runs in the user's TTY so paru can show PKGBUILDs.
want_aur=$(yq -r '.features.packages // false' "$host_config")
aur_list="${HOME}/.config/packages/aur_pkglist.txt"
if [[ "$want_aur" == "true" && -f "$aur_list" ]]; then
    echo
    echo "=== AUR packages (interactive — paru will show each PKGBUILD) ==="
    "${HERE}/aur-install.sh"
fi
