#!/usr/bin/env bash
# Install AUR packages interactively. Reads ~/.config/packages/aur_pkglist.txt
# (written by sync-pkglist from `pacman -Qqem` minus the arch-install
# baseline in ~/.config/packages/baseline.txt).
#
# Runs as the primary user. paru will sudo internally when building/installing.
# No --noconfirm: paru's interactive PKGBUILD review is the whole point — it
# is the line of defense against a typosquatted or hijacked AUR package.

set -Eeuo pipefail

PKGLIST="${HOME}/.config/packages/aur_pkglist.txt"
[[ -f "$PKGLIST" ]] || { echo "no AUR package list at $PKGLIST — nothing to do"; exit 0; }

command -v paru >/dev/null \
    || { echo "error: paru not installed — run phase 3 first"; exit 1; }

mapfile -t pkgs < <(sed 's/#.*//' "$PKGLIST" | awk 'NF')
(( ${#pkgs[@]} > 0 )) || { echo "AUR list is empty"; exit 0; }

echo "AUR packages to install/upgrade (${#pkgs[@]}):"
printf '  %s\n' "${pkgs[@]}"
echo

exec paru -S --needed "${pkgs[@]}"
