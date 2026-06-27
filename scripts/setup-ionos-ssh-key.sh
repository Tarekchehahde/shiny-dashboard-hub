#!/usr/bin/env bash
# One-time setup: SSH key + ~/.ssh/config alias for passwordless VPS tunnel.
# You will be asked for the IONOS root password once.

set -euo pipefail

VPS_IP="82.165.167.86"
VPS_USER="root"
SSH_HOST="ionos-mastr"
KEY="$HOME/.ssh/id_ed25519_ionos_mastr"
CONFIG="$HOME/.ssh/config"
PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"

export PATH="/Users/tarek-lokal/.homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ ! -f "$KEY" ]]; then
  echo "Creating SSH key: $KEY"
  ssh-keygen -t ed25519 -f "$KEY" -N "" -C "ionos-mastr-hub"
fi

if ! grep -q "Host ${SSH_HOST}" "$CONFIG" 2>/dev/null; then
  cat >>"$CONFIG" <<EOF

# MaStR IONOS VPS — added by ${PROJECT}/scripts/setup-ionos-ssh-key.sh
Host ${SSH_HOST}
  HostName ${VPS_IP}
  User ${VPS_USER}
  IdentityFile ${KEY}
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
  ServerAliveInterval 60
EOF
  chmod 600 "$CONFIG"
  echo "Added SSH config block for Host ${SSH_HOST}"
else
  echo "SSH config already contains Host ${SSH_HOST}"
fi

echo
echo "Copying public key to ${VPS_USER}@${VPS_IP} (enter VPS password once)..."
ssh-copy-id -i "${KEY}.pub" "${VPS_USER}@${VPS_IP}"

echo
echo "Testing login..."
ssh -o BatchMode=yes "${SSH_HOST}" 'echo OK: connected as $(whoami)@$(hostname -f 2>/dev/null || hostname)'

echo
echo "Setup complete. Double-click 'MaStR Hub' on your Desktop."
