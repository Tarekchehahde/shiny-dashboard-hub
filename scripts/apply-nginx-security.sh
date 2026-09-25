#!/usr/bin/env bash
# Apply nginx + fail2ban hardening on the MaStR VPS.
# Idempotent — safe to re-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NGINX_CONF="/etc/nginx/nginx.conf"
NGINX_SITE="/etc/nginx/sites-available/mastr-hub"
SNIPPET_DIR="/etc/nginx/snippets"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root on the VPS: sudo bash scripts/apply-nginx-security.sh"
  exit 1
fi

install -d "$SNIPPET_DIR" /var/cache/mastr-shiny
chown rstudio:rstudio /var/cache/mastr-shiny
chmod 0755 /var/cache/mastr-shiny
if [[ -f /var/cache/mastr-shiny/ip-geo.csv ]]; then
  chown rstudio:rstudio /var/cache/mastr-shiny/ip-geo.csv
fi

install -m 0644 "$ROOT/scripts/nginx/mastr-security-headers.conf" "$SNIPPET_DIR/"
install -m 0644 "$ROOT/scripts/nginx/mastr-rate-limit-http.conf" "$SNIPPET_DIR/"
install -m 0644 "$ROOT/scripts/nginx/mastr-rate-limit-server.conf" "$SNIPPET_DIR/"
install -m 0644 "$ROOT/scripts/nginx/mastr-cloudflare-realip.conf" "$SNIPPET_DIR/"
install -m 0644 "$ROOT/scripts/nginx/mastr-fahrpruefung.conf" "$SNIPPET_DIR/"

ensure_http_include() {
  local marker="$1"
  local file="$2"
  if ! grep -q "$marker" "$NGINX_CONF"; then
    sed -i "/http {/a\\    include snippets/$file;" "$NGINX_CONF"
    echo "Added http include snippets/$file"
  fi
}

ensure_server_include() {
  local marker="$1"
  local file="$2"
  if ! grep -q "$marker" "$NGINX_SITE"; then
    sed -i "/server_name /a\\    include snippets/$file;" "$NGINX_SITE"
    echo "Added server include snippets/$file to $NGINX_SITE"
  fi
}

ensure_http_include "mastr-rate-limit-http.conf" "mastr-rate-limit-http.conf"
ensure_server_include "mastr-security-headers.conf" "mastr-security-headers.conf"
ensure_server_include "mastr-cloudflare-realip.conf" "mastr-cloudflare-realip.conf"
ensure_server_include "mastr-rate-limit-server.conf" "mastr-rate-limit-server.conf"
ensure_server_include "mastr-fahrpruefung.conf" "mastr-fahrpruefung.conf"

install -m 0644 "$ROOT/scripts/fail2ban/nginx-botscan.filter" /etc/fail2ban/filter.d/nginx-botscan.conf
install -m 0644 "$ROOT/scripts/fail2ban/nginx-botscan-jail.conf" /etc/fail2ban/jail.d/nginx-botscan.conf

nginx -t
systemctl reload nginx
systemctl restart fail2ban
fail2ban-client status nginx-botscan 2>/dev/null || true

echo "Done: security headers, rate limits, Cloudflare real-IP, fail2ban nginx-botscan."
