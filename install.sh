#!/bin/bash

# Ensure the script is running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root." >&2
    exit 1
fi

# Get the absolute path of the current directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Specify the log file path relative to the script's directory
LOG_FILE="$SCRIPT_DIR/arch_install.log"

# Function to log messages to both console and log file
log() {
    local message="$1"
    echo "$message" | tee -a "$LOG_FILE"
}

# Function to handle errors
handle_error() {
    local error_message="$1"
    log "Error: $error_message"
    exit 1
}

# Initialize log file
touch "$LOG_FILE"
log "Starting Arch Linux Installation Script..."

# Source the installation variables
source install.env || {
    log "Failed to source install.env."
    exit 1
}

# Check for required installation variables
check_required_variables() {
    # Required variables list
    local required_vars=("KEYMAP_INSTALL" "FONT_INSTALL" "TIMEZONE_INSTALL" 
                         "LOCALE_INSTALL" "ADDITIONAL_LOCALES_INSTALL"
                         "HOSTNAME_INSTALL" "USERNAME" 
                         "DISK" "BOOT_PARTITION_SIZE" "ROOT_PARTITION_END" 
                         "SWAP_PARTITION_END")

    for var_name in "${required_vars[@]}"; do
        if [ -z "${!var_name}" ]; then  # Check if variable is unset or empty
            log "Error: Required variable ${var_name} is not set."
            exit 1
        else
            log "${var_name} is set to ${!var_name}."
        fi
    done
}

check_required_variables

# Function to check and connect to Wi-Fi
function connect_to_wifi {
    if ! ping -c 1 archlinux.org &> /dev/null; then
        log "Starting Wi-Fi connection attempt."
        [ -z "$WIFI_SSID" ] && read -p "Enter Wi-Fi SSID: " WIFI_SSID
        [ -z "$WIFI_PASSPHRASE" ] && read -sp "Enter Wi-Fi passphrase: " WIFI_PASSPHRASE

        iwctl --passphrase "$WIFI_PASSPHRASE" station wlan0 connect "$WIFI_SSID" || {
            log "Failed to connect to Wi-Fi network '$WIFI_SSID'."
            return 1
        }
        log "Connected to Wi-Fi network '$WIFI_SSID'."
        log "Waiting 10 seconds for network connection to stabilize..."
        sleep 10
    else
        log "Internet connection is already active."
    fi
}

# Check and connect to Wi-Fi
connect_to_wifi || exit 1

# Update the system clock
timedatectl set-ntp true || exit 1
log "System clock synchronized with NTP."

# Set the mirrorlist to Germany
log "Setting mirrorlist to Germany..."
reflector --country Germany --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || exit 1
log "Mirrorlist set to Germany."

# Disk Partitioning
log "WARNING: This will destroy all data on the disk $DISK and remove existing partition structures."
read -rp "Are you sure you want to clean the disk $DISK? (type 'YES' to confirm): " confirmation

if [[ "$confirmation" != "YES" ]]; then
    log "Disk cleaning aborted. No changes have been made."
    exit 1
fi

# Wipe the disk
wipe_disk() {
    dd if=/dev/zero of="$1" bs=1M count=1000 conv=notrunc status=progress || exit 1
    end=$(($(blockdev --getsz "$1") - 100))
    dd if=/dev/zero of="$1" bs=512 count=100 seek=$end conv=notrunc status=progress || exit 1
    log "The disk $1 has been cleaned."
}

wipe_disk "$DISK"

# Function to determine the correct partition naming scheme
get_partition_suffix() {
    if [[ "$DISK" =~ nvme ]]; then
        PART_SUFFIX="p"
    else
        PART_SUFFIX=""
    fi
    log "Using partition suffix '$PART_SUFFIX' for disk '$DISK'."
}

get_partition_suffix

# Create GPT partition table
log "Creating GPT partition table..."
parted --script "${DISK}" mklabel gpt || exit 1

# Create partitions
parted --script --align optimal "${DISK}" mkpart ESP fat32 1MiB "${BOOT_PARTITION_SIZE}" || exit 1
parted --script "${DISK}" set 1 boot on || exit 1
parted --script "${DISK}" set 1 esp on || exit 1

parted --script --align optimal "${DISK}" mkpart primary ext4 "${BOOT_PARTITION_SIZE}" "${ROOT_PARTITION_END}" || exit 1
parted --script --align optimal "${DISK}" mkpart primary linux-swap "${ROOT_PARTITION_END}" "${SWAP_PARTITION_END}" || exit 1
parted --script --align optimal "${DISK}" mkpart primary ext4 "${SWAP_PARTITION_END}" 100% || exit 1

# Format the partitions
mkfs.fat -F32 "${DISK}${PART_SUFFIX}1" || exit 1  # ESP
log "Disk partitioning complete."

# Disk Encryption (LUKS)
log "Preparing disk encryption..."
cryptsetup luksFormat --type luks2 "${DISK}${PART_SUFFIX}2" -d - || exit 1
cryptsetup open "${DISK}${PART_SUFFIX}2" cryptroot -d - || exit 1
mkfs.ext4 /dev/mapper/cryptroot || exit 1

# Mount the root partition
mount /dev/mapper/cryptroot /mnt || exit 1

# Create the directory structure
mkdir /mnt/{boot,home} || exit 1

# Create a keyfile for the home partition and add it to the LUKS slot
mkdir /mnt/etc || exit 1
dd if=/dev/urandom of=/mnt/etc/crypthomekey bs=512 count=8 status=none || exit 1
chmod 600 /mnt/etc/crypthomekey || exit 1
cryptsetup luksAddKey "${DISK}${PART_SUFFIX}4" /mnt/etc/crypthomekey

# Encrypt and open the home partition using the keyfile
cryptsetup -d /mnt/etc/crypthomekey luksFormat --type luks2 "${DISK}${PART_SUFFIX}4" || exit 1
cryptsetup -d /mnt/etc/crypthomekey open "${DISK}${PART_SUFFIX}4" crypthome || exit 1
mkfs.ext4 /dev/mapper/crypthome || exit 1

# Set up and turn on swap
mkswap "${DISK}${PART_SUFFIX}3" || exit 1
swapon "${DISK}${PART_SUFFIX}3" || exit 1

# Mount the filesystems
mount "${DISK}${PART_SUFFIX}1" /mnt/boot || exit 1
mount /dev/mapper/crypthome /mnt/home || exit 1

log "Disk encryption and mounting complete."

# Base Installation
log "Installing the base system and essential packages..."
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware intel-ucode || exit 1

# Generate an fstab file
genfstab -U /mnt >> /mnt/etc/fstab || exit 1

# Copy the network configuration to the new system
cp -R /etc/iwd /mnt/etc/ || log "No iwd network configuration found."
cp -R /var/lib/iwd /mnt/var/lib/ || log "No iwd network configuration found."



############################################
##    BEGIN CHROOT OPERATIONS FUNCTION    ##
############################################
chroot_operations() {

# Source the installation variables
source /root/install.env || {
    echo "Failed to source install.env."
    exit 1
}

# Function to set up the timezone
set_timezone() {
    ln -sf "/usr/share/zoneinfo/${TIMEZONE_INSTALL}" /etc/localtime
    hwclock --systohc || handle_error "Failed to set hardware clock."
    log "Timezone set to ${TIMEZONE_INSTALL} and hardware clock synchronized."
}

# Function to generate locales
generate_locales() {
    {
        echo "${LOCALE_INSTALL} UTF-8"
        for loc in "${ADDITIONAL_LOCALES_INSTALL[@]}"; do
            echo "$loc UTF-8"
        done
    } > /etc/locale.gen
    locale-gen || handle_error "Failed to generate locales."
    log "Locale generated: ${LOCALE_INSTALL}."
}

# Function to set the system language and additional configurations
set_locale_conf() {
    echo "LANG=${LOCALE_INSTALL}" > /etc/locale.conf
    [[ ! -z "${LC_TIME_INSTALL}" ]] && echo "LC_TIME=${LC_TIME_INSTALL}" >> /etc/locale.conf
    [[ ! -z "${LC_NUMERIC_INSTALL}" ]] && echo "LC_NUMERIC=${LC_NUMERIC_INSTALL}" >> /etc/locale.conf
    [[ ! -z "${LC_MONETARY_INSTALL}" ]] && echo "LC_MONETARY=${LC_MONETARY_INSTALL}" >> /etc/locale.conf
    [[ ! -z "${LC_PAPER_INSTALL}" ]] && echo "LC_PAPER=${LC_PAPER_INSTALL}" >> /etc/locale.conf
    [[ ! -z "${LC_MEASUREMENT_INSTALL}" ]] && echo "LC_MEASUREMENT=${LC_MEASUREMENT_INSTALL}" >> /etc/locale.conf
    log "System language and additional locale configurations set."
}

# Function to set the console keyboard layout
set_keyboard_layout() {
    echo "KEYMAP=${KEYMAP_INSTALL}" > /etc/vconsole.conf
    log "Console keyboard layout set to ${KEYMAP_INSTALL}."
}

# Function to set the root password
set_root_password() {
    log "Please set the root password."
    passwd || handle_error "Failed to set root password."
}

# Function to configure the system hostname and hosts file
configure_hostname() {
    echo "${HOSTNAME_INSTALL}" > /etc/hostname
    {
        echo "127.0.0.1 localhost"
        echo "::1       localhost"
        echo "127.0.1.1 ${HOSTNAME_INSTALL}.localdomain ${HOSTNAME_INSTALL}"
    } > /etc/hosts
    log "Hostname set to ${HOSTNAME_INSTALL} and hosts file configured."
}

# Function to configure mkinitcpio with appropriate hooks
configure_mkinitcpio() {
    sed -i 's/^HOOKS.*/HOOKS=(base udev autodetect keyboard keymap consolefont modconf block encrypt filesystems fsck)/' /etc/mkinitcpio.conf
    mkinitcpio -P linux-zen || handle_error "Failed to regenerate initramfs."
    grep -q "encrypt" /etc/mkinitcpio.conf || handle_error "The initramfs is not configured to unlock the root partition."
    [ -f /boot/initramfs-linux-zen.img ] || handle_error "The initramfs image does not exist."
    log "mkinitcpio configured with appropriate hooks and initramfs regenerated."
}

# Function to install and configure the bootloader
configure_bootloader() {
    mountpoint -q /boot || handle_error "The EFI system partition is not mounted."
    bootctl --path=/boot install || handle_error "Failed to install systemd-boot."
    local root_uuid=$(blkid -s UUID -o value ${DISK}${PART_SUFFIX}2)
    {
        echo "title Arch Linux (Zen)"
        echo "linux /vmlinuz-linux-zen"
        echo "initrd /intel-ucode.img"
        echo "initrd /initramfs-linux-zen.img"
        echo "options cryptdevice=UUID=${root_uuid}:cryptroot root=/dev/mapper/cryptroot quiet rw"
    } > /boot/loader/entries/arch.conf
    log "Systemd-boot installed and configured."
}

# Function to unlock the home partition at boot using the keyfile
configure_crypttab() {
    [ -f /etc/crypthomekey ] || handle_error "The keyfile for the home partition was not found."
    local home_uuid=$(blkid -s UUID -o value "${DISK}${PART_SUFFIX}4")
    echo "crypthome UUID=${home_uuid} /etc/crypthomekey luks,discard" >> /etc/crypttab
    log "Home partition keyfile configured in crypttab."
}

# Function to set the bootloader default and timeout
configure_loader_conf() {
    {
        echo "default arch"
        echo "timeout 3"
        echo "console-mode max"
        echo "editor no"
    } > /boot/loader/loader.conf
    log "Bootloader default and timeout configured."
}

# Function to update the package manager
update_package_manager() {
    pacman -Sy || handle_error "Failed to update package manager."
    log "Package manager updated."
}

# Function to install and enable firewalld
install_firewalld() {
    read -r -p "Do you want to install and enable firewalld? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        pacman -S --needed --noconfirm firewalld || handle_error "Failed to install firewalld."
        systemctl enable firewalld.service || handle_error "Failed to enable firewalld service."
        systemctl start firewalld.service || handle_error "Failed to start firewalld service."
        log "Firewalld installed, enabled, and started."
    fi
}

# Function to install and enable audio services with pipewire
install_audio() {
    read -r -p "Do you want to install pipewire audio? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        pacman -S --needed --noconfirm wireplumber pipewire pipewire-alsa pipewire-pulse pipewire-jack pipewire-pulse || handle_error "Failed to install pipewire."
        log "Pipewire audio installed."
    fi
}

# Function to install and enable bluetooth services
install_bluetooth() {
    read -r -p "Do you want to install bluetooth? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        pacman -S --needed --noconfirm bluez bluez-utils || handle_error "Failed to install bluetooth."
        systemctl enable bluetooth.service || handle_error "Failed to enable bluetooth service."
        log "Bluetooth installed and service enabled."
    fi
}

# Function to install and enable printing services
install_printing() {
    read -r -p "Do you want to install printing? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        pacman -S --needed --noconfirm cups cups-pdf cups-pk-helper || handle_error "Failed to install printing."
        systemctl enable cups.service || handle_error "Failed to enable cups service."
        log "Printing services installed and enabled."
    fi
}

# Function to install and configure network services using systemd-networkd and iwd
configure_network_services() {
    # Install iwd if not already installed
    pacman -S --needed --noconfirm iwd || handle_error "Failed to install iwd."
    log "iwd (iNet Wireless Daemon) installed."

    # Create iwd main configuration
    mkdir -p /etc/iwd
    cat << EOF_IWD > /etc/iwd/main.conf
[General]
EnableNetworkConfiguration=true

[Network]
NameResolvingService=systemd
EOF_IWD
    log "iwd main configuration set up."

    # Enable systemd-networkd and systemd-resolved services
    systemctl enable systemd-networkd.service systemd-resolved.service || handle_error "Failed to enable network services."
    log "systemd-networkd and systemd-resolved services enabled."

    # Configure wireless network interface
    mkdir -p /etc/systemd/network
    cat << EOF_NETWORKD > /etc/systemd/network/25-wireless.network
[Match]
Type=wlan

[Network]
DHCP=yes
IPv6PrivacyExtensions=yes

[DHCP]
RouteMetric=20
EOF_NETWORKD
    log "Wireless network interface configured for DHCP."

    # Enable iwd service for wireless network management
    systemctl enable iwd.service || handle_error "Failed to enable iwd service."
    log "iwd service enabled for wireless network management."

    # Configure systemd-resolved
    mkdir -p /etc/systemd/resolved.conf.d
    cat << EOF_RESOLVED > /etc/systemd/resolved.conf.d/dns.conf
[Resolve]
# Cloudflare
DNS=1.1.1.1 1.0.0.1 2606:4700:4700::1111 2606:4700:4700::1001
# OpenDNS
FallbackDNS=208.67.222.222 208.67.220.220 2620:119:53::53 2620:119:35::35
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
# Disable LLMNR and MulticastDNS, to reduce network noise
LLMNR=no
MulticastDNS=no
EOF_RESOLVED
    log "systemd-resolved configured to use Cloudflare DNS with DNS Over TLS."

    log "Network configuration complete. Use 'iwctl' to connect to Wi-Fi networks."
}

# Function to optionally configure automatic USB drive mounting
configure_usb_auto_mount() {
    read -r -p "Do you want to configure automatic USB drive mounting? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        # Ensure udisks2 is installed
        pacman -S --needed --noconfirm udisks2 || handle_error "Failed to install udisks2."
        log "udisks2 installed for managing disk drives."

        # Create udev rule for auto-mounting USB drives
        mkdir -p /etc/udev/rules.d
        cat << EOF_AUTOMOUNT > /etc/udev/rules.d/99-usb-automount.rules
# Udev rule to auto-mount USB drives with udisks2
ACTION=="add", KERNEL=="sd[a-z][0-9]", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", RUN+="/usr/bin/udisksctl mount -b %N"
ACTION=="remove", KERNEL=="sd[a-z][0-9]", SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", RUN+="/usr/bin/udisksctl unmount -b %N"
EOF_AUTOMOUNT
        log "Udev rule for automatic USB drive mounting configured."

        log "USB drive auto-mount configuration complete. Drives will be auto-mounted on system startup."
    else
        log "Automatic USB drive mounting configuration skipped."
    fi
}

# Function to install desktop profiles
install_desktop_profiles() {
    echo "Installing desktop profiles..."

    # Define package lists for each profile
    local packages_minimal=("iwd" "vim" "neovim" "git" "htop" "curl" "wget" "rsync" "openssh" "man-db" "man-pages" "alacritty" "bat" "bottom" "duf" "dust" "fd" "helix" "jq" "lsd" "ripgrep" "starship")
    local packages_sway=("polkit" "xorg-xwayland" "brightnessctl" "sway" "swayidle" "swaylock" "waybar" "mako" "kanshi" "wl-clipboard" "grim" "slurp" "wl-clipboard")

    # Function to install packages
    install_packages() {
        echo "Installing packages: $@"
        for pkg in "$@"; do
            pacman -S --needed --noconfirm "$pkg" || handle_error "Failed to install $pkg."
        done
    }

    # Profile selection and package installation
    echo "Select one of the following profiles to install:"
    select profile in "minimal" "sway"; do
        case $profile in
            "minimal")
                install_packages "${packages_minimal[@]}"
                break
                ;;
            "sway")
                install_packages "${packages_minimal[@]}" "${packages_sway[@]}"
                log "Sway desktop environment installed."
                break
                ;;
            *)
                echo "Invalid selection, please try again."
                ;;
        esac
    done
}

# Function to clone and setup dotfiles
setup_dotfiles() {
    read -r -p "Do you want to set up dotfiles for ${USERNAME}? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        local tmp_repo="/tmp/dotfiles_${USERNAME}"
        local backup_dir="/home/${USERNAME}/dotfiles_install_backup"
        log "Setting up dotfiles from ${DOTFILES_GIT_REPO}."

        # Clone the dotfiles into a temporary directory
        git clone "${DOTFILES_GIT_REPO}" "${tmp_repo}" || handle_error "Failed to clone dotfiles repository."

        # Create backup directory
        sudo -u "${USERNAME}" mkdir -p "${backup_dir}" || handle_error "Failed to create backup directory."

        # Backup and copy files that exist in both the repo and the home directory
        shopt -s dotglob
        for file in "${tmp_repo}"/*; do
            local filename=$(basename "$file")
            
            # Skip git-specific and non-dotfiles
            if [[ "$filename" == ".git" || "$filename" == ".gitignore" ]]; then
                continue
            fi

            # Check if file exists in the user's home directory
            if [[ -e "/home/${USERNAME}/${filename}" ]]; then
                log "Backing up ${filename}"
                sudo -u "${USERNAME}" mv "/home/${USERNAME}/${filename}" "${backup_dir}/" || {
                    log "Failed to move ${filename} to backup directory"
                    continue
                }
            fi
            
            log "Copying ${filename} to home directory"
            sudo -u "${USERNAME}" cp -r "${file}" "/home/${USERNAME}/" || log "Failed to copy ${filename}"  # Logging line
        done
        shopt -u dotglob

        # Cleanup: Remove the temporary repository
        rm -rf "${tmp_repo}"

        log "Dotfiles setup completed for user ${USERNAME}."
    else
        log "Dotfiles setup skipped."
    fi
}

# Function to install user packages
install_user_packages() {
    read -r -p "Do you want to install additional packages for ${USERNAME}? [y/N] " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        if [[ -f "/home/${USERNAME}/${PKG_LIST_PATH}" ]]; then
            log "Installing user packages for ${USERNAME}."
            pacman -S --needed --noconfirm - < "/home/${USERNAME}/${PKG_LIST_PATH}" || handle_error "Failed to install packages."
            log "User packages installed for ${USERNAME}."
        else
            log "Package list file not found, skipping package installation."
        fi
    else
        log "User package installation skipped."
    fi
}

# Function to create and configure a new user
create_user() {
    if ! id "${USERNAME}" &>/dev/null; then
        # Install ZSH if not installed
        if ! command -v zsh &> /dev/null; then
            pacman -S --noconfirm zsh || handle_error "Failed to install zsh."
            log "zsh installed."
        fi

        # Add user with zsh as default shell
        useradd -m -G wheel -s /bin/zsh "${USERNAME}" || handle_error "Failed to add user ${USERNAME}."
        log "User ${USERNAME} added with zsh as the default shell."

        # Set user password via prompt
        echo "Please set the password for user ${USERNAME}:"
        passwd "${USERNAME}" || handle_error "Failed to set password for ${USERNAME}."
        log "Password set for user ${USERNAME}."

        # Configure sudo privileges
        echo "${USERNAME} ALL=(ALL) ALL" > "/etc/sudoers.d/${USERNAME}"
        chmod 0440 "/etc/sudoers.d/${USERNAME}" || handle_error "Failed to set permissions for sudoers file."
        log "Sudo privileges configured for user ${USERNAME}."

        # Install Oh My Zsh for the user
        log "Installing Oh My Zsh for ${USERNAME}..."
        sudo -u "${USERNAME}" sh -c "RUNZSH=no CHSH=no sh -c \"\$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        log "Oh My Zsh installed for ${USERNAME}."

        # Optionally set up dotfiles and install user packages
        setup_dotfiles
        install_user_packages
    else
        log "User ${USERNAME} already exists, skipping user creation."
    fi
}

# Function to enable essential services
enable_essential_services() {
    systemctl enable iwd.service || log "Failed to enable iwd service."
    systemctl enable systemd-timesyncd.service || log "Failed to enable systemd-timesyncd service."
    systemctl enable fstrim.timer || log "Failed to enable fstrim timer."
    systemctl enable systemd-networkd.service || log "Failed to enable systemd-networkd service."
    systemctl enable systemd-resolved.service || log "Failed to enable systemd-resolved service."
    systemctl enable systemd-homed.service || log "Failed to enable systemd-resolved service."
    log "Essential services enabled."
}

# Main execution flow
log "Beginning system configuration..."

set_timezone
generate_locales
set_locale_conf
set_keyboard_layout
configure_hostname
configure_mkinitcpio
configure_bootloader
configure_crypttab
configure_loader_conf
update_package_manager
install_firewalld
install_audio
install_bluetooth
install_printing
configure_network_services
configure_usb_auto_mount
install_desktop_profiles
set_root_password
create_user
enable_essential_services

}
############################################
##     END CHROOT OPERATIONS FUNCTION     ##
############################################

# Export dependencies for chroot operations function
export -f chroot_operations log handle_error
export SCRIPT_DIR LOG_FILE

# Copy the variables file to the new system
log "Copying the variables file to the new system..."
cp install.env /mnt/root/ || exit 1

# Execute the chroot operations function
log "Executing chroot operations in new system..."
arch-chroot /mnt /bin/bash -c chroot_operations || {
    log "Chroot operations failed."
    exit 1
}
log "Chroot operations complete."


# Finalize systemd-resolved configuration
read -r -p "Did you install the network configuration during the install process? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    log "Creating symlink for /etc/resolv.conf to use systemd-resolved..."
    ln -sf ../run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
    log "Symlink created."
else
    log "Skipping symlink creation for /etc/resolv.conf. Please remember to create it manually if necessary."
fi


# Clean up
umount -R /mnt || log "Failed to unmount partitions."
log "Unmounted all partitions."

# Optional reboot
read -r -p "Do you want to reboot now? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
    log "Rebooting system..."
    reboot
else
    log "Installation complete. Please reboot the system."
fi
