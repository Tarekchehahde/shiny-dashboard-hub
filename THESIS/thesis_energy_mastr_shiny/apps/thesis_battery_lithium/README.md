# Thesis track — Batterie, Speicher, Lithium (Deutschland)

**Agent handoff:** [`../AGENT_CONTEXT_THESIS_MASTR_SHINY.md`](../AGENT_CONTEXT_THESIS_MASTR_SHINY.md) (one level up: `thesis_energy_mastr_shiny/`).

This tree is **only** the thesis/research Shiny apps. Production MaStR dashboards live in the **same** GitHub repository under **`WORK/shiny/`** (this monorepo is `Tarekchehahde/mastr-shiny`); this folder does not ship the production `WORK/shiny/app.R` launcher.

## Launcher

Set your R working directory to **`THESIS/thesis_energy_mastr_shiny/`** (repository path from clone root: `mastr-shiny/THESIS/thesis_energy_mastr_shiny/`):

```r
shiny::runApp("run_app_thesis_energy.R")
```

Or run a single app:

```r
shiny::runApp("apps/thesis_battery_lithium/01_batteries_deutschland")
```

## Data

- **MaStR-powered apps** use `R/mastr_data.R` (remote Parquet / DuckDB via GitHub Releases). No ETL in this folder.
- **Lithium / mining context** is not in MaStR. App `03_lithium_rohstoff_kontext` reads optional curated rows from **`data/thesis_static/lithium_projects_de.csv`** (relative to `thesis_energy_mastr_shiny/`, not this `apps/` subfolder).

## If you see “Could not resolve latest release”

The app calls GitHub’s **`/releases/latest`** API for `MASTR_REPO` (default `Tarekchehahde/transtek`). That fails when the repo is **private**, has **no releases**, or you’re **rate-limited**. Pick one fix **before** `runApp()`:

**A — Pin a known data release tag** (no “latest” API call):

```r
Sys.setenv(MASTR_TAG = "data-2026-04-21")   # use a tag that exists on your Releases page
shiny::runApp("run_app_thesis_energy.R")
```

**B — Private repo:** set a token that can read releases:

```r
Sys.setenv(GITHUB_TOKEN = "ghp_xxx")        # classic PAT or fine-grained with repo read
```

**C — Offline / API blocked:** download `mastr.duckdb` from your repo’s Releases (browser), then:

```r
Sys.setenv(MASTR_LOCAL_DB = "/full/path/to/mastr.duckdb")
shiny::runApp("run_app_thesis_energy.R")
```

Or in code after `library(shiny)`: `source("R/mastr_data.R"); mastr_use_local("/path/to/mastr.duckdb")`.
