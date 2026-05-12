# RStudio launch commands — work vs. thesis context

All commands below assume the **R console** in RStudio (not PowerShell).  
They use the public repo **`Tarekchehahde/mastr-shiny`** and branch **`main`**.

> **Shared data source:** every dashboard reads the same **GitHub Release** assets produced by **`mastr-nightly-etl`** (Parquet + optional DuckDB). Any other project (e.g. a thesis Shiny app that `source()`s `mastr_data.R` or uses the same release URLs) depends on that pipeline — not on a second ETL.

---

## Step 0 — Install R packages (once per machine)

```r
install.packages(c(
  "shiny", "bslib", "DBI", "duckdb", "memoise", "cachem", "httr2", "rlang",
  "dplyr", "tidyr", "ggplot2", "plotly", "leaflet", "reactable",
  "scales", "stringr", "lubridate"
))
```

---

## Context A — **Work** (always newest published `data-*` snapshot)

Use this when you want the **latest** nightly MaStR extract (floating tag).

```r
Sys.unsetenv("MASTR_TAG")   # ensure no pin from a previous session
Sys.setenv(MASTR_REPO = "Tarekchehahde/mastr-shiny")
```

Then launch any block from **§ Single dashboards** below.

---

## Context B — **Thesis** (reproducible, pinned snapshot)

Use this when your wife’s analysis must stay **bit-identical** across months (defence / appendix). Pick a **concrete** release tag from  
[Releases](https://github.com/Tarekchehahde/mastr-shiny/releases) (pattern **`data-YYYY-MM-DD`**).

```r
Sys.setenv(MASTR_REPO = "Tarekchehahde/mastr-shiny")
Sys.setenv(MASTR_TAG  = "data-2026-05-12")   # <- change to the frozen snapshot you cite in the thesis
```

Restart R (**Session → Restart R**) whenever you change **`MASTR_TAG`**, so `mastr_data.R` cache does not keep an old release.

Then launch the same **`runGitHub`** lines as in work mode — they will honour **`MASTR_TAG`**.

---

## Thesis focus — **batteries (Stromspeicher) in Germany**

If the thesis is on **German grid batteries / storage** using **MaStR**, the nightly ETL already publishes **`stromspeicher.parquet`** (BNetzA **EinheitStromSpeicher** and related entities in the DuckDB build). The same **`MASTR_TAG`** pin applies as for any other MaStR-Shiny view.

**Most relevant built-in dashboards** (after setting work or thesis env above):

| Topic | `subdir` folder | Notes |
|--------|-----------------|--------|
| Storage fleet overview (capacity, C-rate, tech) | `shiny/apps/08_storage` | Good first stop for “batteries in DE”. |
| New storage IBN — quarterly bars | `shiny/apps/20_ibn_speicher_bars` | Tableau-parity build-out view. |
| New storage IBN — table | `shiny/apps/21_ibn_speicher_tabelle` | Year / quarter / month cuts. |
| Battery capacity histogram | `shiny/apps/22_batteriekapazitaet` | See [`RUN.md`](RUN.md): some **kWh** dimensions may still depend on an ETL extension — check before citing in the thesis. |

**Custom SQL in R** (from a local clone, `setwd("…/mastr-shiny/shiny")`, after `source("R/mastr_data.R")`): query the **`stromspeicher`** view/table the same way the apps do (see [`DATA_SCHEMA.md`](DATA_SCHEMA.md) for columns). Pin **`MASTR_TAG`** for reproducible exports.

**Not found in this workspace:** a separate thesis-only repo path; if it appears later, keep **`MASTR_REPO` / `MASTR_TAG`** aligned with the methods chapter.

---

## Launcher menu (all apps)

**Work or thesis** (after setting env block above):

```r
shiny::runGitHub(
  "mastr-shiny",
  "Tarekchehahde",
  subdir = "shiny",
  ref    = "main",
  launch.browser = TRUE
)
```

---

## Single dashboards — full `runGitHub` list

Replace only the **`subdir`** argument. **`launch.browser`** is optional.

Template:

```r
shiny::runGitHub(
  "mastr-shiny",
  "Tarekchehahde",
  subdir = "shiny/apps/<FOLDER>",
  ref    = "main",
  launch.browser = TRUE
)
```

| Folder | Run `subdir =` |
|--------|----------------|
| Launcher (full menu) | `"shiny"` |
| Most Visited (flagship) | `"shiny/apps/most_visited"` |
| 01 — Überblick | `"shiny/apps/01_overview"` |
| 02 — Solar PV | `"shiny/apps/02_solar_pv"` |
| 03 — Wind onshore | `"shiny/apps/03_wind_onshore"` |
| 04 — Wind offshore | `"shiny/apps/04_wind_offshore"` |
| 05 — Biomasse | `"shiny/apps/05_biomass"` |
| 06 — Wasserkraft | `"shiny/apps/06_hydro"` |
| 07 — Geothermie | `"shiny/apps/07_geothermal"` |
| 08 — Stromspeicher | `"shiny/apps/08_storage"` |
| 09 — KWK | `"shiny/apps/09_chp"` |
| 10 — Netzbetreiber | `"shiny/apps/10_grid_operators"` |
| 11 — Marktakteure | `"shiny/apps/11_market_actors"` |
| 12 — Geo-Karte | `"shiny/apps/12_geo_map"` |
| 13 — Zubau-Trends | `"shiny/apps/13_capacity_trends"` |
| 14 — Bundesländer | `"shiny/apps/14_state_comparison"` |
| 15 — EE-Quote | `"shiny/apps/15_ee_quote"` |
| 16 — IBN stacked area | `"shiny/apps/16_ibn_stacked_area"` |
| 17 — Anlagen & Leistung | `"shiny/apps/17_anlagen_leistung"` |
| 18 — IBN Tabelle | `"shiny/apps/18_ibn_tabelle"` |
| 19 — IBN Balken | `"shiny/apps/19_ibn_bars"` |
| 20 — IBN Speicher Balken | `"shiny/apps/20_ibn_speicher_bars"` |
| 21 — IBN Speicher Tabelle | `"shiny/apps/21_ibn_speicher_tabelle"` |
| 22 — Batteriekapazität | `"shiny/apps/22_batteriekapazitaet"` |
| 23 — Registrierungsverhalten | `"shiny/apps/23_registrierungsverhalten"` |
| 24 — Registrierungsverhalten Vergleich | `"shiny/apps/24_registrierungsverhalten_vergleich"` |

### Copy-paste examples (work context)

```r
Sys.unsetenv("MASTR_TAG")
Sys.setenv(MASTR_REPO = "Tarekchehahde/mastr-shiny")

shiny::runGitHub("mastr-shiny", "Tarekchehahde", subdir = "shiny/apps/most_visited", ref = "main", launch.browser = TRUE)
```

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde", subdir = "shiny/apps/02_solar_pv", ref = "main", launch.browser = TRUE)
```

---

## Clone + `runApp` (optional — same two contexts)

```r
# adjust path if your clone lives elsewhere
setwd("C:/Users/CHEHADE/TarekChehadeCodes/mastr-shiny/shiny")

# Thesis: pin before sourcing
Sys.setenv(MASTR_TAG = "data-2026-05-12")

shiny::runApp("apps/most_visited", launch.browser = TRUE)
```

---

## Quick health check (same feed thesis apps use)

After `runGitHub` has populated cache, or from a clone:

```r
source("R/mastr_data.R")   # from shiny/ directory; or source via raw GitHub URL
mastr_release_info()
# tag should match the release you expect (newest, or MASTR_TAG when set)
```

External check (no R): latest release **`data-*`** and asset **`solar.parquet`** should return HTTP **200** (already verified after each good publish).

---

## If the thesis project lives in another folder

This workspace does **not** contain a separate thesis repo path. If that project uses **`mastr_data.R`**, set the same **`MASTR_REPO`** / **`MASTR_TAG`** before sourcing, or document the release tag in the thesis methods chapter.

See also [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) for release-resolution behaviour.
