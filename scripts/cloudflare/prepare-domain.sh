#!/usr/bin/env bash
# Prepare MaStR VPS for Cloudflare proxy (orange-cloud DNS).
# Run on VPS as root after adding the domain in Cloudflare dashboard.
#
# Prereqs (Cloudflare dashboard):
#   1. Add site → choose Free plan
#   2. DNS A record: your-domain → 82.165.167.86 (proxied / orange cloud)
#   3. SSL/TLS mode: Full (strict) once origin cert works
#   4. Bot Fight Mode: optional ON under Security
#
# Usage:
#   sudo MASTR_PUBLIC_DOMAIN=nouralwan.de bash scripts/cloudflare/prepare-domain.sh
set -euo pipefail

DOMAIN="${MASTR_PUBLIC_DOMAIN:-}"
VPS_IP="${MASTR_VPS_IP:-82.165.167.86}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NGINX_SITE="/etc/nginx/sites-available/mastr-hub"
ENV_FILE="/etc/mastr-shiny/public.env"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the VPS."
  exit 1
fi

if [[ -z "$DOMAIN" ]]; then
  echo "Set MASTR_PUBLIC_DOMAIN, e.g.:"
  echo "  sudo MASTR_PUBLIC_DOMAIN=nouralwan.de bash scripts/cloudflare/prepare-domain.sh"
  exit 1
fi

echo "Checking DNS for $DOMAIN ..."
RESOLVED="$(dig +short "$DOMAIN" A 2>/dev/null | head -1 || true)"
if [[ -z "$RESOLVED" ]]; then
  echo "WARN: No A record for $DOMAIN yet. Add proxied A → $VPS_IP in Cloudflare first."
else
  echo "A record: $DOMAIN → $RESOLVED"
  if [[ "$RESOLVED" == "$VPS_IP" ]]; then
    echo "NOTE: Points directly to VPS IP. Enable Cloudflare proxy (orange cloud) for DDoS/bot filtering."
  else
    echo "Looks proxied or CNAME'd (not raw VPS IP) — good for Cloudflare."
  fi
fi

bash "$ROOT/scripts/cloudflare/update-realip-ranges.sh"
bash "$ROOT/scripts/apply-nginx-security.sh"

install -d /etc/mastr-shiny
if grep -q "^MASTR_PUBLIC_DOMAIN=" "$ENV_FILE" 2>/dev/null; then
  sed -i "s/^MASTR_PUBLIC_DOMAIN=.*/MASTR_PUBLIC_DOMAIN=$DOMAIN/" "$ENV_FILE"
else
  echo "MASTR_PUBLIC_DOMAIN=$DOMAIN" >> "$ENV_FILE"
fi
chmod 0644 "$ENV_FILE"

if ! grep -q "server_name $DOMAIN" "$NGINX_SITE"; then
  sed -i "s/server_name _;/server_name $DOMAIN _;/" "$NGINX_SITE"
  echo "Added server_name $DOMAIN to nginx."
fi

if ! certbot certificates 2>/dev/null | grep -q "Certificate Name: $DOMAIN"; then
  echo "Requesting Let's Encrypt cert for $DOMAIN (and www) ..."
  certbot certonly --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN" || {
    echo "Certbot failed — set a valid email or run certbot manually."
  }
fi

nginx -t
systemctl reload nginx

cat <<EOF

Cloudflare prep done for $DOMAIN.

Manual steps in Cloudflare dashboard:
  • DNS: A record proxied → $VPS_IP
  • SSL/TLS: Full (strict)
  • Security → Bots: enable Bot Fight Mode (optional)
  • Speed → disable Rocket Loader for Shiny (can break websockets)

Traffic dashboard will show real visitor IPs via CF-Connecting-IP once proxied.
EOF
