# RUN — Launch the MaStR dashboards in RStudio

Copy-paste the blocks below. No clone, no XML downloads, no configuration.
You'll be looking at live German Marktstammdatenregister data in under
two minutes.

> Architecture & how it works: [`SOLUTION.md`](SOLUTION.md).

---

## Monorepo paths — read this before `runGitHub`

This repository uses top-level **`WORK/`** (production Shiny + ETL) and **`THESIS/`** (thesis apps). Every production `subdir` must start with **`WORK/shiny`** — not `shiny`.

| Symptom | Cause |
|---------|--------|
| `No Shiny application exists at the path …/mastr-shiny-main/shiny/apps/…` | `subdir` still uses legacy **`shiny/...`** — change to **`WORK/shiny/...`** |
| App launches but wrong / old code | Fork or old branch — use **`ref = "main"`** on **`Tarekchehahde/mastr-shiny`** |

**Flagship (Most Visited) — correct one-liner:**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "WORK/shiny/apps/most_visited", ref = "main", launch.browser = TRUE)
```

**Sanity check without opening the app** (confirms `main` has the file on GitHub):

```r
u <- "https://raw.githubusercontent.com/Tarekchehahde/mastr-shiny/main/WORK/shiny/apps/most_visited/app.R"
f <- tempfile(fileext = ".R")
stopifnot(download.file(u, f, quiet = TRUE) == 0L, file.size(f) > 100)
unlink(f); message("OK: most_visited path on GitHub")
```

Full checklist: [repository `README.md`](../../README.md) § “Verify layout”.

---

## Step 1 — install packages (once per machine)

Open the **R or RStudio console** (not a terminal — this is R code).

```r
install.packages(c("shiny","bslib","DBI","duckdb","memoise","cachem","httr2","rlang","dplyr","tidyr","ggplot2","plotly","leaflet","reactable","scales","stringr","lubridate"))
```

## Step 2 — launch the dashboard menu

```r
shiny::runGitHub("mastr-shiny","Tarekchehahde",subdir="WORK/shiny",ref="main",launch.browser=TRUE)
```

You'll see a card grid with the **Flagship** ("Most Visited") at the top,
then the 15 **Core** dashboards, then the 9 **Tableau-Vergleich** dashboards
that replicate the in-house Tableau workbook.

## Step 2 (alternative) — launch one dashboard directly

```r
shiny::runGitHub("mastr-shiny","Tarekchehahde",subdir="WORK/shiny/apps/01_overview",ref="main",launch.browser=TRUE)
```

Swap `01_overview` for any of:

| # | Folder | Shows |
|--:|---|---|
| 01 | `01_overview` | national KPIs, energy mix, monthly build-out |
| 02 | `02_solar_pv` | PV fleet: size classes, Bundesland filter, top PLZ |
| 03 | `03_wind_onshore` | onshore turbines, hub height, year/state filters |
| 04 | `04_wind_offshore` | offshore parks, water depth, distance to coast |
| 05 | `05_biomass` | biomass / biogas plants |
| 06 | `06_hydro` | run-of-river, storage, pumped hydro |
| 07 | `07_geothermal` | deep-geothermal heat & power |
| 08 | `08_storage` | battery + pumped storage |
| 09 | `09_chp` | combined heat & power |
| 10 | `10_grid_operators` | Netzbetreiber overview |
| 11 | `11_market_actors` | Marktakteure registration timeline |
| 12 | `12_geo_map` | interactive Leaflet map |
| 13 | `13_capacity_trends` | time-series build-out |
| 14 | `14_state_comparison` | Bundesland league tables |
| 15 | `15_ee_quote` | renewable share by state |
| ★ | `most_visited` | **Flagship** — monthly solar Zubau by segment + YTD diff table (Tableau-parity; internal name *Candida dashboard*: see [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md)) |
| 16 | `16_ibn_stacked_area` | Tableau *Inbetriebnahmen (2)* — stacked area by size bucket |
| 17 | `17_anlagen_leistung` | Tableau *Überblick – Anlagen & Leistung* — summary row, 3 maps, Q-time series |
| 18 | `18_ibn_tabelle` | Tableau *Inbetriebnahmen MaStR – Tabelle* — Jahr/Quartal/Monat + Δ |
| 19 | `19_ibn_bars` | Tableau *Inbetriebnahmen MaStR* — quarterly bar panels |
| 20 | `20_ibn_speicher_bars` | Tableau *Inbetriebnahmen Speicher* — storage version of 19 |
| 21 | `21_ibn_speicher_tabelle` | Tableau *Inbetriebnahmen Speicher – Tabelle* |
| 22 | `22_batteriekapazitaet` | Tableau *Histogramm Batteriekapazität* (partial — kWh column pending ETL extension) |
| 23 | `23_registrierungsverhalten` | Tableau *Registrierungsverhalten* — IBN-vs-Registrierung delay |
| 24 | `24_registrierungsverhalten_vergleich` | Tableau *Registrierungsverhalten im Vergleich* — heatmap matrix |

---

## What you'll see

- **First launch**: one-time ~2–5 s download of tiny aggregate Parquets
  (~300 KB total) to your local user cache. A single console message
  `[mastr] cached 7 aggregate parquet(s) to …` confirms it worked.
- **First unit-level query** (Solar PV, Wind Onshore, etc.): ~30–40 s
  while DuckDB resolves 20 remote Parquet schemas. Paid **once per
  release** per machine.
- **Everything afterward**: 20 ms per chart. The disk cache survives R
  restarts and auto-invalidates when a new nightly release is published.

No XML is ever downloaded. Your local footprint is <20 MB including the
cache.

---

## Fully offline mode (optional, one-shot 1.9 GB download)

If you want native DuckDB speed and no network at all:

```r
download.file("https://github.com/Tarekchehahde/mastr-shiny/releases/latest/download/mastr.duckdb",destfile="~/mastr.duckdb",mode="wb")
```

Then, once per session **before** launching any app:

```r
source("https://raw.githubusercontent.com/Tarekchehahde/mastr-shiny/main/WORK/shiny/R/mastr_data.R"); mastr_use_local("~/mastr.duckdb")
```

Now every query is <50 ms. Works on a plane.

> If the GitHub Release has split the DuckDB into `mastr.duckdb.partNN`
> chunks (it does when the file crosses 1.9 GB), follow the
> `REASSEMBLE.md` instructions on the release page.

---

## Force-refresh the local cache (after a new nightly release)

The cache auto-invalidates when the release tag changes, so you normally
don't need this. To wipe manually:

```r
source("https://raw.githubusercontent.com/Tarekchehahde/mastr-shiny/main/WORK/shiny/R/mastr_data.R"); mastr_prefetch(force=TRUE)
```

---

## Point at a fork instead of the main repo

```r
Sys.setenv(MASTR_REPO="your-github-user/your-fork"); shiny::runGitHub("your-fork","your-github-user",subdir="WORK/shiny",ref="main",launch.browser=TRUE)
```

---

## Troubleshooting

**`bash: syntax error near unexpected token 'c'`**
You ran an R command in a macOS/Linux terminal. All commands in this file
go into the **R / RStudio console**, not the system shell.

**`Error: App dir must contain either app.R or server.R`**
You're on an old fork. The launcher file is `WORK/shiny/app.R` — make sure
your `subdir` is exactly `"WORK/shiny"` or `"WORK/shiny/apps/NN_…"`.

**`No Shiny application exists at the path …/mastr-shiny-main/shiny/apps/…`**
You used the **legacy** `subdir` (`"shiny/..."`). Switch to **`"WORK/shiny/..."`** — see **§ Monorepo paths** at the top of this file.

**`Extension Autoloading Error … Extension 'icu' is an existing extension.`**
Your network blocks DuckDB's extension CDN. Pre-install once:
```r
local({con<-DBI::dbConnect(duckdb::duckdb()); DBI::dbExecute(con,"INSTALL icu"); DBI::dbDisconnect(con,shutdown=TRUE)})
```

**`Binder Error: Referenced column "Bayern" not found in FROM clause!`**
You're on a revision before the SQL-quoting fix (commit `3de9c12`, April
2026). Pull the latest `main` — `runGitHub` always pulls fresh, so just
re-run the launch command.

**First query is really slow (> 1 min)**
GitHub's CDN is occasionally rate-limited from heavy-usage IP ranges.
Either wait 60 s and retry, or switch to offline mode (see above).

**"Could not resolve latest release"**
The nightly ETL hasn't produced a release yet on the repo you're pointed
at. Check [Actions → mastr-nightly-etl](https://github.com/Tarekchehahde/mastr-shiny/actions)
or set `Sys.setenv(MASTR_REPO="Tarekchehahde/mastr-shiny")`.
