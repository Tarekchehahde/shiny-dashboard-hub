#!/usr/bin/env bash
# Regenerate mastr-cloudflare-realip.conf from Cloudflare published IP lists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/scripts/nginx/mastr-cloudflare-realip.conf"

{
  echo "# Auto-generated $(date -u +%Y-%m-%dT%H:%M:%SZ) — do not edit by hand"
  echo "# Refresh: scripts/cloudflare/update-realip-ranges.sh"
  echo ""
  echo "real_ip_header CF-Connecting-IP;"
  echo "real_ip_recursive on;"
  echo ""
  curl -fsSL https://www.cloudflare.com/ips-v4/ | sed 's/^/set_real_ip_from /; s/$/;/'
  echo ""
  curl -fsSL https://www.cloudflare.com/ips-v6/ | sed 's/^/set_real_ip_from /; s/$/;/'
} > "$OUT"

echo "Wrote $OUT"
