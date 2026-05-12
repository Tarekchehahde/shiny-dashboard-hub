# MaStR-Shiny — Click-and-Run Dashboards for the German Marktstammdatenregister

Interactive R/Shiny dashboards for the Bundesnetzagentur **Marktstammdatenregister (MaStR)** —
Germany's official register of all electricity- and gas-market units.

> **You never download the XML.** A nightly GitHub Actions pipeline parses the
> ~2.8 GB MaStR XML dump, writes compact Parquet + DuckDB files, and publishes
> them as GitHub Release assets. The Shiny apps query those files **remotely
> over HTTPS** through DuckDB's `httpfs` extension. Locally, you only ever
> download a few MB of R code.

---

## What's in the box

| Folder | Purpose |
|---|---|
| [`etl/`](etl/) | Python pipeline: download → parse XML → write Parquet → build DuckDB → publish Release |
| [`.github/workflows/`](.github/workflows/) | Nightly ETL, schema-drift detection, release automation |
| [`shiny/apps/`](shiny/apps/) | 15+ standalone Shiny dashboards (one folder = one app) |
| [`shiny/R/`](shiny/R/) | Shared loader (`mastr_data.R`) — reads remote Parquet via DuckDB |
| [`docs/`](docs/) | Documentation, data schema, autonomy model |

**Key docs:**
- **[`docs/RUN.md`](docs/RUN.md)** — copy-paste launch commands for end users (start here).
- **[`docs/RSTUDIO_CONTEXTS.md`](docs/RSTUDIO_CONTEXTS.md)** — **RStudio copy-paste**: work vs. thesis (`MASTR_TAG`), full `runGitHub` list per dashboard.
- **[`docs/SOLUTION.md`](docs/SOLUTION.md)** — full architecture, pipeline, data layer, and design decisions.
- [`docs/DATA_SCHEMA.md`](docs/DATA_SCHEMA.md) — column-level reference.
- [`docs/AUTONOMY.md`](docs/AUTONOMY.md) — CI state machine.

---

## Quickstart (end user, RStudio)

### One-liner from GitHub (no clone)

```r
install.packages(c("shiny", "bslib", "DBI", "duckdb", "memoise", "httr2",
                   "rlang", "dplyr", "tidyr", "ggplot2", "plotly", "leaflet",
                   "reactable", "scales", "stringr", "lubridate"))

# Launcher menu (15 dashboards):
shiny::runGitHub("mastr-shiny", "Tarekchehahde", subdir = "shiny", ref = "main")

# Or jump straight into one dashboard:
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "shiny/apps/02_solar_pv", ref = "main")
```

### Clone-and-run (preferred for repeated use)

```bash
git clone --depth 1 https://github.com/Tarekchehahde/mastr-shiny.git
```

```r
shiny::runApp("mastr-shiny/shiny")                  # launcher menu
shiny::runApp("mastr-shiny/shiny/apps/12_geo_map")  # any single app
```

The first query downloads ~5 MB of column statistics; subsequent queries are
sub-second because DuckDB only fetches the Parquet row groups it needs.

### Zero-install (browser) build

The `gh-pages` branch hosts a [shinylive](https://shinylive.io/) build —
no R, no install, just a URL. See [`docs/SHINYLIVE.md`](docs/SHINYLIVE.md).

---

## The dashboards

| # | App | What it shows |
|--:|---|---|
| 01 | **overview** | KPIs: total installed capacity, units, EE-quote, last refresh |
| 02 | **solar_pv** | PV fleet by Bundesland, size class, year of commissioning |
| 03 | **wind_onshore** | Onshore wind: turbines, hub height, rotor diameter, capacity factor proxy |
| 04 | **wind_offshore** | Offshore wind parks, water depth, distance to coast |
| 05 | **biomass** | Biomass / biogas / waste-to-energy plants |
| 06 | **hydro** | Run-of-river, storage, pumped hydro |
| 07 | **geothermal** | Deep geothermal heat & power |
| 08 | **storage** | Battery + pumped storage capacity, C-rate distribution |
| 09 | **chp** | Combined heat and power (KWK) plants |
| 10 | **grid_operators** | Netzbetreiber: connections, balancing zones |
| 11 | **market_actors** | Marktakteure: organisation type, registration timeline |
| 12 | **geo_map** | Leaflet map, units clustered by PLZ / Gemeinde |
| 13 | **capacity_trends** | Time-series build-out vs. EEG targets |
| 14 | **state_comparison** | Bundesland-level league tables and per-capita rankings |
| 15 | **ee_quote** | Renewable share by region & technology, with target trajectories |

Each app is a self-contained `app.R` with its own README. Add your own by
copying any folder and renaming.

---

## Autonomy model

| Stage | Autonomous? | Frequency | Notes |
|---|---|---|---|
| Download MaStR ZIP | ✅ | Nightly 06:00 UTC | Cron + retry + SHA-256 verify |
| Parse XML → Parquet | ✅ | Nightly | Streaming `lxml.iterparse`, ~25 min on `ubuntu-latest` |
| Build DuckDB views | ✅ | Nightly | Indexed by `EnergietraegerBruttoleistung`, `Bundesland`, `InbetriebnahmeDatum` |
| Publish GitHub Release | ✅ | Nightly | Tag `data-YYYY-MM-DD`, assets split by entity type (≤2 GB cap) |
| Schema-drift detection | ✅ | Nightly | Opens an Issue if BNetzA adds/removes XML fields |
| Update Shiny apps | ⚠️ | On schema change or new chart request | Human-in-the-loop |
| Renew `renv.lock` | ✅ | Weekly | Renovate-style PR |

**Bottom line: set-and-forget for ingest + publish. You only intervene when
BNetzA changes the schema (≈2× per year) or you want a new dashboard.**

See [`docs/AUTONOMY.md`](docs/AUTONOMY.md) for the full state machine.

---

## Data licence

MaStR data is published by the Bundesnetzagentur under
[Datenlizenz Deutschland 2.0 — Namensnennung](LICENSE-DATA.md).
The Shiny apps and ETL code are MIT-licensed. Attribution is rendered in the
footer of every dashboard.

---

## Source

- [Bundesnetzagentur — MaStR Datendownload](https://www.marktstammdatenregister.de/MaStR/Datendownload)
