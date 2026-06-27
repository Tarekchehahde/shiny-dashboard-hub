# Shiny Dashboard Hub

Public **multi-dashboard Shiny server** on an IONOS VPS (`http://82.165.167.86/`) — MaStR energy analytics, live API dashboards, regional demos, Grafana monitoring, and a Mission Control portal.

**Not related to [transtek](https://github.com/Tarekchehahde/transtek)** (separate client project).

| Layer | What it is |
|-------|------------|
| **Production hub** | [`WORK/shiny/hub/`](WORK/shiny/hub/) — nginx routes to many Shiny apps |
| **MaStR ETL** | [`WORK/etl/`](WORK/etl/) + GitHub Actions → nightly `data-YYYY-MM-DD` releases |
| **VPS ops** | [`WORK/docs/SERVER.md`](WORK/docs/SERVER.md) — runbook (passwords: local `SERVER.credentials.local.md` only) |
| **Portal & web docs** | [`WORK/ops-portal/`](WORK/ops-portal/) → `/portal/` and `/portal/docs/` on the server |
| **Thesis track** | [`THESIS/thesis_energy_mastr_shiny/`](THESIS/thesis_energy_mastr_shiny/) — separate battery/thesis apps |

**GitHub:** [Tarekchehahde/shiny-dashboard-hub](https://github.com/Tarekchehahde/shiny-dashboard-hub) · branch **`main`**

---

## Live server

| URL | Purpose |
|-----|---------|
| http://82.165.167.86/ | Dashboard hub |
| http://82.165.167.86/portal/ | Mission Control |
| http://82.165.167.86/portal/docs/ | Public documentation |
| http://82.165.167.86/grafana/ | Live metrics (Grafana) |

Full runbook: [`WORK/docs/SERVER.md`](WORK/docs/SERVER.md)

---

## Monorepo layout

| Folder | Use |
|--------|-----|
| **`WORK/`** | Production Shiny apps, ETL, VPS docs, Grafana provisioning |
| **`THESIS/`** | Thesis / battery dashboards (separate launcher) |

### Path trap — `runGitHub` `subdir` must include `WORK/` or `THESIS/`

| Wrong (old) | Right |
|-------------|-------|
| `subdir = "shiny"` | `subdir = "WORK/shiny"` |
| `subdir = "shiny/apps/most_visited"` | `subdir = "WORK/shiny/apps/most_visited"` |

---

## `runGitHub`

**WORK hub / launcher:**

```r
shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde", subdir = "WORK/shiny", ref = "main")
```

**Single app (example):**

```r
shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde",
                 subdir = "WORK/shiny/apps/most_visited", ref = "main")
```

**THESIS launcher:**

```r
shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde",
                 subdir = "THESIS/thesis_energy_mastr_shiny", ref = "main")
```

---

## Clone

```bash
git clone https://github.com/Tarekchehahde/shiny-dashboard-hub.git
```

```r
shiny::runApp("shiny-dashboard-hub/WORK/shiny")
```

---

## Docs index

| Doc | Topic |
|-----|--------|
| [`WORK/docs/README.md`](WORK/docs/README.md) | Documentation index |
| [`WORK/docs/SERVER.md`](WORK/docs/SERVER.md) | VPS runbook (GitHub-safe) |
| [`WORK/docs/AGENT_HANDOFF_IONOS_VPS.md`](WORK/docs/AGENT_HANDOFF_IONOS_VPS.md) | Agent handoff |
| [`WORK/docs/AGENT_HANDOFF.md`](WORK/docs/AGENT_HANDOFF.md) | MaStR ETL & flagship app |
| [`WORK/docs/RUN.md`](WORK/docs/RUN.md) | Local RStudio |

---

## Data & ETL

- **BNetzA** MaStR export → nightly pipeline in **`WORK/etl/`**
- **GitHub Releases** on this repo: `data-YYYY-MM-DD`
- Apps consume releases via DuckDB + `httpfs` (`WORK/shiny/R/mastr_data.R`)

---

## Licence

MaStR data: [Datenlizenz Deutschland — Namensnennung](LICENSE-DATA.md). Code: MIT where noted in [LICENSE](LICENSE).
