# Infrastructure

How dashboards are deployed on the IONOS VPS. **No secrets** in this page — passwords live in `/etc/mastr-shiny/*.env` on the server only.

---

## Architecture

```
Browser → nginx :80
            ├─ /              → Shiny hub :3838
            ├─ /{app_id}/     → Shiny app :3839–3854
            ├─ /portal/       → static HTML /var/www/mastr-portal/
            ├─ /grafana/      → Grafana :3000
            ├─ /netdata/      → Netdata :19999
            └─ /site_traffic/ → Shiny :3854
```

Each Shiny app is a **systemd** unit `mastr-{id}` running `R -e 'shiny::runApp(...)'` on a dedicated port.

---

## Port map (selected)

| Port | Service |
|------|---------|
| 3838 | Hub |
| 3839 | most_visited |
| 3840 | dummy_demo |
| 3841 | health_wealth_nations |
| 3842 | lebanese_elections |
| 3843 | my_manager_demo |
| 3844 | deutschland_solar_radiation |
| 3845–3853 | Thüringen demos |
| 3846 | eu_electricity_live |
| 3854 | site_traffic |
| 3000 | Grafana |
| 8787 | RStudio Server |

---

## Key paths on VPS

| Path | Role |
|------|------|
| `/opt/mastr-shiny/` | Application code (git clone) |
| `/var/www/mastr-portal/` | Mission Control + documentation static files |
| `/etc/nginx/sites-available/mastr-hub` | nginx routes |
| `/etc/grafana/provisioning/` | Grafana datasources & dashboards |
| `/etc/prometheus/prometheus.yml` | Scrape targets |

---

## Deploy documentation or portal changes

From your Mac (repo root):

```bash
scp -r WORK/ops-portal/* ionos-mastr:/var/www/mastr-portal/
```

No restart needed — nginx serves static files immediately.

---

## Deploy Shiny code changes

```bash
ssh ionos-mastr
cd /opt/mastr-shiny && sudo -u rstudio git pull origin main
sudo systemctl restart mastr-{id}   # affected app(s)
```

Or rsync single files and restart the matching service.

---

## MaStR data layer

- Parquet files on object storage, queried through **DuckDB** (`WORK/shiny/R/mastr_data.R`)
- Shared Tableau-style helpers in `tableau_helpers.R`
- Thüringen-specific SQL in `thueringen_helpers.R`

Apps that only use external APIs (EU electricity, solar radiation) call HTTP APIs directly with in-memory caching.

---

## Swap & resources

2 GB swap file (`/swapfile`) added for headroom when multiple Shiny sessions and RStudio run concurrently on 8 GB RAM.
