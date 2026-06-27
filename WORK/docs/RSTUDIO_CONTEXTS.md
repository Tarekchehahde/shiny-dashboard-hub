# RStudio launch commands — work vs. thesis context

All commands below assume the **R console** in RStudio (not PowerShell).  
They use the public repo **`Tarekchehahde/shiny-dashboard-hub`** and branch **`main`**.

> **Monorepo `subdir`:** production apps live under **`WORK/shiny/`**. Never use **`subdir = "shiny"`** or **`"shiny/apps/..."`** — that layout was removed. Use **`"WORK/shiny"`** and **`"WORK/shiny/apps/<folder>"`**. Thesis: **`"THESIS/thesis_energy_mastr_shiny"`**. If `runGitHub` errors with a path containing **`…/mastr-shiny-main/shiny/`**, fix the `subdir` prefix. See [`RUN.md`](RUN.md) § Monorepo paths and [repo `README.md`](../../README.md) § Path trap.

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
Sys.setenv(MASTR_REPO = "Tarekchehahde/shiny-dashboard-hub")
```

Then launch any block from **§ Single dashboards** below.

---

## Context B — **Thesis** (reproducible, pinned snapshot)

Use this when your wife’s analysis must stay **bit-identical** across months (defence / appendix). Pick a **concrete** release tag from  
[Releases](https://github.com/Tarekchehahde/shiny-dashboard-hub/releases) (pattern **`data-YYYY-MM-DD`**).

```r
Sys.setenv(MASTR_REPO = "Tarekchehahde/shiny-dashboard-hub")
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
| Storage fleet overview (capacity, C-rate, tech) | `WORK/shiny/apps/08_storage` | Good first stop for “batteries in DE”. |
| New storage IBN — quarterly bars | `WORK/shiny/apps/20_ibn_speicher_bars` | Tableau-parity build-out view. |
| New storage IBN — table | `WORK/shiny/apps/21_ibn_speicher_tabelle` | Year / quarter / month cuts. |
| Battery capacity histogram | `WORK/shiny/apps/22_batteriekapazitaet` | See [`RUN.md`](RUN.md): some **kWh** dimensions may still depend on an ETL extension — check before citing in the thesis. |

**Where they live:** These are **separate app folders** under **`mastr-shiny/WORK/shiny/apps/`** — production / Tableau-parity dashboards (incl. flagship **most_visited**). Each row is a different `subdir` for `shiny::runGitHub(...)`.

**Thesis-only battery apps** (same GitHub repo, different tree): **`THESIS/thesis_energy_mastr_shiny/`** — use `subdir = "THESIS/thesis_energy_mastr_shiny"` for the thesis launcher, or the per-app `subdir` values documented in [`../../THESIS/README.md`](../../THESIS/README.md) and [`../../THESIS/thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md`](../../THESIS/thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md).

**Other Shiny folders elsewhere in `TarekChehadeCodes`** (not MaStR Germany fleet): for example **`DATALAKE-431/shiny_sap_tesvolt_preview/`** (SAP / Tesvolt CSV preview) and **`DATALAKE-431/notebooks/DATALAKE-431_Transmission_Start_Shiny_App/`** (transmission / BMS device data). Those use **different files and questions** than the BNetzA register; do not mix them with thesis methods for **MaStR Stromspeicher** unless you explicitly bridge them in the text.

**Custom SQL in R** (from a local clone, `setwd("…/mastr-shiny/WORK/shiny")`, after `source("R/mastr_data.R")`): query the **`stromspeicher`** view/table the same way the apps do (see [`DATA_SCHEMA.md`](DATA_SCHEMA.md) for columns). Pin **`MASTR_TAG`** for reproducible exports.

---

## Launcher menu (all apps)

**Work or thesis** (after setting env block above):

```r
shiny::runGitHub(
  "shiny-dashboard-hub",
  "Tarekchehahde",
  subdir = "WORK/shiny",
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
  "shiny-dashboard-hub",
  "Tarekchehahde",
  subdir = "WORK/shiny/apps/<FOLDER>",
  ref    = "main",
  launch.browser = TRUE
)
```

| Folder | Run `subdir =` |
|--------|----------------|
| Launcher (full menu) | `"WORK/shiny"` |
| Most Visited (flagship) | `"WORK/shiny/apps/most_visited"` |
| 01 — Überblick | `"WORK/shiny/apps/01_overview"` |
| 02 — Solar PV | `"WORK/shiny/apps/02_solar_pv"` |
| 03 — Wind onshore | `"WORK/shiny/apps/03_wind_onshore"` |
| 04 — Wind offshore | `"WORK/shiny/apps/04_wind_offshore"` |
| 05 — Biomasse | `"WORK/shiny/apps/05_biomass"` |
| 06 — Wasserkraft | `"WORK/shiny/apps/06_hydro"` |
| 07 — Geothermie | `"WORK/shiny/apps/07_geothermal"` |
| 08 — Stromspeicher | `"WORK/shiny/apps/08_storage"` |
| 09 — KWK | `"WORK/shiny/apps/09_chp"` |
| 10 — Netzbetreiber | `"WORK/shiny/apps/10_grid_operators"` |
| 11 — Marktakteure | `"WORK/shiny/apps/11_market_actors"` |
| 12 — Geo-Karte | `"WORK/shiny/apps/12_geo_map"` |
| 13 — Zubau-Trends | `"WORK/shiny/apps/13_capacity_trends"` |
| 14 — Bundesländer | `"WORK/shiny/apps/14_state_comparison"` |
| 15 — EE-Quote | `"WORK/shiny/apps/15_ee_quote"` |
| 16 — IBN stacked area | `"WORK/shiny/apps/16_ibn_stacked_area"` |
| 17 — Anlagen & Leistung | `"WORK/shiny/apps/17_anlagen_leistung"` |
| 18 — IBN Tabelle | `"WORK/shiny/apps/18_ibn_tabelle"` |
| 19 — IBN Balken | `"WORK/shiny/apps/19_ibn_bars"` |
| 20 — IBN Speicher Balken | `"WORK/shiny/apps/20_ibn_speicher_bars"` |
| 21 — IBN Speicher Tabelle | `"WORK/shiny/apps/21_ibn_speicher_tabelle"` |
| 22 — Batteriekapazität | `"WORK/shiny/apps/22_batteriekapazitaet"` |
| 23 — Registrierungsverhalten | `"WORK/shiny/apps/23_registrierungsverhalten"` |
| 24 — Registrierungsverhalten Vergleich | `"WORK/shiny/apps/24_registrierungsverhalten_vergleich"` |

### Copy-paste examples (work context)

```r
Sys.unsetenv("MASTR_TAG")
Sys.setenv(MASTR_REPO = "Tarekchehahde/shiny-dashboard-hub")

shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde", subdir = "WORK/shiny/apps/most_visited", ref = "main", launch.browser = TRUE)
```

```r
shiny::runGitHub("shiny-dashboard-hub", "Tarekchehahde", subdir = "WORK/shiny/apps/02_solar_pv", ref = "main", launch.browser = TRUE)
```

---

## Clone + `runApp` (optional — same two contexts)

```r
# adjust path if your clone lives elsewhere
setwd("C:/Users/CHEHADE/TarekChehadeCodes/mastr-shiny/WORK/shiny")

# Thesis: pin before sourcing
Sys.setenv(MASTR_TAG = "data-2026-05-12")

shiny::runApp("apps/most_visited", launch.browser = TRUE)
```

---

## Quick health check (same feed thesis apps use)

After `runGitHub` has populated cache, or from a clone:

```r
source("R/mastr_data.R")   # from WORK/shiny/ directory; or source via raw GitHub URL
mastr_release_info()
# tag should match the release you expect (newest, or MASTR_TAG when set)
```

External check (no R): latest release **`data-*`** and asset **`solar.parquet`** should return HTTP **200** (already verified after each good publish).

---

## If the thesis project lives in another folder

The **thesis Shiny tree** is **`THESIS/thesis_energy_mastr_shiny/`** in this same repository (`Tarekchehahde/shiny-dashboard-hub`). If you maintain a **separate** fork or copy elsewhere, keep **`MASTR_REPO`** / **`MASTR_TAG`** aligned with the methods chapter.

See also [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) for release-resolution behaviour.
