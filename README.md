# arch-install

Reproducible Arch Linux installer. One declarative config per host, a thin
bash bootstrap for the destructive parts, and Ansible for everything else.

## Workflow

| Phase | What it does | Entry point |
|---|---|---|
| 1. Build | Build a custom live ISO with this repo baked in | [1-build/build.sh](1-build/build.sh) |
| 2. Install | Flash ISO → boot → partition, LUKS, btrfs, pacstrap, chroot Ansible | [2-install/install.sh](2-install/install.sh) |
| 3. First boot | AUR helper, CLI tools, system services, Secure Boot | [3-first-boot/first-boot.sh](3-first-boot/first-boot.sh) |
| 4. Customize | Desktop environment, dotfiles, user packages | [4-customize/customize.sh](4-customize/customize.sh) |

Phase 2 ends with prompts for root and user passwords. The Ansible chroot
playbook (`2-install/install.yml`) runs inside `arch-chroot` as part of this
phase. Phases 3 and 4 run on the booted system and require sudo. Everything
that only needs file writes or `systemctl enable` belongs in phase 2; anything
that needs dbus, logind, or EFI runtime goes in phase 3+.

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
```

## Usage

### 1. Build the ISO

Runs on an existing Arch system. Bakes this repo into the live image.

```bash
./1-build/build.sh arch-install.iso
```

### 2. Flash to USB

```bash
sudo dd if=arch-install.iso of=/dev/<usb> bs=4M oflag=direct status=progress && sync
```

### 3. Install

Boot the ISO — the banner shows the next steps. Connect to wifi (`iwctl`), then:

```bash
~/arch-install/2-install/install.sh xps
```

Wipes the disk, sets up LUKS + btrfs, pacstraps the base system, runs the
chroot Ansible playbook, then prompts for root and user passwords. After
`reboot` you have a bootable encrypted system with the user account ready to
log in.

### 4. First boot

After first boot, connect to wifi and run:

```bash
~/arch-install/3-first-boot/first-boot.sh xps
```

Installs paru, CLI tools, audio (pipewire), and sets up system services
(bluetooth, firewall, snapshots). Use `--tags <tag>` to run a single step —
valid tags: `aur`, `cli`, `audio`, `bluetooth`, `firewall`, `printing`,
`usb_automount`, `snapshots`, `secure_boot`.

### 5. Customize

```bash
~/arch-install/4-customize/customize.sh xps
```

Installs the sway desktop and optionally checks out your dotfiles
(bare git repo, work-tree `~`) and installs official-repo user packages.
Valid tags: `desktop`, `dotfiles`, `packages`.

If `features.packages` is true and an AUR package list exists at
`~/.config/packages/aur_pkglist.txt`, `customize.sh` then hands off to
`4-customize/aur-install.sh`. AUR installs are interactive on purpose —
paru shows each PKGBUILD before building so a typosquatted or hijacked
package can be caught before it runs as your user. The same script can
be re-run later by itself any time the AUR package list changes.

### Secure Boot

The entire Secure Boot flow runs in phase 3 (booted system). Sequence:

1. Verify the system boots normally (`features.secure_boot: false`)
2. Boot into UEFI firmware → Secure Boot → delete all existing keys (enters Setup Mode)
3. Boot back into the installed system
4. Set `features.secure_boot: true` in the host config
5. Run:

```bash
~/arch-install/3-first-boot/first-boot.sh xps --tags secure_boot
```

This creates the sbctl keys, signs the UKI, and enrolls the keys into firmware
in one pass. The `--microsoft` flag is included so hardware with Microsoft-signed
option ROMs (common on XPS) continues to work. The pacman hook bundled with sbctl
re-signs automatically on every kernel or bootloader update.

### Recovery: re-run after a failed install

If phase 2 fails mid-run, the disk is already prepared — fix the issue and
re-run only the Ansible playbook without touching the disk:

```bash
./2-install/recover.sh xps [--tags <tag>]
```

Valid phase 2 tags: `locale`, `time`, `hostname`, `network`, `dns`,
`mkinitcpio`, `bootloader`, `users`, `zsh`, `services`, `autologin`, `stage`.
