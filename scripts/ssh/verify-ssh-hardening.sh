#!/usr/bin/env bash
# Ensure SSH is key-only. Safe to re-run.
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the VPS."
  exit 1
fi

HARDEN="/etc/ssh/sshd_config.d/99-hardening.conf"
install -d /etc/ssh/sshd_config.d

cat > "$HARDEN" <<'EOF'
# MaStR VPS — key-only SSH
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
AllowTcpForwarding yes
EOF

# Remove conflicting overrides in main config (comments only — drop-in wins)
sed -i 's/^PermitRootLogin yes/# PermitRootLogin yes (use 99-hardening.conf)/' /etc/ssh/sshd_config

sshd -t
systemctl reload ssh

echo "SSH effective policy:"
sshd -T | grep -E "permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries"
