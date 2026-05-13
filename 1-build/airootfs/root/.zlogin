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
  ║     If step 2 fails after disk prep, recover with:           ║
  ║       bash ~/arch-install/2-install/recover.sh xps           ║
  ║                                                              ║
  ║  3. After reboot — system setup:                             ║
  ║       bash ~/arch-install/3-first-boot/first-boot.sh xps     ║
  ║                                                              ║
  ║  4. Desktop & personal config:                               ║
  ║       bash ~/arch-install/4-customize/customize.sh xps       ║
  ╚══════════════════════════════════════════════════════════════╝

BANNER
