#!/usr/bin/env bash
# Bounce the 4-month Prognose when a new GitHub data-* release has landed.
#
# MaStR ETL (mastr-nightly-etl) is scheduled once: 06:00 UTC. GitHub often
# delays that cron; recent publishes cluster ~07:15 UTC (on time) or
# ~10:20–11:40 UTC (delayed). This script is meant to run ~1 hour after those
# windows — not every 20 minutes. See scripts/cron/mastr-data-sync.
set -euo pipefail

REPO="${MASTR_REPO:-Tarekchehahde/shiny-dashboard-hub}"
STATE_DIR="${MASTR_SYNC_STATE_DIR:-/var/lib/mastr-shiny}"
STATE_FILE="${STATE_DIR}/last-data-release"
SERVICES="${MASTR_SYNC_SERVICES:-mastr-most-visited-forecast}"

log() { logger -t mastr-data-sync -- "$*"; echo "mastr-data-sync: $*"; }

newest_data_release() {
  python3 - "$REPO" <<'PY'
import json, os, sys, urllib.request

repo = sys.argv[1]
url = f"https://api.github.com/repos/{repo}/releases?per_page=30"
headers = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "mastr-data-sync",
}
tok = os.environ.get("GITHUB_TOKEN", "").strip()
if tok:
    headers["Authorization"] = f"Bearer {tok}"

req = urllib.request.Request(url, headers=headers)
with urllib.request.urlopen(req, timeout=30) as resp:
    releases = json.load(resp)

rows = []
for rel in releases:
    if rel.get("draft") or rel.get("prerelease"):
        continue
    tag = rel.get("tag_name") or ""
    if not str(tag).startswith("data-"):
        continue
    pub = rel.get("published_at") or ""
    rows.append((pub, tag))

if not rows:
    sys.exit("no data-* releases")
rows.sort(reverse=True)
pub, tag = rows[0]
print(f"{tag}|{pub}")
PY
}

mkdir -p "$STATE_DIR"
fingerprint="$(newest_data_release)"
tag="${fingerprint%%|*}"

if [[ ! -s "$STATE_FILE" ]]; then
  printf '%s\n' "$fingerprint" > "$STATE_FILE"
  log "seeded $STATE_FILE with $tag (no restart)"
  exit 0
fi

prev="$(tr -d '\n' < "$STATE_FILE")"
if [[ "$prev" == "$fingerprint" ]]; then
  log "no new data-* release ($tag) — skip"
  exit 0
fi

log "new release $fingerprint (was $prev) — restarting $SERVICES"
printf '%s\n' "$fingerprint" > "$STATE_FILE"

for svc in $SERVICES; do
  if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-active "$svc" >/dev/null 2>&1; then
    systemctl restart "$svc"
    log "restarted $svc"
  else
    log "skip $svc (not installed/active)"
  fi
done
