# MaStR IONOS VPS — server documentation

**Production home:** https://82.165.167.86/ (Mission Control) · **Dashboard hub:** https://82.165.167.86/dashboards/  
**GitHub:** [Tarekchehahde/shiny-dashboard-hub](https://github.com/Tarekchehahde/shiny-dashboard-hub) · branch `main`  
**Local mirror:** `/Users/tarek-lokal/Documents/mastr-shiny/` *(folder name may still say mastr-shiny)*  
**Server clone:** `/opt/mastr-shiny/` on VPS `82.165.167.86` *(path unchanged; `git remote` → shiny-dashboard-hub)*

> **Passwords:** not in this file (safe for GitHub). On your Mac see **`SERVER.credentials.local.md`** in this folder (gitignored).

---

## Quick links

| What | URL | Auth |
|------|-----|------|
| Dashboard hub | https://82.165.167.86/dashboards/ | Public (Goldthau readings path is password-protected) |
| Mission Control | https://82.165.167.86/ | Public (`/portal/` redirects here) |
| **About / CV** | http://82.165.167.86/about/ | Public — primary personal page |
| `/cv` | redirects → `/about/` | Short link |
| **Barrierefrei (DE / AR)** | https://82.165.167.86/barrierefrei/ | Public trial — programming & data science for screen-reader users (`/barrierefrei/ar/` Arabic) |
| **Fahrprüfung (DEKRA study)** | http://82.165.167.86/fahrpruefung/ | App password — see credentials file |
| **Goldthau readings (Nour)** | http://82.165.167.86/goldthau-readings/ | Login required — see credentials file |
| **Nour job tracker** | https://82.165.167.86/nour-jobs/ | Login required — see credentials file |
| Web documentation | http://82.165.167.86/portal/docs/ | Public |
| Grafana (live metrics) | http://82.165.167.86/grafana/ | Public view; admin to edit. `/grafana/metrics` is login-gated |
| MaStR Live Showcase | http://82.165.167.86/grafana/d/mastr-live-showcase/mastr-live-showcase?refresh=5s | Public |
| Netdata | http://82.165.167.86/netdata/ | Login required — see credentials file (Grafana admin). Mac shortcut still uses SSH tunnel |
| RStudio Server | *removed* — use RStudio Desktop / Positron on the Mac | — |
| Site traffic | http://82.165.167.86/site_traffic/ | Login — see credentials file |

---

## Infrastructure

| Item | Value |
|------|--------|
| Provider | IONOS Cloud VPS |
| IP | `82.165.167.86` |
| OS | Ubuntu 24.04 LTS |
| Spec | 6 vCPU, 8 GB RAM, 240 GB NVMe |
| Public entry | HTTPS **443** (HTTP **80** redirects to HTTPS; ACME stays on 80) |
| R | 4.6.0 |
| bslib | **0.11.0** — no vector `width` in `layout_column_wrap` |
| RStudio Server | **not installed** (IDE is local on the Mac) |
| Swap | 2 GB `/swapfile` |

---

## Public URLs (all dashboards)

| URL path | App |
|----------|-----|
| `/` | Mission Control — public gateway |
| `/dashboards/` | Hub — dashboard picker |
| `/my_manager_demo/` | Executive pitch demo |
| `/dummy_demo/` | Routing test |
| `/most_visited/` | MaStR solar Zubau (flagship) |
| `/most_visited_forecast/` | 4-month Zubau outlook |
| `/eurostat_resettled/` | Eurostat resettled persons (`migr_asyrescra`) |
| `/eurostat_de_gas/` | Germany natural-gas diversification |
| `/transformative-ai/` | Transformative AI Strategy for Europe (static one-screen briefing) |
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
| `/fahrpruefung/` | Private — DEKRA Stichworte study app (password gate) |
| `/grafana/` | Public view; admin login to edit |
| `/grafana/metrics` | Private — HTTP basic auth (Grafana admin) |
| `/netdata/` | Private — HTTP basic auth (Grafana admin); SSH tunnel still works |
| `/portal/` | **301 → `/`** (legacy Mission Control bookmark) |
| `/portal/docs/` | Rendered project documentation |

---

## Port map & systemd

All Shiny apps run as Linux user **`rstudio`**.

| Public path | Port | systemd service | Notes |
|-------------|------|-----------------|-------|
| `/` | — | nginx static | Mission Control (`/var/www/mastr-portal/index.html`) |
| `/dashboards/` | 3838 | `mastr-hub` | Hub (pathPrefix `/dashboards`) |
| `/most_visited/` | 3839 | `mastr-most-visited` | MaStR flagship |
| `/most_visited_forecast/` | 3856 | `mastr-most-visited-forecast` | 4-month Zubau outlook |
| `/eurostat_resettled/` | 3857 | `mastr-eurostat-resettled` | Eurostat `migr_asyrescra` |
| `/eurostat_de_gas/` | 3858 | `mastr-eurostat-de-gas` | Germany gas diversification |
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

Sub-apps use `options(shiny.url.pathPrefix = '/<id>')`. Hub uses `shiny.url.pathPrefix='/dashboards'` and `MASTR_HUB_MODE=paths`.

**nginx:** `/etc/nginx/sites-available/mastr-hub` (+ `/etc/nginx/sites-enabled/mastr-hub` — may be a separate copy)  
**Fahrprüfung route:** `include snippets/mastr-fahrpruefung.conf;` → `/etc/nginx/snippets/mastr-fahrpruefung.conf` (repo: `scripts/nginx/mastr-fahrpruefung.conf`). Survives hub-file cleanup if the include line is kept; re-run `scripts/apply-nginx-security.sh` to restore.  
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
WORK/ops-portal/                     # Mission Control (`/`) + `/portal/docs/` sources
WORK/grafana/                        # Grafana provisioning copies
```

---

## SSH & RStudio

```bash
ssh ionos-mastr
# or: ssh root@82.165.167.86
```

**R:** production Shiny apps run as Linux user `rstudio`. There is no RStudio Server on this VPS — use RStudio Desktop / Positron on the Mac.

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

Nightly ETL (`mastr-nightly-etl`) is scheduled **once** at **06:00 UTC**. It publishes `data-YYYY-MM-DD`. GitHub often starts that cron late; publishes typically land around **07:15 UTC** (on time) or **10:20–11:40 UTC** (delayed). Shiny pins the tag for the life of the R process.

**Prognose auto-sync:** `/usr/local/sbin/mastr-sync-data-apps.sh` (repo: `scripts/mastr-sync-data-apps.sh`) runs twice a day via `/etc/cron.d/mastr-data-sync`, **1 hour after** those windows:

- **08:30 UTC** — after an on-time publish
- **12:30 UTC** — after a delayed publish

If the newest `data-*` tag or `published_at` changed, it restarts **only** `mastr-most-visited-forecast`. Unchanged releases are a no-op. Most Visited is not bounced on this timer.

State file: `/var/lib/mastr-shiny/last-data-release`. Logs: `journalctl -t mastr-data-sync` (and syslog).

## Eurostat resettled persons

Dashboard: https://82.165.167.86/eurostat_resettled/ — cube `migr_asyrescra`. ETL: `scripts/eurostat-sync-resettled.py` (VPS `/usr/local/sbin/eurostat-sync-resettled.py`). Cron `/etc/cron.d/mastr-eurostat-resettled` at 09:30/10:30/21:30/22:30 UTC (after Eurostat’s 11:00 and 23:00 CET catalogue refresh). No-op when the cube `updated` stamp is unchanged. Data: `/var/lib/mastr-shiny/eurostat/migr_asyrescra/`.

## Eurostat Germany natural gas

Dashboard: https://82.165.167.86/eurostat_de_gas/ — cubes `nrg_ti_gas`, `nrg_ti_gasm`, `nrg_ind_id`, `nrg_stk_gasm`, `nrg_cb_gasm`, `nrg_pc_202`, `nrg_pc_203` (Germany slices). ETL: `scripts/eurostat-sync-de-gas.py` (VPS `/usr/local/sbin/eurostat-sync-de-gas.py`). Cron `/etc/cron.d/mastr-eurostat-de-gas` at 09:35/10:35/21:35/22:35 UTC. No-op when every cube `updated` stamp is unchanged. Data: `/var/lib/mastr-shiny/eurostat/nrg_gas_de/`. Annual import partners are **country of origin**; monthly partners are **last transit country**.

Manual:

```bash
systemctl restart mastr-most-visited mastr-most-visited-forecast
```

---

## Machine learning

No public ML page on the VPS. Interactive IDE work is local (RStudio Desktop / Positron on the Mac).

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
