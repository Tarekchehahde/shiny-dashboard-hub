#!/usr/bin/env bash
# Double-click / Desktop launcher: open MaStR hub in browser + SSH tunnel for RStudio.
#
# Public hub (no tunnel):  http://82.165.167.86/
# RStudio via tunnel:      http://localhost:8787  (user: rstudio)

set -euo pipefail

PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"
LOG="$PROJECT/logs/ionos-hub-launch.log"
SSH_HOST="ionos-mastr"
HUB_URL="http://82.165.167.86/"
RSTUDIO_URL="http://localhost:8787"
TUNNEL_PORTS=(8787 3838 3839 19999)

export PATH="/Users/tarek-lokal/.homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$PROJECT/logs"
exec >>"$LOG" 2>&1
echo "=== $(date) ==="

notify() {
  osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null || true
}

alert() {
  osascript -e "display alert \"$1\" message \"$2\"" 2>/dev/null || true
}

tunnel_running() {
  local pids
  pids=$(pgrep -f "ssh.*${SSH_HOST}.*8787:localhost:8787" 2>/dev/null || true)
  [[ -n "$pids" ]]
}

start_tunnel() {
  local -a forwards=()
  local port
  for port in "${TUNNEL_PORTS[@]}"; do
    forwards+=(-L "${port}:localhost:${port}")
  done

  if ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
    ssh -f -N \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=60 \
      -o ServerAliveCountMax=3 \
      "${forwards[@]}" \
      "$SSH_HOST"
    echo "SSH tunnel started (${TUNNEL_PORTS[*]})"
    return 0
  fi

  echo "SSH key login failed for host alias '$SSH_HOST'"
  return 1
}

open "${HUB_URL}"

if tunnel_running; then
  echo "SSH tunnel already running"
  notify "MaStR Hub" "Opened hub. RStudio tunnel already active."
else
  if start_tunnel; then
    notify "MaStR Hub" "Opened hub + SSH tunnel (RStudio :8787, Netdata :19999)"
  else
    notify "MaStR Hub" "Hub opened. Run setup once for passwordless SSH tunnel."
    alert "MaStR Hub" "Landing page opened in your browser.

SSH tunnel not started (login not configured).

One-time setup (Terminal):
  bash ${PROJECT}/scripts/setup-ionos-ssh-key.sh

Then double-click the Desktop shortcut again for RStudio at ${RSTUDIO_URL}"
  fi
fi

echo "Done."
