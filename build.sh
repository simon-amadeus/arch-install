#!/usr/bin/env bash

# Script to build a custom Arch ISO with the installer

# Set variables
ARCHISO_SOURCE="/usr/share/archiso/configs/releng/"
TMP_DIR=$(mktemp -d)  # Create a temporary directory
TMP_WORK_DIR="$TMP_DIR/work"
TMP_OUT_DIR="$TMP_DIR/out"
CUSTOM_ISO_DIR="$TMP_DIR/archiso"
FINAL_OUTPUT_DIR="$(pwd)"  # Current working directory

# Read iso name from args or use default
if [ -z "$1" ]; then
    echo "No ISO name provided, using default name: custom_arch.iso"
    ISO_NAME="custom_arch.iso"
else
    ISO_NAME="$1"
fi

# Function to clean up temporary files on exit
cleanup() {
    echo "Cleaning up temporary files..."
    sudo rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Function to check if a command succeeded
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error: $1 failed!"
        exit 1
    fi
}

# Install archiso if not already installed
if ! command -v mkarchiso &> /dev/null; then
    echo "Installing archiso package..."
    sudo pacman -S archiso
    check_success "Installing archiso"
else
    echo "archiso is already installed."
fi

# Copy releng source files to the temporary directory
echo "Copying releng files to custom ISO directory..."
cp -r "$ARCHISO_SOURCE" "$CUSTOM_ISO_DIR"
check_success "Copying releng files"

# Copy the installer and post-install scripts
echo "Copying installer files..."
cp install.sh "$CUSTOM_ISO_DIR/airootfs/root/"
cp install.env "$CUSTOM_ISO_DIR/airootfs/root/"
cp post_install.sh "$CUSTOM_ISO_DIR/airootfs/root/"
check_success "Copying installer files"

# Build the ISO inside the temporary directory
echo "Building the custom ISO..."
sudo mkarchiso -v -w "$TMP_WORK_DIR" -o "$TMP_OUT_DIR" "$CUSTOM_ISO_DIR"
check_success "Building the custom ISO"

# Move the final ISO file to the current working directory
echo "Moving final ISO to the current working directory..."
mv "$TMP_OUT_DIR"/*.iso "$FINAL_OUTPUT_DIR/$ISO_NAME"
check_success "Moving final ISO"

echo "Custom ISO creation complete! File located at: $FINAL_OUTPUT_DIR/$ISO_NAME"
