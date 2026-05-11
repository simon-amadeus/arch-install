# arch-install

Reproducible Arch Linux installer. One declarative config per host, a thin
bash bootstrap for the destructive parts, and Ansible for everything else.

## Architecture

| Phase | What it does | Tool |
|---|---|---|
| 0. ISO | Build a custom live ISO with this repo + ansible baked in | [iso/build.sh](iso/build.sh) |
| 1. Bootstrap | Partition, LUKS, btrfs subvolumes, pacstrap base | [bootstrap/install.sh](bootstrap/install.sh) |
| 2. System | Locale, time, hostname, network, UKI, systemd-boot, user account, bluetooth, firewall, autologin, snapshots, Secure Boot signing | [ansible/system.yml](ansible/system.yml) |
| 3. User | AUR helper, audio (pipewire + linger), sway desktop, dotfiles, Secure Boot enrollment | [ansible/user.yml](ansible/user.yml) |

Phase 2 runs inside `arch-chroot`. Phase 3 runs on the booted system and
requires sudo (`-K`). Everything that only needs file writes or `systemctl
enable` belongs in phase 2; anything that needs dbus, logind, or EFI runtime
goes in phase 3.

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
new machine by adding a new file there — no code changes needed.

See [hosts/xps.yml](hosts/xps.yml) for the full schema. Key fields:

```yaml
hostname, reflector_country, timezone, locale, keymap, console_font
disk: { device, esp_size, swapfile_size }
kernel, microcode
user: { name, shell, groups, dotfiles_repo }
features: { audio, bluetooth, firewalld, desktop, snapshots, secure_boot, tpm2_unlock }
network: { dns: { primary, fallback }, dns_over_tls, dnssec }
```

## Usage

### Build the ISO

```bash
./iso/build.sh arch-install.iso
```

### Flash to USB

```bash
sudo dd if=arch-install.iso of=/dev/<usb> bs=16M oflag=direct status=progress
```

### Install (phases 1 + 2)

Boot the ISO, connect to wifi (`iwctl`), then:

```bash
~/arch-install/bootstrap/install.sh xps
```

Wipes the disk, sets up LUKS + btrfs, pacstraps the base system, runs the
system Ansible playbook inside the chroot, then prompts for root and user
passwords. After `reboot` you have a bootable encrypted system with the user
account ready to log in.

### User environment (phase 3)

After first boot, connect to wifi and run:

```bash
~/arch-install/bootstrap/setup-user.sh xps
```

Installs paru, the pipewire stack, the sway desktop, and checks out your
dotfiles (bare git repo, work-tree `~`). Use `--tags <tag>` to run a single
step — valid tags: `aur`, `audio`, `desktop`, `dotfiles`, `secure_boot`.

### Secure Boot

Set `features.secure_boot: true` in the host config before running the
installer. Phase 2 creates the sbctl keys and signs the UKI; the pacman hook
bundled with sbctl re-signs on every kernel update.

Enrollment requires the UEFI to be in Setup Mode (clear all Secure Boot keys
in firmware settings), then on the booted system:

```bash
~/arch-install/bootstrap/setup-user.sh xps --tags secure_boot
```

Enable `features.tpm2_unlock` after Secure Boot is established.

### Re-running after a failure

If phase 2 fails mid-run, the disk is already prepared — fix the issue and
re-run only the Ansible playbook:

```bash
./bootstrap/rerun-ansible.sh xps [--tags <tag>]
```

Valid phase 2 tags: `locale`, `time`, `hostname`, `network`, `mkinitcpio`,
`bootloader`, `users`, `services`, `bluetooth`, `firewall`, `autologin`,
`snapshots`, `secure_boot`.
