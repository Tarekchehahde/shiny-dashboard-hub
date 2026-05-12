# How to run the dashboards

Three paths, ordered by friction.

## 1. Browser only (zero install)

Open the GitHub Pages URL for the repo:

```
https://tarekchehahde.github.io/mastr-shiny/
```

(Available once the `mastr-shinylive-deploy` workflow has run at least once.)

Pick a dashboard from the grid. The apps run entirely in WebAssembly; your
browser downloads ~10 MB of pre-aggregated Parquet on first visit, cached
thereafter.

**Best for:** stakeholders, quick demos, mobile.
**Limit:** only the pre-aggregated views are available — no custom SQL, no
row-level drill-down.

---

## 2. RStudio, remote data (recommended)

Works on macOS / Windows / Linux. You only need the `WORK/shiny/` folder.

```bash
# terminal
git clone --depth 1 https://github.com/Tarekchehahde/mastr-shiny.git
cd mastr-shiny/WORK/shiny
```

In RStudio (set the working directory to the `WORK/shiny/` folder first):

```r
install.packages("renv")
renv::restore()
shiny::runApp(".")

# or a specific dashboard directly:
shiny::runApp("apps/02_solar_pv")
```

First query pulls ~5 MB of Parquet metadata. Subsequent queries are usually
< 1 MB each (DuckDB fetches only the relevant row groups).

---

## 3. Fully offline (airplane mode)

Download the DuckDB from the latest release once (~600 MB), then run locally.

```r
url <- "https://github.com/Tarekchehahde/mastr-shiny/releases/latest/download/mastr.duckdb"
download.file(url, "mastr.duckdb", mode = "wb")

source("R/mastr_data.R")
mastr_use_local("mastr.duckdb")
shiny::runApp("apps/01_overview")
```

From this point no network is needed at all.

---

## Troubleshooting

### "Could not resolve latest release"
The nightly ETL hasn't produced a Release yet. Either:
- Run the workflow manually: **Actions → mastr-nightly-etl → Run workflow**
  (or `gh workflow run mastr-nightly-etl.yml`)
- Or point at a fork that already has releases:
  `Sys.setenv(MASTR_REPO = "some-other-user/some-fork")`

### Queries are slow
- First query in a session warms DuckDB's metadata cache (~5 MB). Later
  queries should be sub-second for any aggregate view.
- If the full entity tables feel sluggish, filter by `bundesland_name` or
  year — the Parquet files are dictionary-encoded on those columns.
- Or switch to offline mode (option 3 above).

### `shinylive::export` fails
Make sure you're on R ≥ 4.3 and have `remotes::install_github("posit-dev/r-shinylive")`.
Our CI build uses R 4.4.

### "duckdb httpfs install failed"
Check that your firewall permits HTTPS to `github.com` and
`objects.githubusercontent.com`. DuckDB fetches its httpfs extension on first
use; bundle it offline via `duckdb::duckdb_download_extensions("httpfs")`.
