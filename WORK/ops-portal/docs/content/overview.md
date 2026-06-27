# MaStR Shiny Server — Overview

**Public hub:** [http://82.165.167.86/](http://82.165.167.86/)  
**Mission Control:** [http://82.165.167.86/portal/](http://82.165.167.86/portal/)  
**Documentation:** you are here.

This VPS hosts a **Dashboard Hub** — a collection of R Shiny applications behind nginx, plus live monitoring (Grafana, Netdata) and an optional password-protected traffic analytics app.

## What lives on this server

| Area | URL | Access |
|------|-----|--------|
| Dashboard Hub | `/` | Public |
| Mission Control portal | `/portal/` | Public |
| Documentation | `/portal/docs/` | Public |
| Grafana live metrics | `/grafana/` | Public view (read-only) |
| Netdata | `/netdata/` | Public |
| RStudio Server | `:8787` | Login required |
| Site traffic analytics | `/site_traffic/` | Password |

## Technology stack

- **R 4.6** + **Shiny** + **bslib** for all dashboards
- **DuckDB** + parquet for Marktstammdatenregister (MaStR) solar/wind/storage data
- **nginx** reverse proxy → one Shiny process per app (systemd)
- **Prometheus** + **Grafana** for host and HTTP probe monitoring
- **Ubuntu 24.04** on IONOS VPS (6 vCPU, 8 GB RAM)

## Repository layout (local / server)

```
WORK/shiny/
  hub/app.R              # landing page listing all dashboards
  apps/<id>/app.R        # one folder per dashboard
  R/                     # shared helpers (data, UI, Thüringen, nginx logs)
WORK/ops-portal/         # Mission Control + this documentation site
```

On the VPS the app tree is deployed under `/opt/mastr-shiny/`.

## Adding a new dashboard

1. Create `WORK/shiny/apps/<id>/app.R`
2. Register in `WORK/shiny/hub/app.R` (`DASHBOARDS` list)
3. Add nginx `location /{id}/` → port, systemd unit `mastr-{id}`, enable & start
4. Optionally add HTTP probe in Prometheus blackbox config for Grafana UP/DOWN panels

See **Infrastructure** for ports and deployment commands.
