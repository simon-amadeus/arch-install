# Print a friendly banner once on the live ISO so the next step is obvious.
cat <<'BANNER'

  ╔══════════════════════════════════════════════════════════╗
  ║  Arch installer is staged at: ~/arch-install             ║
  ║                                                          ║
  ║  1. Connect to wifi:    iwctl                            ║
  ║  2. Run the installer:  ~/arch-install/bootstrap/install.sh <host>
  ║                         (e.g. xps — reads hosts/xps.yml)
  ╚══════════════════════════════════════════════════════════╝

BANNER
