# arch-install

Reproducible Arch Linux installer. One declarative config per host, a thin
bash bootstrap for the destructive parts, and Ansible for everything else.

## Architecture

| Phase | What it does | Tool |
|---|---|---|
| 0. ISO | Build a custom live ISO with this repo + ansible baked in | [iso/build.sh](iso/build.sh) |
| 1. Bootstrap | Partition, LUKS, btrfs subvolumes, pacstrap base | [bootstrap/install.sh](bootstrap/install.sh) |
| 2. System | Locale, time, hostname, network, UKI, systemd-boot, user | [ansible/system.yml](ansible/system.yml) |
| 3. User *(not yet implemented)* | Dotfiles, AUR helper, GUI apps, desktop env | `ansible/user.yml` (TODO) |

## Disk layout

One LUKS2 container, btrfs inside with subvolumes — swap lives as a btrfs
swapfile, no separate plaintext swap partition.

```
/dev/<disk>
├── p1  ESP (FAT32, 1 GiB)              → /boot
└── p2  LUKS2 ──→ btrfs
                  ├── @           → /
                  ├── @home       → /home
                  ├── @snapshots  → /.snapshots
                  ├── @var_log    → /var/log
                  ├── @var_cache  → /var/cache
                  └── @swap       → /swap (contains swapfile)
```

Boot is via systemd-boot auto-discovering Unified Kernel Images
(`/boot/EFI/Linux/arch-<kernel>.efi`). No hand-written loader entries.

## Per-host config

Everything that varies between machines lives in `hosts/<name>.yml`. Add a
new machine by adding a new file there — no code changes.

See [hosts/xps.yml](hosts/xps.yml) for the schema.

## Usage

### Build the ISO

```bash
./iso/build.sh arch-install.iso
```

### Flash to USB

```bash
sudo dd if=arch-install.iso of=/dev/<usb> bs=16M oflag=direct status=progress
```

### Install

Boot the ISO, connect to wifi (`iwctl`), then:

```bash
~/arch-install/bootstrap/install.sh xps
```

That runs phase 1 (bootstrap) → phase 2 (Ansible inside the chroot) →
prompts for root + user passwords. After `reboot` you have a bootable
encrypted system with the user account ready to log in.

### Test in qemu before flashing USB

```bash
./iso/build.sh
./tests/vm.sh install        # boots ISO with a fresh 32G qcow2, drive install manually
./tests/vm.sh boot           # boots the disk after install (no ISO) to verify
./tests/vm.sh clean          # nuke the test disk + nvram
```

Requires `qemu-full` and `edk2-ovmf`.

### Re-running after a failure

If the Ansible playbook fails, the disk is already prepared — fix the
broken task and re-run only the playbook (no need to repartition):

```bash
arch-chroot /mnt ansible-playbook \
    -i /root/install/ansible/inventory.ini \
    -e @/root/install/hosts/xps.yml \
    /root/install/ansible/system.yml \
    --tags <failed-tag>     # optional: locale, network, bootloader, ...
```

## Status

Skeleton. The phase 1 + minimal phase 2 path exists. Still to do:

- [ ] phase 3 (user.yml): dotfiles via chezmoi, AUR helper, GUI apps
- [ ] desktop role (sway)
- [ ] optional service roles (audio, bluetooth, printing, firewalld)
- [ ] snapper config + pre-pacman snapshots
- [ ] TPM2 auto-unlock via `systemd-cryptenroll`
- [ ] qemu-based smoke test in `tests/`

The original installer is preserved in [legacy/](legacy/) for reference
during the rebuild.
