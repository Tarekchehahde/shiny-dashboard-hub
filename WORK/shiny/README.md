# `WORK/shiny/` — click-and-run dashboards

This folder is the **production** Shiny tree inside the monorepo (`WORK/`). End users only need this directory when running from a **clone** (`setwd` here). For **`shiny::runGitHub`**, always set **`subdir = "WORK/shiny"`** or **`"WORK/shiny/apps/…"`** — never **`"shiny/..."`** at repo root (that path was removed).

Everything here is pure R. No XML, no Python, no local database by default.

```
WORK/shiny/
├── app.R              # launcher with a card for every dashboard (auto-picked by runGitHub)
├── R/
│   ├── mastr_data.R   # shared DuckDB-httpfs loader (queries GitHub Releases)
│   └── ui_helpers.R   # shared bslib theme + KPI helpers
├── apps/
│   ├── 01_overview/   app.R
│   ├── 02_solar_pv/   app.R
│   ├── 03_wind_onshore/ app.R
│   ├── … (15 total)
├── DESCRIPTION        # optional package mode (golem-compatible)
└── renv.lock          # pinned dependencies
```

## Three ways to run

### A. One command, all deps restored

```r
install.packages("renv"); renv::restore()
shiny::runApp(".")
```

### B. Launch a specific dashboard

```r
shiny::runApp("apps/11_market_actors")
```

### C. Straight from GitHub, no clone

```r
shiny::runGitHub(
  "mastr-shiny",
  username = "Tarekchehahde",
  ref      = "main",
  subdir   = "WORK/shiny/apps/01_overview"
)
```

## Offline / local-only mode

If you'd rather not hit GitHub for every query, download the DuckDB once
(requires the nightly ETL to have published at least one release):

```r
download.file(
  "https://github.com/Tarekchehahde/mastr-shiny/releases/latest/download/mastr.duckdb",
  "mastr.duckdb", mode = "wb"
)
source("R/mastr_data.R")
mastr_use_local("mastr.duckdb")
shiny::runApp("apps/01_overview")
```

## Pointing to a different fork

```r
Sys.setenv(MASTR_REPO = "some-other-user/some-fork")
```

Pin a specific snapshot (must exist as a release tag on that repo):

```r
Sys.setenv(MASTR_TAG = "data-2026-05-05")
```
