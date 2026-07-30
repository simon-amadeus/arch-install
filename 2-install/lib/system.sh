#!/usr/bin/env bash
# Base system installation: pacstrap, fstab, ansible handoff.

# Packages installed via pacstrap. Keep this list minimal — anything else is
# Ansible's job. We include ansible itself so it's available in the chroot.
BASE_PACKAGES=(
    base base-devel
    btrfs-progs
    cryptsetup
    sudo
    git
    vim
    iwd
    python ansible
    go-yq    # same yq implementation as the live ISO — keep the two in sync
    rsync
)

run_pacstrap() {
    log "pacstrap: refreshing keyring & mirrors"
    pacman-key --init || warn "pacman-key --init failed (continuing)"
    pacman -Sy --noconfirm archlinux-keyring

    log "selecting fastest ${CFG_REFLECTOR_COUNTRY} https mirrors"
    reflector --country "${CFG_REFLECTOR_COUNTRY}" --latest 20 --protocol https --sort rate \
        --save /etc/pacman.d/mirrorlist

    log "running pacstrap (kernel=${CFG_KERNEL}, microcode=${CFG_MICROCODE})"
    pacstrap -K "$MOUNT_ROOT" \
        "${BASE_PACKAGES[@]}" \
        "$CFG_KERNEL" "${CFG_KERNEL}-headers" linux-firmware \
        "$CFG_MICROCODE"
}

write_fstab() {
    log "generating /etc/fstab"
    genfstab -U "$MOUNT_ROOT" >> "${MOUNT_ROOT}/etc/fstab"

    # Add the swapfile entry (genfstab can miss btrfs swapfiles).
    if ! grep -q '/swap/swapfile' "${MOUNT_ROOT}/etc/fstab"; then
        echo "/swap/swapfile none swap defaults 0 0" \
            >> "${MOUNT_ROOT}/etc/fstab"
    fi
}

stage_ansible() {
    local repo_root="$1"
    log "staging repo into ${MOUNT_ROOT}/root/install"

    install -d -m 0700 "${MOUNT_ROOT}/root/install"
    # Copy the whole repo rather than a directory whitelist, so files the
    # later phases need (packages.yml, meta/, …) are staged automatically.
    # Excluded: 1-build (ISO build tree — can contain a multi-GB ISO); the
    # glob also skips dotfiles (.git, .gitignore). Stale destination entries
    # are removed first so re-staging (recover.sh) picks up deletions too.
    local entry name
    for entry in "${repo_root}"/*; do
        name="$(basename "$entry")"
        [[ "$name" == "1-build" ]] && continue
        rm -rf "${MOUNT_ROOT:?}/root/install/${name}"
        cp -r "$entry" "${MOUNT_ROOT}/root/install/"
    done
}

copy_iwd_state() {
    # Carry the live ISO's wifi credentials into the installed system so it
    # can come up online after first boot. Best-effort; ignore if missing.
    [[ -d /var/lib/iwd ]] || return 0
    log "copying iwd state from live ISO into installed system"
    install -d -m 0700 "${MOUNT_ROOT}/var/lib/iwd"
    cp -a /var/lib/iwd/. "${MOUNT_ROOT}/var/lib/iwd/" 2>/dev/null || true
}

run_ansible_in_chroot() {
    local host="$1"
    log "running ansible chroot playbook inside chroot"
    arch-chroot "$MOUNT_ROOT" \
        env ANSIBLE_CONFIG=/root/install/2-install/ansible.cfg \
        ansible-playbook \
            -i /root/install/2-install/inventory.ini \
            -e "@/root/install/hosts/${host}.yml" \
            /root/install/2-install/install.yml
}

setup_resolv_symlink() {
    # arch-chroot bind-mounts the host's /etc/resolv.conf during the Ansible run,
    # blocking Ansible's atomic rename. After the chroot exits the bind mount is
    # released, so we create the symlink here directly on the mounted filesystem.
    log "linking /etc/resolv.conf → systemd-resolved stub"
    ln -sf /run/systemd/resolve/stub-resolv.conf "${MOUNT_ROOT}/etc/resolv.conf"
}

# True when the account already has a usable password (passwd -S field 2 = P).
password_is_set() {
    local status
    status=$(arch-chroot "$MOUNT_ROOT" passwd -S "$1" 2>/dev/null | awk '{print $2}') || true
    [[ "$status" == P* ]]
}

set_passwords_in_chroot() {
    if password_is_set root; then
        log "[1/2] root password already set — skipping"
    else
        log "[1/2] set ROOT password — type twice:"
        arch-chroot "$MOUNT_ROOT" passwd
    fi

    if password_is_set "$CFG_USERNAME"; then
        log "[2/2] password for '${CFG_USERNAME}' already set — skipping"
    else
        log "[2/2] set password for user '${CFG_USERNAME}' — type twice:"
        arch-chroot "$MOUNT_ROOT" passwd "$CFG_USERNAME"
    fi
}
