# Arch Linux Installation

This project contains tools for a scripted semi-automated installation of Arch Linux.


## Usage

After booting with the arch live iso,
set up wifi and execute:

```bash
# After booting from the installation medium

# Download the files
git clone https://gitlab.com/simon.amadeus/arch-install.git
cd arch-install

# Optional: Edit variables in install.env

# Execute the script
./install.sh

``` 

### Alternative

Copy those files to a usb stick and mount into the live system.
Edit vars and execute the script.

The script will also handle the wifi setup.

