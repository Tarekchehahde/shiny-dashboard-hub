# MaStR IONOS VPS — server documentation

**Production hub:** http://82.165.167.86/  
**Repo:** [Tarekchehahde/shiny-dashboard-hub](https://github.com/Tarekchehahde/shiny-dashboard-hub) · branch `main`  
**Local mirror:** `/Users/tarek-lokal/Documents/mastr-shiny/`  
**Server clone:** `/opt/mastr-shiny/` on VPS `82.165.167.86`

> **Passwords:** not in this file (safe for GitHub). On your Mac see **`SERVER.credentials.local.md`** in this folder (gitignored).

---

## Quick links

| What | URL | Auth |
|------|-----|------|
| Dashboard hub | http://82.165.167.86/ | Public |
| Mission Control | http://82.165.167.86/portal/ | Public |
| Web documentation | http://82.165.167.86/portal/docs/ | Public |
| Grafana (live metrics) | http://82.165.167.86/grafana/ | Public view; admin to edit |
| MaStR Live Showcase | http://82.165.167.86/grafana/d/mastr-live-showcase/mastr-live-showcase?refresh=5s | Public |
| Netdata | http://82.165.167.86/netdata/ | Public |
| RStudio Server | http://82.165.167.86:8787/ | Login — see credentials file |
| Site traffic | http://82.165.167.86/site_traffic/ | Login — see credentials file |

---

## Infrastructure

| Item | Value |
|------|--------|
| Provider | IONOS Cloud VPS |
| IP | `82.165.167.86` |
| OS | Ubuntu 24.04 LTS |
| Spec | 6 vCPU, 8 GB RAM, 240 GB NVMe |
| Public entry | HTTP **80** (HTTPS not configured yet) |
| R | 4.6.0 |
| bslib | **0.11.0** — no vector `width` in `layout_column_wrap` |
| RStudio Server | `:8787` (SSH tunnel recommended) |
| Swap | 2 GB `/swapfile` |

---

## Public URLs (all dashboards)

| URL path | App |
|----------|-----|
| `/` | Hub — dashboard picker |
| `/my_manager_demo/` | Executive pitch demo |
| `/dummy_demo/` | Routing test |
| `/most_visited/` | MaStR solar Zubau (flagship) |
| `/deutschland_solar_radiation/` | Live solar GHI map Germany |
| `/health_wealth_nations/` | Gapminder bubble chart |
| `/eu_electricity_live/` | EU day-ahead electricity prices |
| `/lebanese_elections/` | Lebanese elections |
| `/thueringen_solar_wirtschaft/` | Thüringen PV overview |
| `/thueringen_gewerbe_strom/` | Demo 1 — Gewerbe-Strom |
| `/thueringen_waermepumpe_gebaeude/` | Demo 2 — Wärmepumpen |
| `/thueringen_logistik/` | Demo 4 — Logistik |
| `/thueringen_tourismus/` | Demo 5 — Tourismus |
| `/thueringen_kommunal/` | Demo 6 — Kommunal |
| `/thueringen_mittelstand_digital/` | Demo 7 — Mittelstand-Digital |

**Hidden / special:**

| URL | Status |
|-----|--------|
| `/thueringen_fachkraefte/` | nginx **404** + service stopped (unlock for erwicon) |
| `/site_traffic/` | Private — login required |
| `/grafana/` | Public view; admin login to edit |
| `/netdata/` | Public monitoring |
| `/portal/` | Mission Control gateway |
| `/portal/docs/` | Rendered project documentation |

---

## Port map & systemd

All Shiny apps run as Linux user **`rstudio`**.

| Public path | Port | systemd service | Notes |
|-------------|------|-----------------|-------|
| `/` | 3838 | `mastr-hub` | Hub |
| `/most_visited/` | 3839 | `mastr-most-visited` | MaStR flagship |
| `/dummy_demo/` | 3840 | `mastr-dummy-demo` | Test |
| `/health_wealth_nations/` | 3841 | `mastr-health-wealth` | Gapminder |
| `/lebanese_elections/` | 3842 | `mastr-lebanese-elections` | Elections |
| `/my_manager_demo/` | 3843 | `mastr-my-manager-demo` | Pitch |
| `/deutschland_solar_radiation/` | 3844 | `mastr-deutschland-solar-radiation` | Live GHI |
| `/thueringen_solar_wirtschaft/` | 3845 | `mastr-thueringen-solar-wirtschaft` | erwicon |
| `/eu_electricity_live/` | 3846 | `mastr-eu-electricity-live` | EU prices |
| `/thueringen_gewerbe_strom/` | 3847 | `mastr-thueringen-gewerbe-strom` | Demo 1 |
| `/thueringen_waermepumpe_gebaeude/` | 3848 | `mastr-thueringen-waermepumpe-gebaeude` | Demo 2 |
| `/thueringen_fachkraefte/` | 3849 | `mastr-thueringen-fachkraefte` | **HIDDEN** |
| `/thueringen_logistik/` | 3850 | `mastr-thueringen-logistik` | Demo 4 |
| `/thueringen_tourismus/` | 3851 | `mastr-thueringen-tourismus` | Demo 5 |
| `/thueringen_kommunal/` | 3852 | `mastr-thueringen-kommunal` | Demo 6 |
| `/thueringen_mittelstand_digital/` | 3853 | `mastr-thueringen-mittelstand-digital` | Demo 7 |
| `/site_traffic/` | 3854 | `mastr-site-traffic` | Private |
| `/grafana/` | 3000 | `grafana-server` | Grafana OSS |

Sub-apps use `options(shiny.url.pathPrefix = '/<id>')`. Hub uses `MASTR_HUB_MODE=paths`.

**nginx:** `/etc/nginx/sites-available/mastr-hub`  
**Grafana proxy:** `location /grafana/` → `http://127.0.0.1:3000` (no trailing slash on `proxy_pass`)

---

## Server layout (repo)

```
/opt/mastr-shiny/                    # git clone
└── WORK/shiny/
    ├── hub/app.R                    # DASHBOARDS list, HUB_HIDDEN_IDS
    ├── apps/<id>/app.R              # one app per folder
    ├── R/                           # ui_helpers, mastr_data, thueringen_helpers, nginx_analytics
    ├── data/thueringen/             # Kreis CSVs for demos
    └── www/                         # shared assets (LinkedIn QR)
WORK/ops-portal/                     # Mission Control + /portal/docs/ sources
WORK/grafana/                        # Grafana provisioning copies
```

---

## SSH & RStudio

```bash
ssh ionos-mastr
# or: ssh root@82.165.167.86
```

**RStudio (prefer tunnel):**

```bash
ssh -L 8787:localhost:8787 ionos-mastr
# Browser: http://localhost:8787  — user rstudio (password in SERVER.credentials.local.md)
```

**Mac desktop shortcuts:** MaStR Hub, IONOS VPS Terminal, VPS Netdata — see `scripts/setup-ionos-ssh-key.sh` and `scripts/install-ionos-desktop-launcher.sh`.

---

## Day-to-day commands (on VPS)

```bash
systemctl list-units 'mastr-*' --all

# Restart all Shiny apps after shared R/ change
for svc in $(systemctl list-units 'mastr-*' --all --no-legend | awk '{print $1}'); do
  systemctl try-restart "$svc" 2>/dev/null || true
done

journalctl -u mastr-hub -n 50 --no-pager

curl -s -o /dev/null -w "hub:%{http_code}\n" http://127.0.0.1/
curl -s -o /dev/null -w "kommunal:%{http_code}\n" http://127.0.0.1/thueringen_kommunal/
```

---

## Deploy code

```bash
cd /opt/mastr-shiny
sudo -u rstudio git pull origin main
# restart affected mastr-* service(s)
```

From Mac (single file):

```bash
rsync -avz WORK/shiny/hub/app.R ionos-mastr:/opt/mastr-shiny/WORK/shiny/hub/
ssh ionos-mastr 'systemctl restart mastr-hub'
```

**Portal / web docs:**

```bash
scp -r WORK/ops-portal/* ionos-mastr:/var/www/mastr-portal/
```

---

## Add a new dashboard

1. Create `WORK/shiny/apps/<id>/app.R`
2. Add to `DASHBOARDS` in `hub/app.R`
3. systemd unit on free port with `shiny.url.pathPrefix='/<id>'`
4. nginx `location /<id>/` → `proxy_pass http://127.0.0.1:<port>/;`
5. `nginx -t && systemctl reload nginx && systemctl enable --now mastr-<name>`

---

## Grafana & monitoring

**Stack:** Prometheus `:9090`, node_exporter `:9100`, nginx_exporter `:9113`, blackbox_exporter `:9115`

| Dashboard | Purpose |
|-----------|---------|
| MaStR Live Showcase | CPU/RAM/network, nginx req/s, UP/DOWN per app (5s refresh) |
| Node Exporter Full | Detailed host metrics |
| Blackbox Exporter | HTTP probe latency |
| NGINX exporter | Traffic & connections |
| Prometheus Overview | Scrape health |

**Kiosk mode:** append `&kiosk` to dashboard URL.

**Config:** `/etc/mastr-shiny/grafana.env`, `/etc/grafana/provisioning/`  
**Restart:** `systemctl restart grafana-server prometheus`

---

## Site traffic (private)

- Parses `/var/log/nginx/access.log` (`rstudio` in group `adm`)
- Code: `WORK/shiny/apps/site_traffic/app.R`, `WORK/shiny/R/nginx_analytics.R`
- Env: `/etc/mastr-shiny/traffic.env`
- Not on public hub — login in `SERVER.credentials.local.md`

---

## Mission Control & web docs

| Item | Source | Deploy target |
|------|--------|---------------|
| Mission Control | `WORK/ops-portal/index.html` | `/var/www/mastr-portal/` |
| Web documentation | `WORK/ops-portal/docs/` | `/var/www/mastr-portal/docs/` |

Public docs cover dashboards, monitoring, infrastructure, ML guide, reference-verification **methodology** (no private bibliography).

---

## erwicon Thüringen (2026)

| # | ID | Data |
|---|-----|------|
| — | `thueringen_solar_wirtschaft` | MaStR PV by Kreis |
| 1 | `thueringen_gewerbe_strom` | Energy-Charts + MaStR C&I |
| 2 | `thueringen_waermepumpe_gebaeude` | MaStR storage / home-PV / biomass |
| 3 | `thueringen_fachkraefte` | BA labor stats — **hidden** |
| 4 | `thueringen_logistik` | Demo CSV + MaStR |
| 5 | `thueringen_tourismus` | Demo CSV |
| 6 | `thueringen_kommunal` | MaStR solar ≥100 kW, storage, wind |
| 7 | `mastr-thueringen-mittelstand-digital` | Demo catalog |

**Unlock Demo 3:** remove from `HUB_HIDDEN_IDS`, restore nginx → `:3849`, `systemctl start mastr-thueringen-fachkraefte`.

---

## MaStR data freshness

Nightly ETL → GitHub release `data-YYYY-MM-DD`. `mastr-most-visited` caches release tag at process start:

```bash
systemctl restart mastr-most-visited
```

---

## Machine learning

RStudio Server (`:8787`) is the ML environment — tidymodels, caret, xgboost, torch. JupyterLab not installed. See http://82.165.167.86/portal/docs/?doc=ml

---

## Troubleshooting

### Hub 502

```bash
journalctl -u mastr-hub -n 30 --no-pager
```

**Known cause:** `layout_column_wrap(width = c(xs=1, lg=0.5))` fails on bslib 0.11 — use `width = 1/2` + CSS.

### Thüringen wind query

Use `WindAnLandOderAufSee <> 889` in `sql_wind_onshore_raw()` (`thueringen_helpers.R`), not column `Lage`.

### DuckDB permissions

```bash
chown -R rstudio:rstudio /usr/local/lib/R/site-library/duckdb
```

---

## Server-only paths

| Path | Role |
|------|------|
| `/etc/systemd/system/mastr-*.service` | Shiny units |
| `/etc/nginx/sites-available/mastr-hub` | Reverse proxy |
| `/etc/mastr-shiny/traffic.env` | Site-traffic login |
| `/etc/mastr-shiny/grafana.env` | Grafana env |
| `/root/rstudio-credentials.txt` | RStudio password backup |

---

## Security

- Passwords only in **`SERVER.credentials.local.md`** (gitignored) — never commit that file
- Prefer SSH tunnel for RStudio; do not disable RStudio auth on a public IP
- Site traffic shows real visitor IPs — admin only
- Rotate passwords if ever shared in chat

---

## Related docs

| Doc | When to read |
|-----|--------------|
| [README.md](README.md) | Index of all WORK/docs files |
| [AGENT_HANDOFF_IONOS_VPS.md](AGENT_HANDOFF_IONOS_VPS.md) | Agent handoff, unlock recipes, file index |
| [AGENT_HANDOFF.md](AGENT_HANDOFF.md) | MaStR ETL, data releases |
| [RUN.md](RUN.md) | Local development without VPS |
