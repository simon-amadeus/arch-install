#!/usr/bin/env bash
# QEMU smoke test for the installer.
#
# Modes:
#   ./tests/vm.sh install       boot the custom ISO with a fresh disk and run the installer interactively
#   ./tests/vm.sh boot          boot from the disk after install (no ISO attached)
#   ./tests/vm.sh clean         delete the test disk + nvram
#
# Requirements (Arch host):
#   sudo pacman -S --needed qemu-full edk2-ovmf
#
# This script is intended for use on an Arch host where the ISO was built with
# `iso/build.sh`. The disk image is 32 GiB and lives next to the repo.

set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HERE}/.." && pwd)"

ISO_PATH="${REPO_ROOT}/arch-install.iso"
DISK_PATH="${REPO_ROOT}/.tmp-vm/disk.qcow2"
OVMF_VARS_PATH="${REPO_ROOT}/.tmp-vm/OVMF_VARS.fd"
DISK_SIZE="32G"
RAM="4G"
CORES="4"

OVMF_CODE_CANDIDATES=(
    /usr/share/edk2/x64/OVMF_CODE.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd
    /usr/share/OVMF/OVMF_CODE.fd
)
OVMF_VARS_CANDIDATES=(
    /usr/share/edk2/x64/OVMF_VARS.4m.fd
    /usr/share/edk2-ovmf/x64/OVMF_VARS.fd
    /usr/share/OVMF/OVMF_VARS.fd
)

die() { echo "fatal: $*" >&2; exit 1; }

find_first() {
    for p in "$@"; do
        [[ -f "$p" ]] && { echo "$p"; return 0; }
    done
    return 1
}

ensure_setup() {
    command -v qemu-system-x86_64 >/dev/null \
        || die "qemu-system-x86_64 not found. Install with: sudo pacman -S qemu-full"

    OVMF_CODE=$(find_first "${OVMF_CODE_CANDIDATES[@]}") \
        || die "OVMF firmware not found. Install with: sudo pacman -S edk2-ovmf"
    OVMF_VARS_TEMPLATE=$(find_first "${OVMF_VARS_CANDIDATES[@]}") \
        || die "OVMF vars template not found"

    mkdir -p "$(dirname "$DISK_PATH")"

    # Per-VM copy of OVMF vars (firmware nvram lives in this file)
    if [[ ! -f "$OVMF_VARS_PATH" ]]; then
        cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_PATH"
        echo "created firmware nvram at ${OVMF_VARS_PATH}"
    fi

    if [[ ! -f "$DISK_PATH" ]]; then
        qemu-img create -f qcow2 "$DISK_PATH" "$DISK_SIZE"
        echo "created disk at ${DISK_PATH} (${DISK_SIZE})"
    fi
}

kvm_args() {
    if [[ -r /dev/kvm ]]; then
        echo "-enable-kvm -cpu host"
    else
        echo "-cpu max"
    fi
}

base_args() {
    cat <<EOF
-machine q35,smm=on
-m ${RAM}
-smp ${CORES}
$(kvm_args)
-drive if=pflash,format=raw,readonly=on,file=${OVMF_CODE}
-drive if=pflash,format=raw,file=${OVMF_VARS_PATH}
-drive file=${DISK_PATH},if=virtio,format=qcow2
-netdev user,id=net0
-device virtio-net,netdev=net0
-vga virtio
-display gtk,gl=on
EOF
}

cmd_install() {
    [[ -f "$ISO_PATH" ]] || die "ISO not found at ${ISO_PATH}. Run iso/build.sh first."
    ensure_setup
    echo "booting ISO (${ISO_PATH}) with disk ${DISK_PATH}"
    # shellcheck disable=SC2046
    exec qemu-system-x86_64 \
        $(base_args) \
        -cdrom "$ISO_PATH" \
        -boot order=d
}

cmd_boot() {
    ensure_setup
    [[ -s "$DISK_PATH" ]] || die "disk image is empty — run \`$0 install\` first"
    echo "booting from disk ${DISK_PATH}"
    # shellcheck disable=SC2046
    exec qemu-system-x86_64 $(base_args)
}

cmd_clean() {
    rm -rf "$(dirname "$DISK_PATH")"
    echo "removed VM state"
}

case "${1:-}" in
    install) cmd_install ;;
    boot)    cmd_boot ;;
    clean)   cmd_clean ;;
    *)       die "usage: $0 {install|boot|clean}" ;;
esac
