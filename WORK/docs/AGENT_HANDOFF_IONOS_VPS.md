# Agent handoff — IONOS VPS dashboard hub (2026-06-22)

**Purpose:** Hand off the **production Shiny hub** on the user's **IONOS VPS**. Any agent continuing this work should read this file first, then [`SERVER.md`](SERVER.md) for the full runbook (GitHub-safe).

**Passwords (local only):** [`SERVER.credentials.local.md`](SERVER.credentials.local.md) — gitignored, never push to GitHub.

**Repo:** [Tarekchehahde/shiny-dashboard-hub](https://github.com/Tarekchehahde/shiny-dashboard-hub) · branch **`main`**  
**Local mirror (user machine):** `/Users/tarek-lokal/Documents/mastr-shiny/`  
**Server clone:** `/opt/mastr-shiny/` on VPS **`82.165.167.86`**

---

## Credentials (local only — not in git)

> Passwords live in **`WORK/docs/SERVER.credentials.local.md`** (gitignored).  
> Full runbook without secrets: **`WORK/docs/SERVER.md`**

| System | User | Password |
|--------|------|----------|
| **VPS SSH (root)** | `root` | IONOS panel → Server → Zugangsdaten |
| **RStudio Server** | `rstudio` | see `SERVER.credentials.local.md` |
| **Site traffic dashboard** | `admin` | see `SERVER.credentials.local.md` |
| **Grafana admin** | `admin` | see `SERVER.credentials.local.md` |
| **Mission Control** | — | Public — http://82.165.167.86/portal/ |

**Change site-traffic password:**

```bash
ssh ionos-mastr
sudo nano /etc/mastr-shiny/traffic.env   # MASTR_TRAFFIC_USER / MASTR_TRAFFIC_PASS
sudo systemctl restart mastr-site-traffic
```

**Change Grafana password:**

```bash
ssh ionos-mastr
sudo nano /etc/mastr-shiny/grafana.env   # GF_SECURITY_ADMIN_PASSWORD
sudo systemctl restart grafana-server
```

---

## Copy this prompt into a new chat

```
I'm continuing the MaStR Shiny IONOS VPS hub (multi-dashboard server).

Production hub: http://82.165.167.86/

Please read:
1. WORK/docs/SERVER.md — full server runbook (no passwords)
2. WORK/docs/SERVER.credentials.local.md — passwords (local only, gitignored)
3. WORK/docs/AGENT_HANDOFF_IONOS_VPS.md — handoff (infra, ports, erwicon)
4. WORK/docs/AGENT_HANDOFF.md — MaStR data path; "Candida" = most_visited codename

Key facts:
- Hub: WORK/shiny/hub/app.R — DASHBOARDS list + HUB_HIDDEN_IDS
- 16 public dashboards + 1 private site_traffic (port 3854)
- erwicon Thüringen demos 1–7 (Demo 3 Regionalwirtschaft HIDDEN until event day)
- Shared UI: WORK/shiny/R/ui_helpers.R (mastr_page, responsive CSS, collapsible LinkedIn QR)
- MaStR loaders: mastr_data.R, thueringen_helpers.R, nginx_analytics.R
- Apps run as user rstudio; nginx :80 → localhost ports 3838–3854
- bslib 0.11 on VPS — layout_column_wrap(width = c(...)) NOT supported (caused hub 502 once)

SSH: ssh ionos-mastr  (or ssh root@82.165.167.86)
Passwords: WORK/docs/SERVER.credentials.local.md (local only, gitignored)
```

---

## What this project is (2026-06-22)

| Layer | Role |
|--------|------|
| **Hub** | `WORK/shiny/hub/app.R` — card grid; hub order: pitch/demo first, then flagship/live, Thüringen block at bottom |
| **Most Visited** | `apps/most_visited/` — MaStR solar Zubau (internal codename **Candida**) |
| **EU Electricity Live** | `apps/eu_electricity_live/` — Energy-Charts day-ahead prices |
| **Solar Radiation DE** | `apps/deutschland_solar_radiation/` — Open-Meteo GHI map |
| **Health & Wealth** | `apps/health_wealth_nations/` — Gapminder bubble chart |
| **Lebanese elections** | `apps/lebanese_elections/` — Tableau replica |
| **MyManager demo** | `apps/my_manager_demo/` — executive pitch (EN/DE) |
| **Thüringen erwicon 1–7** | Seven demos for **erwicon connect 2026** (23 Jun, Erfurt) — see table below |
| **Site traffic** | `apps/site_traffic/` — **private** nginx log viewer (not on hub) |
| **Shared R** | `ui_helpers.R`, `mastr_data.R`, `thueringen_helpers.R`, `nginx_analytics.R`, `ba_labor_data.R` |
| **Assets** | `WORK/shiny/www/linkedin-qr-tarek-chehade.png` — QR on all dashboards (auto-hide after 5s) |
| **Proxy** | nginx `/etc/nginx/sites-available/mastr-hub` |
| **Processes** | systemd `mastr-*` units, user `rstudio` |

---

## Infrastructure snapshot

| Item | Value |
|------|--------|
| Provider | IONOS Cloud VPS |
| IP | `82.165.167.86` |
| OS | Ubuntu 24.04 LTS |
| Spec | 6 vCPU, 8 GB RAM, 240 GB NVMe |
| Public entry | HTTP **80** (HTTPS not configured) |
| R version | 4.6.0 |
| bslib | **0.11.0** (no vector `width` in `layout_column_wrap`) |
| RStudio Server | 2026.x on `:8787` (SSH tunnel recommended) |
| Netdata | `:19999` localhost only (Desktop **VPS Netdata** app) |
| Grafana | **13.x** on `:3000` localhost; public **http://82.165.167.86/grafana/** |
| Swap | **2 GB** `/swapfile` (added 2026-06-22) |

### Full port map

| Public path | Port | systemd service | Status / notes |
|-------------|------|-----------------|----------------|
| `/` | 3838 | `mastr-hub` | Hub landing |
| `/most_visited/` | 3839 | `mastr-most-visited` | MaStR flagship |
| `/dummy_demo/` | 3840 | `mastr-dummy-demo` | Routing test |
| `/health_wealth_nations/` | 3841 | `mastr-health-wealth` | Gapminder |
| `/lebanese_elections/` | 3842 | `mastr-lebanese-elections` | Elections |
| `/my_manager_demo/` | 3843 | `mastr-my-manager-demo` | Pitch |
| `/deutschland_solar_radiation/` | 3844 | `mastr-deutschland-solar-radiation` | Live GHI |
| `/thueringen_solar_wirtschaft/` | 3845 | `mastr-thueringen-solar-wirtschaft` | erwicon solar |
| `/eu_electricity_live/` | 3846 | `mastr-eu-electricity-live` | EU prices |
| `/thueringen_gewerbe_strom/` | 3847 | `mastr-thueringen-gewerbe-strom` | Demo 1 |
| `/thueringen_waermepumpe_gebaeude/` | 3848 | `mastr-thueringen-waermepumpe-gebaeude` | Demo 2 |
| `/thueringen_fachkraefte/` | 3849 | `mastr-thueringen-fachkraefte` | **HIDDEN** — nginx `404`, service stopped |
| `/thueringen_logistik/` | 3850 | `mastr-thueringen-logistik` | Demo 4 |
| `/thueringen_tourismus/` | 3851 | `mastr-thueringen-tourismus` | Demo 5 |
| `/thueringen_kommunal/` | 3852 | `mastr-thueringen-kommunal` | Demo 6 |
| `/thueringen_mittelstand_digital/` | 3853 | `mastr-thueringen-mittelstand-digital` | Demo 7 |
| `/site_traffic/` | 3854 | `mastr-site-traffic` | **Private** — login required |
| `/grafana/` | 3000 | `grafana-server` | **Grafana** — login required; not on hub |

Sub-apps: `options(shiny.url.pathPrefix = '/<id>')` before `runApp()`.  
Hub: `MASTR_HUB_MODE=paths` in systemd.

---

## erwicon Thüringen demos (2026)

| # | ID | Data source |
|---|-----|-------------|
| — | `thueringen_solar_wirtschaft` | MaStR PV by Kreis |
| 1 | `thueringen_gewerbe_strom` | Energy-Charts + MaStR C&I |
| 2 | `thueringen_waermepumpe_gebaeude` | MaStR Speicher/Home-PV/Biomasse |
| 3 | `thueringen_fachkraefte` | BA STEA/BST API — **hidden** (job-search optics) |
| 4 | `thueringen_logistik` | Demo CSV + MaStR C&I |
| 5 | `thueringen_tourismus` | Demo CSV |
| 6 | `thueringen_kommunal` | MaStR solar ≥100 kW, storage, wind (`WindAnLandOderAufSee`, not `Lage`) |
| 7 | `thueringen_mittelstand_digital` | Demo catalog + mock KPIs |

**Unlock Demo 3 for erwicon day:**

1. Remove `thueringen_fachkraefte` from `HUB_HIDDEN_IDS` in `hub/app.R`; set `published = TRUE`.
2. Restore nginx `location /thueringen_fachkraefte/` → `:3849` (remove `return 404`).
3. `systemctl start mastr-thueringen-fachkraefte && systemctl restart mastr-hub`

Demo data CSVs: `WORK/shiny/data/thueringen/` (also under some app `data/` dirs).

---

## UI / UX features (2026-06-22)

| Feature | Location |
|---------|----------|
| Responsive mobile/tablet CSS | `mastr_responsive_css()` in `ui_helpers.R` |
| LinkedIn QR dock | `mastr_creator_qr_ui()` — shows 5s, slides right, reopen via edge tab |
| Hub badges | Thüringen apps use `badge = "Thüringen"` / `bg-secondary` (no broken white erwicon pills) |
| Footers | `mastr_footer()` presets: `thueringen`, `thueringen_gewerbe`, `thueringen_fachkraefte`, `eu_electricity`, etc. |
| Licensing memo | `WORK/docs/Posit_RStudio_Licensing_Use_Case_Assessment.md` |

---

## Site traffic dashboard (private)

- **URL:** http://82.165.167.86/site_traffic/
- **Login:** see `SERVER.credentials.local.md`
- **Code:** `WORK/shiny/apps/site_traffic/app.R`, `WORK/shiny/R/nginx_analytics.R`
- **Log:** `/var/log/nginx/access.log` (user `rstudio` in group `adm`)
- **Env:** `/etc/mastr-shiny/traffic.env`
- **Unit:** `scripts/systemd/mastr-site-traffic.service`

Counts dashboard **entry** page views (not JS/CSS). Shows IPs, devices, daily chart.

---

## Mission Control portal (`/portal/`)

**URL:** http://82.165.167.86/portal/

Single HTML gateway (static, nginx) linking to:

| Link | URL | Auth |
|------|-----|------|
| Dashboard Hub | `/` | Public |
| Grafana | `/grafana/` | **Public view** (anonymous); admin login for configuration |
| Netdata | `/netdata/` | **Public** (via nginx proxy; was localhost-only) |
| RStudio | `:8787` | **Login required** — do not disable on public internet |
| Site traffic | `/site_traffic/` | Password |

Source: `WORK/ops-portal/` → `/var/www/mastr-portal/` on VPS.

**Documentation:** http://82.165.167.86/portal/docs/ — rendered Markdown (dashboards, monitoring, infrastructure, reference-verification methodology). Bibliography content is **not** published.

---

## Machine learning on this VPS

| Tool | Status | Best for |
|------|--------|----------|
| **RStudio Server** | Installed (`:8787`) | R ML: **tidymodels**, caret, xgboost, torch, Shiny prototypes |
| **JupyterLab** | Not installed | Python ML: scikit-learn, pandas — install if needed |
| Orange / KNIME | N/A on server | Desktop GUI tools — use locally, not this VPS |

RStudio is the primary ML IDE here; same R 4.6 stack as production Shiny apps.

---

## Grafana showcase dashboards

- **Prometheus** + **node_exporter** installed (host metrics)
- Pre-provisioned dashboards in folder **Showcase**:
  - **Node Exporter Full** — CPU, RAM, disk, network (live)
  - **Prometheus 2.0 Overview** — scrape health
- Anonymous visitors can **view** dashboards; use `admin` login to edit
- Datasource: Prometheus → `http://127.0.0.1:9090`

**Optional next:** nginx log metrics, Loki for Shiny access logs, alert rules.

---

## Netdata — public vs localhost

| Access | URL |
|--------|-----|
| **Public (new)** | http://82.165.167.86/netdata/ |
| **SSH tunnel (still works)** | `ssh -L 19999:127.0.0.1:19999 ionos-mastr` → http://localhost:19999/ |
| **Desktop app** | **VPS Netdata** shortcut on Mac |

Previously Netdata listened on `127.0.0.1:19999` only; nginx now proxies `/netdata/`.

---

## Grafana (monitoring UI)

- **URL:** http://82.165.167.86/grafana/
- **Public view:** anonymous **Viewer** (no login to browse Showcase dashboards)
- **Admin login:** `admin` — see `SERVER.credentials.local.md` (for editing)
- **Version:** 13.x (OSS)
- **Showcase dashboards:** Node Exporter Full, Prometheus 2.0 Overview (live via Prometheus + node_exporter)
- **Config:** `/etc/mastr-shiny/grafana.env`
- **nginx:** `location /grafana/` → `proxy_pass http://127.0.0.1:3000` (no trailing slash)

---

## History (setup → Jun 2026)

1. VPS provisioned; hub + core apps (most_visited, dummy, health, lebanese, my_manager, solar radiation).
2. Seven **erwicon** Thüringen demos deployed; EU electricity live added.
3. **Kommunal** fix: wind SQL uses `WindAnLandOderAufSee <> 889`; `mastr_empty_plot()` for loading states.
4. Hub reorder; erwicon title badges removed; **502 fix** — hub must use `layout_column_wrap(width = 1/2)` not named vector (bslib 0.11).
5. Mobile responsive CSS; **site_traffic** app; collapsible LinkedIn QR dock.
6. **Grafana** + Prometheus + **Mission Control** portal (`/portal/`); Netdata public at `/netdata/`.

**Not done yet:**

- HTTPS + custom domain (e.g. `nouralwan.de`)
- Git pull automation on deploy
- systemd timer to restart `mastr-most-visited` after nightly MaStR release
- Commit/push all local hub changes if still ahead of `origin/main`

---

## File index

| Path | Role |
|------|------|
| `WORK/shiny/hub/app.R` | Hub; `DASHBOARDS`, `HUB_HIDDEN_IDS`, `hub_dashboards()` |
| `WORK/shiny/R/ui_helpers.R` | `mastr_page()`, theme, QR dock, responsive CSS |
| `WORK/shiny/R/mastr_data.R` | MaStR GitHub Releases + DuckDB |
| `WORK/shiny/R/thueringen_helpers.R` | Kreis/PLZ, `sql_wind_onshore_raw()`, erwicon banner |
| `WORK/shiny/R/nginx_analytics.R` | Parse nginx logs for site_traffic |
| `WORK/shiny/R/ba_labor_data.R` | BA API for Regionalwirtschaft demo |
| `WORK/shiny/apps/site_traffic/app.R` | Private traffic dashboard |
| `WORK/shiny/apps/thueringen_*/app.R` | erwicon demos |
| `WORK/shiny/www/linkedin-qr-tarek-chehade.png` | LinkedIn QR asset |
| `scripts/systemd/mastr-site-traffic.service` | Traffic app unit template |
| `WORK/docs/SERVER.md` | Full server runbook (GitHub-safe) |
| `WORK/docs/SERVER.credentials.local.md` | Passwords (local only) |
| `WORK/docs/IONOS_VPS_HUB.md` | Redirect → SERVER.md |
| `WORK/docs/Posit_RStudio_Licensing_Use_Case_Assessment.md` | Licensing use-case memo |

### Server-only

| Path | Role |
|------|------|
| `/etc/systemd/system/mastr-*.service` | All Shiny units |
| `/etc/nginx/sites-available/mastr-hub` | Reverse proxy |
| `/etc/mastr-shiny/traffic.env` | Site-traffic login |
| `/etc/mastr-shiny/grafana.env` | Grafana admin + subpath env |
| `/root/rstudio-credentials.txt` | RStudio password |
| `/var/log/nginx/access.log` | Traffic analytics source |

---

## Agent task recipes

### Deploy `ui_helpers.R` (affects all apps)

```bash
rsync -avz WORK/shiny/R/ui_helpers.R ionos-mastr:/opt/mastr-shiny/WORK/shiny/R/
ssh ionos-mastr 'chown rstudio:rstudio /opt/mastr-shiny/WORK/shiny/R/ui_helpers.R
  for svc in $(systemctl list-units "mastr-*" --all --no-legend | awk "{print \$1}"); do
    systemctl try-restart "$svc" 2>/dev/null || true
  done'
```

### Hub 502 after hub/app.R change

Check `journalctl -u mastr-hub -n 20`. Common: unsupported `layout_column_wrap(width = c(...))` on bslib 0.11.

### Debug sub-app

```bash
journalctl -u mastr-thueringen-kommunal -n 50 --no-pager
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3852/
```

### Health check (all public paths)

```bash
for p in / /most_visited/ /eu_electricity_live/ /thueringen_kommunal/ /thueringen_solar_wirtschaft/; do
  curl -s -o /dev/null -w "$p %{http_code}\n" "http://127.0.0.1$p"
done
```

---

## Desktop launcher (macOS)

| Shortcut | Action |
|----------|--------|
| **MaStR Hub** | Open http://82.165.167.86/ + SSH tunnel |
| **IONOS VPS Terminal** | SSH root session |
| **VPS Netdata** | Tunnel → http://localhost:19999/ |

Setup: `bash scripts/setup-ionos-ssh-key.sh`  
Logs: `mastr-shiny/logs/ionos-hub-launch.log`

---

## Security notes

- **Passwords:** `WORK/docs/SERVER.credentials.local.md` only — file is gitignored; never push to GitHub
- Prefer SSH key + tunnel for RStudio; don't expose `:8787` publicly if avoidable
- Rotate VPS root password if ever pasted in chat
- Site traffic shows real IPs — treat as admin-only

---

## Related reading

| Doc | When |
|-----|------|
| [`SERVER.md`](SERVER.md) | Full runbook — URLs, ports, deploy, monitoring |
| [`SERVER.credentials.local.md`](SERVER.credentials.local.md) | Passwords (local only) |
| [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) | MaStR ETL, release tags |
| [`RUN.md`](RUN.md) | Local RStudio without VPS |
