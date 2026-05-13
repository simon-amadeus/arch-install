#!/usr/bin/env bash
# Disk preparation: wipe, partition, LUKS, btrfs subvolumes, mount.
#
# Globals expected (set by config.sh):
#   CFG_DISK, CFG_ESP_SIZE, CFG_SWAPFILE_SIZE
# Globals exported by this lib:
#   ESP_PART, LUKS_PART      — kernel device paths for the partitions
#   CRYPT_NAME=cryptroot     — LUKS device-mapper name

CRYPT_NAME="cryptroot"
MOUNT_ROOT="/mnt"

wipe_disk() {
    log "wiping ${CFG_DISK} (signatures + GPT)"
    wipefs --all --force "$CFG_DISK"
    sgdisk --zap-all "$CFG_DISK"
    partprobe "$CFG_DISK"
}

partition_disk() {
    log "creating GPT layout on ${CFG_DISK}"
    # 1: ESP (FAT32), 2: LUKS container (rest of disk)
    sgdisk \
        --new=1:0:+"${CFG_ESP_SIZE}" --typecode=1:ef00 --change-name=1:ESP \
        --new=2:0:0                  --typecode=2:8309 --change-name=2:cryptsystem \
        "$CFG_DISK"
    partprobe "$CFG_DISK"

    ESP_PART=$(partition_path 1)
    LUKS_PART=$(partition_path 2)
    wait_for_path "$ESP_PART"
    wait_for_path "$LUKS_PART"
    log "partitions: ESP=${ESP_PART} LUKS=${LUKS_PART}"
}

format_esp() {
    log "formatting ${ESP_PART} as FAT32"
    mkfs.fat -F32 -n ESP "$ESP_PART"
}

luks_format() {
    log "creating LUKS2 container on ${LUKS_PART} (interactive passphrase)"
    # Interactive passphrase prompt — only one ever, no scripted input.
    cryptsetup luksFormat \
        --type luks2 \
        --pbkdf argon2id \
        --label cryptsystem \
        --verify-passphrase \
        "$LUKS_PART"

    log "opening LUKS container as ${CRYPT_NAME}"
    cryptsetup open "$LUKS_PART" "$CRYPT_NAME"
    wait_for_path "/dev/mapper/${CRYPT_NAME}"
}

btrfs_create_subvolumes() {
    local dev="/dev/mapper/${CRYPT_NAME}"

    log "creating btrfs filesystem on ${dev}"
    mkfs.btrfs --force --label system "$dev"

    log "creating btrfs subvolumes"
    mount "$dev" "$MOUNT_ROOT"
    btrfs subvolume create "${MOUNT_ROOT}/@"
    btrfs subvolume create "${MOUNT_ROOT}/@home"
    btrfs subvolume create "${MOUNT_ROOT}/@snapshots"
    btrfs subvolume create "${MOUNT_ROOT}/@var_log"
    btrfs subvolume create "${MOUNT_ROOT}/@var_cache"
    btrfs subvolume create "${MOUNT_ROOT}/@swap"
    umount "$MOUNT_ROOT"
}

btrfs_mount_all() {
    local dev="/dev/mapper/${CRYPT_NAME}"
    # No discard=async: LUKS was opened without --allow-discards, so any
    # discard from btrfs would be dropped at the LUKS layer anyway. Trading
    # SSD wear-levelling efficiency for the privacy gain of not exposing
    # used/free block boundaries.
    local opts="noatime,compress=zstd:1,ssd,space_cache=v2"

    log "mounting btrfs subvolumes"
    mount -o "${opts},subvol=@" "$dev" "$MOUNT_ROOT"
    mkdir -p \
        "${MOUNT_ROOT}/home" \
        "${MOUNT_ROOT}/.snapshots" \
        "${MOUNT_ROOT}/var/log" \
        "${MOUNT_ROOT}/var/cache" \
        "${MOUNT_ROOT}/swap" \
        "${MOUNT_ROOT}/boot"
    mount -o "${opts},subvol=@home"      "$dev" "${MOUNT_ROOT}/home"
    mount -o "${opts},subvol=@snapshots" "$dev" "${MOUNT_ROOT}/.snapshots"
    mount -o "${opts},subvol=@var_log"   "$dev" "${MOUNT_ROOT}/var/log"
    mount -o "${opts},subvol=@var_cache" "$dev" "${MOUNT_ROOT}/var/cache"

    # Swap subvol must be mounted with no compression / no CoW for the swapfile.
    mount -o "noatime,subvol=@swap" "$dev" "${MOUNT_ROOT}/swap"

    mount "$ESP_PART" "${MOUNT_ROOT}/boot"
}

create_swapfile() {
    local target="${MOUNT_ROOT}/swap/swapfile"
    log "creating ${CFG_SWAPFILE_SIZE} btrfs swapfile at ${target}"
    btrfs filesystem mkswapfile --size "$CFG_SWAPFILE_SIZE" "$target"
    swapon "$target"
}

prepare_disk() {
    confirm "About to DESTROY all data on ${CFG_DISK}"
    wipe_disk
    partition_disk
    format_esp
    luks_format
    btrfs_create_subvolumes
    btrfs_mount_all
    create_swapfile
    log "disk preparation complete"
}
