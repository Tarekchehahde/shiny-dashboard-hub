#!/usr/bin/env bash
# IONOS VPS — R + RStudio Server + MaStR Candida dashboard (most_visited)
# Target: Ubuntu 24.04 (noble). Run as root on a fresh VPS.
#
# Usage:
#   scp scripts/ionos-vps-rstudio-candida-setup.sh root@82.165.167.86:/root/
#   ssh root@82.165.167.86 'bash /root/ionos-vps-rstudio-candida-setup.sh'
#
# After this script:
#   RStudio IDE:  http://YOUR_IP:8787  (user: rstudio)
#   Candida app:  http://YOUR_IP:3838  (Shiny, systemd service mastr-candida)

set -euo pipefail

RSTUDIO_DEB="rstudio-server-2026.05.1-225-amd64.deb"
RSTUDIO_URL="https://download2.rstudio.org/server/noble/amd64/${RSTUDIO_DEB}"
MASTR_REPO="https://github.com/Tarekchehahde/shiny-dashboard-hub.git"
INSTALL_DIR="/opt/mastr-shiny"
SHINY_USER="rstudio"

echo "==> Phase 1: base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y \
  git curl wget gdebi-core nginx certbot python3-certbot-nginx \
  build-essential libcurl4-openssl-dev libssl-dev libxml2-dev \
  libfontconfig1-dev libharfbuzz-dev libfribidi-dev libfreetype6-dev \
  libpng-dev libtiff5-dev libjpeg-dev libudunits2-dev libgdal-dev \
  libgeos-dev libproj-dev

echo "==> Phase 2: R (CRAN noble)"
if ! command -v R >/dev/null 2>&1; then
  wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    | gpg --dearmor -o /usr/share/keyrings/r-project.gpg
  echo "deb [signed-by=/usr/share/keyrings/r-project.gpg] https://cloud.r-project.org/bin/linux/ubuntu noble-cran40/" \
    > /etc/apt/sources.list.d/r-project.list
  apt-get update
  apt-get install -y r-base r-base-dev
fi
R --version | head -1

echo "==> Phase 3: Linux user for RStudio"
if ! id "${SHINY_USER}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${SHINY_USER}"
fi
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "${SHINY_USER}" -g "${SHINY_USER}" "/home/${SHINY_USER}/.ssh"
  cp /root/.ssh/authorized_keys "/home/${SHINY_USER}/.ssh/authorized_keys"
  chown "${SHINY_USER}:${SHINY_USER}" "/home/${SHINY_USER}/.ssh/authorized_keys"
  chmod 600 "/home/${SHINY_USER}/.ssh/authorized_keys"
fi
echo "Set a password for ${SHINY_USER} (needed for RStudio login):"
passwd "${SHINY_USER}"

echo "==> Phase 4: RStudio Server"
cd /tmp
wget -q "${RSTUDIO_URL}" -O "${RSTUDIO_DEB}"
gdebi -n "${RSTUDIO_DEB}"
systemctl enable rstudio-server
systemctl restart rstudio-server

echo "==> Phase 5: clone mastr-shiny + renv restore"
install -d -o "${SHINY_USER}" -g "${SHINY_USER}" "${INSTALL_DIR}"
if [[ ! -d "${INSTALL_DIR}/.git" ]]; then
  sudo -u "${SHINY_USER}" git clone --depth 1 "${MASTR_REPO}" "${INSTALL_DIR}"
fi
sudo -u "${SHINY_USER}" bash -lc "
  cd '${INSTALL_DIR}/WORK/shiny' && \
  Rscript -e 'if (!requireNamespace(\"renv\", quietly=TRUE)) install.packages(\"renv\", repos=\"https://cloud.r-project.org\"); renv::restore(prompt=FALSE)'
"

echo "==> Phase 6: systemd service (Candida / most_visited on port 3838)"
cat > /etc/systemd/system/mastr-candida.service << EOF
[Unit]
Description=MaStR Candida Shiny dashboard (most_visited)
After=network.target rstudio-server.service

[Service]
Type=simple
User=${SHINY_USER}
WorkingDirectory=${INSTALL_DIR}/WORK/shiny
Environment=HOME=/home/${SHINY_USER}
ExecStart=/usr/lib/R/bin/R -e "shiny::runApp('apps/most_visited', host='0.0.0.0', port=3838, launch.browser=FALSE)"
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable mastr-candida
systemctl restart mastr-candida

echo "==> Phase 7: nginx reverse proxy (HTTP on port 80 -> Shiny 3838)"
cat > /etc/nginx/sites-available/mastr-candida << 'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:3838;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 300;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/mastr-candida /etc/nginx/sites-enabled/mastr-candida
nginx -t
systemctl enable nginx
systemctl restart nginx

IP=$(curl -4 -s ifconfig.me || hostname -I | awk '{print $1}')
echo ""
echo "=============================================="
echo "Setup complete."
echo ""
echo "  RStudio IDE:  http://${IP}:8787   user: ${SHINY_USER}"
echo "  Candida app:  http://${IP}/        (nginx -> Shiny)"
echo "  Direct Shiny: http://${IP}:3838"
echo ""
echo "IONOS firewall: allow TCP 22, 80, 443, 8787 (8787 optional — use SSH tunnel instead)."
echo "HTTPS: after DNS A-record points here, run:"
echo "  certbot --nginx -d dashboard.YOURDOMAIN.de"
echo "=============================================="
