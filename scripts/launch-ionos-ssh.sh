#!/usr/bin/env bash
# Desktop launcher: Terminal + root SSH to IONOS VPS (ops / infra demos).

set -euo pipefail

PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"
LOG="$PROJECT/logs/ionos-ssh-launch.log"
SSH_HOST="ionos-mastr"
REMOTE="/opt/mastr-shiny/scripts/vps-infra-shell.sh"

export PATH="/Users/tarek-lokal/.homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$PROJECT/logs"
exec >>"$LOG" 2>&1
echo "=== $(date) ==="

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
  echo "SSH key login failed for $SSH_HOST"
  osascript -e "display alert \"IONOS VPS SSH\" message \"SSH key not configured.

Run once in Terminal:
  bash ${PROJECT}/scripts/setup-ionos-ssh-key.sh

Then double-click this shortcut again.\"" 2>/dev/null || true
  exit 1
fi

# Fallback if remote script not deployed yet
SSH_CMD="ssh -t ${SSH_HOST} 'bash ${REMOTE} 2>/dev/null || exec bash -l'"

/usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
  activate
  do script "${SSH_CMD}"
end tell
APPLESCRIPT

echo "Opened Terminal SSH to ${SSH_HOST}"
