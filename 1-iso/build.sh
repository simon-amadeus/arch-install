#!/usr/bin/env bash
# Build a custom Arch ISO that bakes in:
#   - this repo at /root/arch-install/
#   - extra packages: ansible, python, yq, git (so install.sh runs immediately)
#   - airootfs overlay from iso/airootfs/
#
# Usage:  ./iso/build.sh [output.iso]

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

ARCHISO_SOURCE="/usr/share/archiso/configs/releng"
ISO_NAME="${1:-arch-install.iso}"

TMP_DIR="${REPO_ROOT}/.tmp-iso"
WORK_DIR="${TMP_DIR}/work"
OUT_DIR="${TMP_DIR}/out"
PROFILE_DIR="${TMP_DIR}/profile"

cleanup() {
    if [[ -d "$TMP_DIR" ]]; then
        echo "cleaning up ${TMP_DIR}"
        sudo rm -rf "$TMP_DIR"
    fi
}
trap cleanup EXIT

command -v mkarchiso >/dev/null 2>&1 || {
    echo "installing archiso..."
    sudo pacman -S --needed --noconfirm archiso
}

mkdir -p "$TMP_DIR"
cp -r "$ARCHISO_SOURCE" "$PROFILE_DIR"

# Add packages we need at first boot of the live ISO
{
    echo "ansible"
    echo "python"
    echo "go-yq"          # provides /usr/bin/yq
    echo "git"
    echo "reflector"
} >> "${PROFILE_DIR}/packages.x86_64"

# Stage the repo into the live ISO under /root/arch-install
mkdir -p "${PROFILE_DIR}/airootfs/root/arch-install"
rsync -a \
    --exclude='.git' \
    --exclude='.tmp-iso' \
    --exclude='legacy' \
    "${REPO_ROOT}/" "${PROFILE_DIR}/airootfs/root/arch-install/"

# Layer our airootfs overlay (vconsole, autologin banner, etc.)
if [[ -d "${HERE}/airootfs" ]]; then
    rsync -a "${HERE}/airootfs/" "${PROFILE_DIR}/airootfs/"
fi

echo "building ISO..."
sudo mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "$PROFILE_DIR"

sudo mv "${OUT_DIR}"/*.iso "${REPO_ROOT}/${ISO_NAME}"
sudo chown "$(id -u):$(id -g)" "${REPO_ROOT}/${ISO_NAME}"
echo "done: ${REPO_ROOT}/${ISO_NAME}"
