#!/bin/bash


# Install Yay
pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
makepkg -si
cd ..
rm -rf yay-bin


# Install 1Password
curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --import
git clone https://aur.archlinux.org/1password.git
cd 1password
makepkg -si
cd ..
rm -rf 1password


# Install 1Password CLI
echo "Installing 1Password CLI..."

# Hardcoded version for initial install
ARCH="amd64"
VERSION="2.22.0"

wget "https://cache.agilebits.com/dist/1P/op2/pkg/v$VERSION/op_linux_${ARCH}_v$VERSION.zip" -O op.zip
unzip -d op op.zip
sudo mv op/op /usr/local/bin
rm -r op.zip op
sudo groupadd -f onepassword-cli
sudo chgrp onepassword-cli /usr/local/bin/op
sudo chmod g+s /usr/local/bin/op

echo "1Password CLI installed successfully."

# Update 1Password CLI to the latest version
echo "Checking for updates and installing if available..."
UPDATE_DIR="$HOME/Downloads"
mkdir -p "$UPDATE_DIR"
cd "$UPDATE_DIR"

# Use op update to download the latest version
/usr/local/bin/op update --directory "$UPDATE_DIR"

# Find the downloaded zip file
ZIP_FILE=$(ls op_linux_${ARCH}_v*.zip | sort -V | tail -n 1)

# If a new version was downloaded, install it
if [ -n "$ZIP_FILE" ]; then
    echo "New version found: $ZIP_FILE"
    unzip -d op "$ZIP_FILE"
    sudo mv op/op /usr/local/bin
    rm -r "$ZIP_FILE" op

    # Reapply group settings and permissions
    sudo groupadd -f onepassword-cli
    sudo chgrp onepassword-cli /usr/local/bin/op
    sudo chmod g+s /usr/local/bin/op

    echo "1Password CLI updated successfully."
else
    echo "1Password CLI is already the latest version."
fi


# Install 1password hetzner cloud plugin
sudo pacman -S hcloud
op signin
op plugin init hcloud


# Install Visual Studio Code
yay -S visual-studio-code-bin


# Install file browser
sudo pacman -S rustup
rustup default stable
yay -S joshuto

