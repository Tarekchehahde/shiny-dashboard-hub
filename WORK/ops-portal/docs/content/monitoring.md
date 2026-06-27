# Monitoring & operations

Live views for demos and day-to-day ops. Most monitoring is **public read-only**; admin tools need a password.

---

## Grafana (`/grafana/`)

**Best demo URL:** [MaStR Live Showcase](http://82.165.167.86/grafana/d/mastr-live-showcase/mastr-live-showcase?refresh=5s) — 5-second refresh, CPU/RAM/network, nginx req/s, green **UP** / red **DOWN** for each public app.

| Dashboard | What it shows |
|-----------|----------------|
| MaStR Live Showcase | Host metrics + HTTP probes for hub & key apps |
| Node Exporter Full | Detailed CPU, disk, network |
| Prometheus Blackbox Exporter | Probe latency per URL |
| NGINX exporter | Connections, request rate |
| Prometheus 2.0 Overview | Prometheus self-health |

**Stack:** Prometheus `:9090`, node_exporter `:9100`, nginx_exporter `:9113`, blackbox_exporter `:9115`.

**TV / presentation mode:** append `&kiosk` to hide Grafana chrome.

Anonymous **Viewer** is enabled for public demos; admin login required to edit.

---

## Netdata (`/netdata/`)

Per-second process and system charts — complementary to Grafana's longer-window trends. Good for “watch the server breathe” during a live demo.

---

## Site traffic (`/site_traffic/`)

Private Shiny app parsing `/var/log/nginx/access.log`:

- Page views and unique visitors
- Popular dashboards
- Visitor IP list (admin use)

Not linked from the public hub. Credentials are stored in server env (`/etc/mastr-shiny/traffic.env`), not in this documentation.

---

## Mission Control (`/portal/`)

Static HTML gateway linking hub, Grafana showcase, Netdata, RStudio, traffic app, and this documentation.

---

## Health checks

Grafana blackbox probes run every **15 seconds** against:

- Hub `/`
- Portal `/portal/`
- Key Shiny apps (most_visited, eu_electricity, kommunal, solar_wirtschaft, deutschland_solar, grafana itself)

All probe targets appear on the **MaStR Live Showcase** dashboard.
