# Print a friendly banner once on the live ISO so the next step is obvious.
cat <<'BANNER'

  ╔══════════════════════════════════════════════════════════════╗
  ║  arch-install is staged at: ~/arch-install                   ║
  ║                                                              ║
  ║  1. Connect to wifi:                                         ║
  ║       iwctl                                                  ║
  ║                                                              ║
  ║  2. Run the installer:                                       ║
  ║       bash ~/arch-install/2-install/install.sh xps           ║
  ║                                                              ║
  ║  3. After reboot — finish user environment:                  ║
  ║       bash ~/arch-install/3-setup/setup.sh xps               ║
  ╚══════════════════════════════════════════════════════════════╝

BANNER
