#!/usr/bin/env bash
# Install / refresh Desktop shortcuts:
#   MaStR Hub.app          — browser hub + optional RStudio tunnel
#   IONOS VPS Terminal.app — root SSH for ops / infra walkthroughs
#   VPS Netdata.app        — Netdata monitoring via SSH tunnel

set -euo pipefail

PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"
HUB_LAUNCHER="$PROJECT/scripts/launch-ionos-hub.sh"
SSH_LAUNCHER="$PROJECT/scripts/launch-ionos-ssh.sh"
NETDATA_LAUNCHER="$PROJECT/scripts/launch-ionos-netdata.sh"
HUB_APP="$HOME/Desktop/MaStR Hub.app"
SSH_APP="$HOME/Desktop/IONOS VPS Terminal.app"
NETDATA_APP="$HOME/Desktop/VPS Netdata.app"

chmod +x "$PROJECT/scripts/launch-ionos-hub.sh"
chmod +x "$PROJECT/scripts/launch-ionos-ssh.sh"
chmod +x "$PROJECT/scripts/launch-ionos-netdata.sh"
chmod +x "$PROJECT/scripts/open-ionos-netdata.sh"
chmod +x "$PROJECT/scripts/setup-ionos-ssh-key.sh"
chmod +x "$PROJECT/scripts/vps-infra-shell.sh"

install_app() {
  local launcher="$1"
  local dest="$2"
  rm -rf "$dest"
  /usr/bin/osacompile -o "$dest" <<APPLESCRIPT
on run
  do shell script "bash '${launcher}'"
end run
APPLESCRIPT
  echo "Installed: $dest"
}

install_app "$HUB_LAUNCHER" "$HUB_APP"
install_app "$SSH_LAUNCHER" "$SSH_APP"
install_app "$NETDATA_LAUNCHER" "$NETDATA_APP"

echo
echo "Optional one-time SSH setup (no password on each launch):"
echo "  bash ${PROJECT}/scripts/setup-ionos-ssh-key.sh"
echo
echo "Desktop shortcuts:"
echo "  MaStR Hub            → http://82.165.167.86/"
echo "  IONOS VPS Terminal   → root SSH (infra demo)"
echo "  VPS Netdata          → http://localhost:19999/ (monitoring)"
echo "  RStudio (via Hub)    → http://localhost:8787"
