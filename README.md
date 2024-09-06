# Arch Linux Installation

This project contains tools for a scripted semi-automated installation of Arch Linux.


## Usage
### 1. Create custom arch iso
```bash
./build.sh my_custom_arch.iso
```

### 2. Test the custom iso
```bash
run_archiso -i my_custom_arch.iso

# after booting, check if files are in the default directory
ls
```

### 2. Boot the custom iso
```bash
# Find the usb drive
sudo fdisk -l
# Write the iso to the usb drive
sudo dd if=my_custom_arch.iso of=<your-usb-drive> bs=16M oflag=direct status=progress
```

### 3. Install Arch Linux
```bash
# The script must be executed from the default directory!!!
./install.sh
``` 
