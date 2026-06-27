#!/usr/bin/env bash
# Desktop launcher: SSH tunnel + open Netdata dashboard (VPS monitoring).
#
# Netdata listens on 127.0.0.1:19999 on the VPS — reachable only via SSH tunnel.
# Browser: http://localhost:19999/

set -euo pipefail

PROJECT="/Users/tarek-lokal/Documents/mastr-shiny"
LOG="$PROJECT/logs/ionos-netdata-launch.log"
SSH_HOST="ionos-mastr"
NETDATA_URL="http://localhost:19999/"
LOCAL_PORT=19999

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
  pgrep -f "ssh.*${SSH_HOST}.*${LOCAL_PORT}:127.0.0.1:${LOCAL_PORT}" >/dev/null 2>&1 \
    || pgrep -f "ssh.*${SSH_HOST}.*${LOCAL_PORT}:localhost:${LOCAL_PORT}" >/dev/null 2>&1
}

start_tunnel() {
  if ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
    ssh -f -N \
      -o ExitOnForwardFailure=yes \
      -o ServerAliveInterval=60 \
      -o ServerAliveCountMax=3 \
      -L "${LOCAL_PORT}:127.0.0.1:${LOCAL_PORT}" \
      "$SSH_HOST"
    echo "SSH tunnel started (${LOCAL_PORT})"
    return 0
  fi
  echo "SSH key login failed for host alias '$SSH_HOST'"
  return 1
}

if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "$SSH_HOST" "echo ok" >/dev/null 2>&1; then
  alert "VPS Netdata" "SSH key not configured.

One-time setup (Terminal):
  bash ${PROJECT}/scripts/setup-ionos-ssh-key.sh

Then double-click this shortcut again."
  exit 1
fi

if ! tunnel_running; then
  if ! start_tunnel; then
    alert "VPS Netdata" "Could not start SSH tunnel."
    exit 1
  fi
  sleep 1
else
  echo "SSH tunnel for Netdata already running"
fi

# Wait briefly for tunnel + Netdata on server
for _ in 1 2 3 4 5; do
  if curl -s -o /dev/null --connect-timeout 2 "${NETDATA_URL}"; then
    break
  fi
  sleep 1
done

open "${NETDATA_URL}"
notify "VPS Netdata" "Opened ${NETDATA_URL} (IONOS VPS monitoring)"

echo "Done."
