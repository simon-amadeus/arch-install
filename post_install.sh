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

# Install 1password-cli
ARCH="amd64" && \
    wget "https://cache.agilebits.com/dist/1P/op2/pkg/v2.20.0/op_linux_${ARCH}_v2.20.0.zip" -O op.zip && \
    unzip -d op op.zip && \
    sudo mv op/op /usr/local/bin && \
    rm -r op.zip op && \
    sudo groupadd -f onepassword-cli && \
    sudo chgrp onepassword-cli /usr/local/bin/op && \
    sudo chmod g+s /usr/local/bin/op

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

