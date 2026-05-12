# MaStR-Shiny — Solution Reference

A complete, end-to-end reference for how this project ingests the
Bundesnetzagentur **Marktstammdatenregister (MaStR)** XML dump nightly and
serves 15 interactive R Shiny dashboards that anyone in the world can run
from RStudio without downloading a single XML file.

> **Audience:** engineers, data team reviewers, forkers, and anyone writing
> academic / policy work who needs to cite exactly what the pipeline does.
> For a two-minute "how do I see a chart in RStudio right now?", read
> [`RUN.md`](RUN.md) instead. Contributors and **coding agents** should also read
> [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) (operations, release quirks, internal naming such as *Candida dashboard*).

---

## 1. The problem in one paragraph

MaStR is Germany's official register of every grid-connected electricity and
gas unit — roughly **8.7 million rows** across 20 entity types (PV, wind,
storage, biomass, KWK, market actors, grid connection points, …). The
Bundesnetzagentur (BNetzA) publishes it daily as a **~2.8 GB ZIP of ~25 GB
of XML** with several hundred columns whose schema drifts ~2× per year. It
is excellent reference data and a pain to distribute, so most published
analyses stop at static PDFs.

The goal of this project is to make MaStR **click-and-run**: any R user can
launch a dashboard from RStudio with one command, see fresh data every
morning, and never download more than a few MB locally.

---

## 2. Architecture

```
                   ┌────────────────────────────┐
                   │  BNetzA — MaStR nightly    │
                   │  Gesamtdatenauszug (ZIP)   │  ~2.8 GB
                   └─────────────┬──────────────┘
                                 │ HTTPS GET, 06:00 UTC
                                 │ aria2c, 16-way parallel
                                 ▼
       ┌──────────────────────────────────────────────┐
       │ GitHub Actions runner (ubuntu-latest, 14 GB) │
       │ ─────────────────────────────────────────────│
       │ download  →  parse (streaming lxml)          │
       │ build-db  →  aggregates                      │
       │ schema-diff (opens issue on change)          │
       │ publish   →  gh release create + upload      │
       └──────────────────────────┬───────────────────┘
                                  │ artifacts, ~1.9 GB total
                                  ▼
          ┌──────────────────────────────────────┐
          │  GitHub Release  data-YYYY-MM-DD     │
          │  ├── solar.parquet       (~450 MB)   │
          │  ├── wind.parquet        (~15 MB)    │
          │  ├── stromspeicher.parquet (~180 MB) │
          │  ├── …                               │
          │  ├── mastr.duckdb.partNN (×5, 1.9 GB)│
          │  └── aggregates/*.parquet (~300 KB)  │
          └──────────────┬───────────────────────┘
                         │ HTTPS range requests
                         │ (local cache after first read)
                         ▼
            ┌──────────────────────────────┐
            │ Shiny apps in RStudio        │
            │ DuckDB httpfs + icu          │
            │ reads only bytes it needs    │
            └──────────────┬───────────────┘
                           │ user never downloads XML
                           ▼
                  ┌─────────────────┐
                  │ User's RStudio  │
                  │ — <20 MB local  │
                  └─────────────────┘
```

**Core invariant:** the user's local footprint is bounded by the size of
the pre-rolled aggregate Parquets (~300 KB today) plus a rolling 256 MB
LRU result cache. All heavy lifting happens in CI.

---

## 3. End-to-end pipeline (GitHub Actions)

All jobs run in `.github/workflows/nightly-etl.yml`, ubuntu-latest runner,
~30 min wall clock.

| Stage         | Entry point                      | Input                          | Output                                  | Typical time |
|---------------|----------------------------------|--------------------------------|-----------------------------------------|--------------|
| **download**  | `mastr_etl.download`             | BNetzA URL                     | `data/work/mastr-latest.zip` + `.sha256`| 5 min        |
| **parse**     | `python -m mastr_etl.parse`      | the ZIP                        | `data/parquet/{entity}.parquet` × 20    | 20 min       |
| **build-db**  | `python -m mastr_etl.build_duckdb` | the parquet directory       | `data/mastr.duckdb` (~1.9 GB)           | 3 min        |
| **aggregates**| `python -m mastr_etl.aggregates` | the duckdb + parquet dir       | `data/aggregates/*.parquet` (~300 KB)   | 30 s         |
| **schema-diff**| `python -m mastr_etl.schema_diff`| today's parquets vs. yesterday | optional GitHub Issue                   | 5 s          |
| **publish**   | `python -m mastr_etl.publish`    | data dir                       | GitHub Release `data-YYYY-MM-DD`        | 3 min        |

### 3.1 Download

- Uses `aria2c` with 16 concurrent connections against the BNetzA CDN. We
  measured a **17× speedup** vs. plain `curl` (~0.37 → ~6.2 MiB/s on the
  GitHub runner).
- `tenacity` retries transient network errors with exponential back-off.
- Post-download: SHA-256 computed; if the ZIP is byte-identical to the
  previous nightly, the pipeline short-circuits the parse step (it caches
  by SHA in `actions/cache@v4`).
- A second cache layer keys the parsed parquet set on the ZIP hash, so
  re-runs of the same day finish in <3 minutes.

### 3.2 Parse

- Implemented in `etl/src/mastr_etl/parse.py`.
- Uses `lxml.iterparse(events=("end",), tag=record_tag)` with `element.clear()`
  on each iteration — constant memory regardless of XML size.
- Each entity type (solar, wind, stromspeicher, …) is defined in
  `etl/src/mastr_etl/config.py:ENTITIES`, with:
  - the XML glob (`EinheitenSolar_*.xml`, `Marktakteure_*.xml`, …)
  - the record element name
  - optional partition columns (e.g. `Bundesland` for `solar`)
  - optional schema overrides
- Writes one `{entity}.parquet` per entity using `pyarrow` with Snappy
  compression. Typical compression ratios are 10–20× vs. the raw XML.
- **Failure handling:** corrupt records are skipped (`recover=True`); cast
  failures yield `NULL` instead of raising. A `Parse summary` log line
  reports per-entity row counts, so CI failures are easy to triage.

### 3.3 Build-DB

- `etl/src/mastr_etl/build_duckdb.py` creates `mastr.duckdb` from the
  Parquet files and materialises:
  - One CREATE TABLE per entity (so DuckDB can index and use stats).
  - A 17-row `bundesland(code, name)` lookup populated from
    `config.BUNDESLAND`.
  - A cross-entity **`v_units_all`** view — UNION ALL across the eight
    generation entity tables (`solar`, `wind`, `biomasse`, `wasser`,
    `geothermie`, `kernkraft`, `verbrennung`, `stromspeicher`) projecting
    a single canonical row shape:
    ```sql
    (source_table, energietraeger, mastr_nr,
     bruttoleistung_kw, nettonennleistung_kw,
     bundesland_code, bundesland_name,
     gemeinde, plz, lon, lat,
     inbetriebnahme_datum, betriebsstatus)
    ```
    plus `v_capacity_by_state`, `v_buildout_monthly`, `v_capacity_by_plz`.
- **Schema-heterogeneity safety:** per-table column discovery (via
  `information_schema.columns`) + a `.col_or_null()` helper project `NULL`
  for columns missing in any branch of the UNION. This is what keeps the
  pipeline green when BNetzA ships a skinny `kernkraft` parquet with only
  45 of solar's 70 columns.
- **Memory safety:** `PRAGMA memory_limit='4GB'` plus a `PRAGMA
  temp_directory` pointed at `$RUNNER_TEMP` so DuckDB spills to disk
  instead of OOM-ing the runner on the ~6 M-row solar table.
- **Fault tolerance:** missing parquet files log a warning and are
  dropped from `v_units_all`; a half-built table is rolled back before
  the next attempt. This is how the pipeline survives BNetzA's
  occasionally-missing `EinheitenGeoSolarthermie_*.xml`.

### 3.4 Aggregates

Small pre-rolled Parquets (~300 KB total, ~1 MB each at the outside) live
in `data/aggregates/`. They exist so every dashboard can render its "at a
glance" view without touching the multi-GB entity tables:

| File                             | Rows  | Used by                                    |
|----------------------------------|-------|--------------------------------------------|
| `kpi_overview.parquet`           | 1     | 01 overview                                |
| `capacity_by_state.parquet`      | ~100  | 01 overview, 14 state comparison           |
| `buildout_monthly.parquet`       | ~4 K  | 01 overview, 13 capacity trends            |
| `capacity_by_plz_top5000.parquet`| 5 000 | 02 solar pv, 12 geo map, 14 state compare  |
| `solar_size_classes.parquet`     | ~25   | 02 solar pv                                |
| `wind_hub_height.parquet`        | ~50   | 03 wind onshore                            |
| `ee_quote_by_year.parquet`       | ~30   | 15 ee quote                                |

All aggregates are generated with the same `_col_or_null()` helper so they
degrade gracefully when an entity is missing (e.g. `wind_hub_height`
returns empty when `wind.Nabenhoehe` is absent rather than failing CI).

### 3.5 Publish

- `etl/src/mastr_etl/publish.py` creates a GitHub Release tagged
  `data-YYYY-MM-DD` (idempotent — deletes and recreates the tag) and
  uploads every parquet + the DuckDB file as release assets.
- **Large-blob handling:** GitHub Release assets are capped at 2 GB
  each. The DuckDB file is ~1.9 GB — hugging the limit — so the
  publisher automatically splits any blob >1.9 GB into
  `<name>.partNN` chunks with a SHA-256 sidecar and a `REASSEMBLE.md`
  file. This is what keeps the pipeline green when the DuckDB grows.
- **Fail-soft uploads:** individual asset upload failures retry with
  exponential back-off; after retries exhaust the file is skipped and
  logged, so a single flaky upload doesn't kill a 30-minute pipeline.
- **Retention:** last 14 releases are kept, older ones deleted by the
  "Keep only the last 14 releases" step.

### 3.6 Schema-drift alerting

- `etl/src/mastr_etl/schema_diff.py` compares today's parquet column sets
  against yesterday's and opens a GitHub Issue when columns appear or
  disappear.
- This is the only step that requires human intervention. Typical response
  is (1) verify whether the drift is intentional upstream,
  (2) update `ENTITIES` or `_col_or_null` projections in the ETL, and
  (3) mirror the change in `shiny/R/mastr_data.R::.create_units_view()` so
  the R-side view stays in sync.

---

## 4. The R-side data layer (`shiny/R/mastr_data.R`)

This is the only file every dashboard needs. It gives each app a DuckDB
connection that looks like a local database but actually streams (and
caches) bytes from GitHub Releases on demand.

### 4.1 Release resolution

`.resolve_release()` hits the GitHub API once per session:

```
GET https://api.github.com/repos/{MASTR_REPO}/releases/latest
```

…and memoises the returned tag + base URL. `MASTR_REPO` defaults to
`Tarekchehahde/mastr-shiny`; forkers can override via
`Sys.setenv(MASTR_REPO="your-user/your-fork")`.

A user-supplied personal access token is honoured
(`Sys.getenv("GITHUB_TOKEN")`) but **is never required** — everything
works anonymously against a public repo.

### 4.2 Local aggregate prefetch

On first `mastr_con()` the layer downloads the 7 aggregate Parquets
(~300 KB total) to
`tools::R_user_dir("mastr-shiny", "cache")/<release-tag>/` and rewrites
the `CREATE VIEW` URLs to point at local paths. Every chart that uses
aggregates then renders from local I/O — typically 20 ms per query
instead of 1–3 s.

| Env var             | Default | Effect                                   |
|---------------------|---------|------------------------------------------|
| `MASTR_PREFETCH=0`  | `1`     | Disable prefetch (stream aggregates too) |
| `MASTR_QUERY_CACHE=0`| `1`    | Disable the persistent result cache      |
| `MASTR_REPO`        | `Tarekchehahde/mastr-shiny` | Point at a fork              |

### 4.3 Lazy entity views

The per-entity CREATE VIEWs + the `v_units_all` UNION ALL cost ~30 s on a
cold connection because DuckDB probes each remote Parquet footer to learn
the schema. Most dashboards don't need them: 01 Overview, 13 Capacity
Trends, and 15 EE-Quote read only the aggregate Parquets.

The layer therefore:
1. Creates only the 7 aggregate views on every connect (< 1 s).
2. Lazily creates the 20 entity views + `v_units_all` + the Bundesland
   lookup **only** when a query's SQL text matches the entity regex
   (`.needs_entity_views()`).
3. Memoises `.mastr_env$entities_ready` so the cost is paid exactly once
   per session.

### 4.4 Disk-backed query cache

Every call to `mastr_query(sql, params)` is routed through
`memoise::memoise()` with `cachem::cache_disk()`:

- 256 MB LRU on disk, in
  `tools::R_user_dir("mastr-shiny","cache")/<release-tag>/_queries/`.
- Cache key = normalised SQL + release tag.
- New nightly release → new tag → automatic cache invalidation with zero
  code changes.
- Measured: second call of any query drops to **9 ms** on a warm
  machine, **200 ms** on a cold R session (disk seek + parquet decode).

### 4.5 `mastr_sql_in()` — safe SQL literal list

Base R's `sQuote()` returns Unicode curly quotes (U+2018 / U+2019). DuckDB
treats those as a quoted-identifier delimiter, so
`bundesland_name IN (sQuote("Bayern"))` crashes with
*`Referenced column "Bayern" not found`*. The layer ships a tiny helper:

```r
mastr_sql_in(c("Bayern", "Hessen"))
# -> "'Bayern','Hessen'"
```

…that every dashboard must use when building an `IN (...)` clause.

### 4.6 Offline mode

A single line bypasses GitHub entirely:

```r
mastr_use_local("~/mastr.duckdb")
```

After this, `mastr_con()` returns a read-only DuckDB connection against
the local file and every helper keeps working. Useful on planes, in SCIFs,
or for reproducibility of published analyses.

---

## 5. The visual layer (`shiny/R/ui_helpers.R`)

- **`mastr_page(title, subtitle, …, fluid = FALSE)`** — the single page
  wrapper every dashboard uses. `fluid = FALSE` is `page_fillable()` for
  single-screen "at-a-glance" dashboards (01 Overview, 13 Capacity
  Trends, 15 EE-Quote). `fluid = TRUE` is `page_fluid()` for dashboards
  with scrolling content (tables, maps, long filter panels).
- **`mastr_kpi(title, value, subtitle, color, min_height = "130px")`** —
  a `bslib::value_box()` wrapper that reserves enough vertical space
  for a 3-line content block, uses tabular-nums numerics, and truncates
  overflow with ellipsis.
- **`mastr_theme()`** — Bootstrap 5 / `flatly` bootswatch, Inter font,
  Transtek-friendly palette that maps each energy carrier to a stable
  colour (`solar` = amber, `wind` = blue, `water` = cyan, etc.).
- **Global CSS injected once per page**: slider tick font-size,
  Plotly mode-bar dimming, reactable tabular-nums rows, card header
  typography, `value-box` min-height + ellipsis.

---

## 6. The 15 dashboards

Each app lives in its own folder `shiny/apps/NN_name/` with an `app.R`
and a small README. They are **fully independent** — no shared global
state beyond `mastr_data.R` + `ui_helpers.R`. You can copy any folder,
rename it, and publish your own dashboard.

| # | App                 | Reads only aggregates? | Uses map? | Uses table? |
|---|---------------------|-----------------------|-----------|-------------|
| 01 | overview           | ✔                     |           |             |
| 02 | solar_pv           | —                     |           | ✔           |
| 03 | wind_onshore       | —                     |           | ✔           |
| 04 | wind_offshore      | —                     |           | ✔           |
| 05 | biomass            | —                     |           | ✔           |
| 06 | hydro              | —                     |           | ✔           |
| 07 | geothermal         | —                     |           | ✔           |
| 08 | storage            | —                     |           | ✔           |
| 09 | chp                | —                     |           | ✔           |
| 10 | grid_operators     | —                     |           | ✔           |
| 11 | market_actors      | —                     |           | ✔           |
| 12 | geo_map            | ✔                     | ✔         |             |
| 13 | capacity_trends    | ✔                     |           |             |
| 14 | state_comparison   | ✔                     |           | ✔           |
| 15 | ee_quote           | ✔                     |           |             |

"Reads only aggregates" means the app never references a bare entity name
or `v_units_all`, so `.ensure_entity_views()` is never triggered and the
cold-start is ~2 s instead of ~40 s.

---

## 7. Performance characteristics (measured)

Benchmarked on a 2020 MacBook Pro (M1, 16 GB) against the
`data-2026-04-21` release over a typical residential fibre link.

| Scenario                                      | First run | Warm (disk cache) |
|-----------------------------------------------|-----------|-------------------|
| Cold start, aggregate-only dashboard           | ~2–5 s    | < 1 s             |
| Cold start, unit-level dashboard              | ~40 s     | < 1 s             |
| Per-chart re-render (any dashboard, warm)     | 9–20 ms   | 9–20 ms           |
| Full `SELECT COUNT(*) FROM v_units_all` cold  | 8 s       | 9 ms              |
| Offline mode (`mastr_use_local`) any query    | < 50 ms   | < 50 ms           |

The 40 s cold start for unit-level dashboards is dominated by 20 HTTPS
round trips to read Parquet footers. It's paid exactly once per release
per machine; all subsequent launches hit the disk cache.

---

## 8. Repository layout

```
mastr-shiny/
├── etl/                       # Python pipeline
│   ├── pyproject.toml
│   ├── src/mastr_etl/
│   │   ├── config.py          # entities + Bundesland lookup
│   │   ├── download.py        # aria2c wrapper + retry/cache
│   │   ├── parse.py           # streaming lxml → Parquet
│   │   ├── build_duckdb.py    # schema-aware DuckDB build
│   │   ├── aggregates.py      # pre-rolled aggregate Parquets
│   │   ├── schema_diff.py     # nightly drift detector
│   │   └── publish.py         # GH release + split-blob uploads
│   └── tests/                 # pytest smoke tests
├── shiny/
│   ├── app.R                  # launcher (runGitHub entry point)
│   ├── R/
│   │   ├── mastr_data.R       # remote/local DuckDB data layer
│   │   └── ui_helpers.R       # theme + value box + page wrapper
│   └── apps/                  # 15 self-contained Shiny dashboards
├── docs/
│   ├── SOLUTION.md            # this file
│   ├── RUN.md                 # public-facing quickstart
│   ├── AGENT_HANDOFF.md       # ops + agent vocabulary (e.g. Candida dashboard)
│   ├── ARCHITECTURE.md        # short index into SOLUTION
│   ├── AUTONOMY.md            # CI autonomy state machine
│   ├── DATA_SCHEMA.md         # column-level reference
│   ├── HOW_TO_RUN.md          # long-form run guide (legacy)
│   └── SHINYLIVE.md           # WebAssembly deploy
├── .github/workflows/         # nightly-etl, etl-ci, shinylive-deploy
├── Makefile                   # `make parse`, `make duckdb`, `make shiny`
├── LICENSE                    # MIT (code)
├── LICENSE-DATA.md            # DL-DE-BY-2.0 (data, mandatory attribution)
└── README.md                  # landing page
```

---

## 9. Known limitations & explicit non-goals

**Known limitations (tracked):**

- **Stromspeicher nutzbare Kapazität (MWh)** — lives in a separate
  `AnlagenStromSpeicher_*.xml` that `config.ENTITIES` doesn't ingest yet.
  The storage dashboard (`apps/08_storage`) surfaces power-side KPIs and
  a visible note pointing at the follow-up. Filing PRs that add
  `anlagen_speicher` as a new entity is the natural contribution path.
- **Bundesland code lookup** — the 17-row
  `config.BUNDESLAND` table maps BNetzA's internal IDs (1400–1416) to
  readable names. If the top-N ranking on a detail dashboard looks
  suspicious (e.g. Bremen topping solar-unit counts), the lookup may be
  off vs. the current BNetzA catalog 1808 and should be re-verified
  against the official codelist. One-line fix in `config.py` + a nightly
  release propagates it everywhere.
- **GeoSolarthermie entity** — BNetzA does not ship
  `EinheitenGeoSolarthermie_*.xml` in every nightly; the ETL logs this
  and skips it fault-tolerantly.

**Explicit non-goals:**

- **Historical snapshots.** We keep the last 14 releases. Anyone who
  wants a reference point can fork and bump the "Keep only the last 14
  releases" step.
- **Time-series consumption data.** MaStR is a register, not a
  meter-data store. Consumption time-series belong in a sibling project
  against SMARD / Stromnetz-BE feeds.
- **Personally identifiable data.** The MaStR ZIP is already scrubbed
  by BNetzA; we redistribute as-is. No enrichment against address
  registers, no PII downstream.

---

## 10. Extension points

Common things you might want to add, and where:

| You want to …                                  | Touch these files                                                                  |
|------------------------------------------------|-------------------------------------------------------------------------------------|
| …ingest a new XML entity                       | `etl/src/mastr_etl/config.py` + mirror in `shiny/R/mastr_data.R::.create_units_view` |
| …add a new dashboard                           | Copy any `shiny/apps/NN_…/` → rename → edit title + queries                         |
| …change the palette / fonts                    | `shiny/R/ui_helpers.R::MASTR_PALETTE` + `mastr_theme()`                              |
| …run against a fork                            | `Sys.setenv(MASTR_REPO = "your-user/your-fork")` before `shiny::runApp()`           |
| …host a private instance                       | Fork, make it private, set `GITHUB_TOKEN` in `Sys.setenv()` before launch           |
| …add a new pre-rolled aggregate                | `etl/src/mastr_etl/aggregates.py` + list in `.create_aggregate_views()` (R)         |
| …change the release retention (14 → N)         | `.github/workflows/nightly-etl.yml` — "Keep only the last 14 releases" step         |
| …deploy a WASM build to GitHub Pages           | `.github/workflows/shinylive-deploy.yml` (already wired)                            |

---

## 11. Security & compliance

- **Secrets.** Only `GITHUB_TOKEN` is needed. CI provides it automatically.
  No database credentials, no API keys.
- **PII.** MaStR omits natural-person detail for small private operators
  already. We redistribute as-is. Any downstream combination with
  third-party address registers is the consumer's responsibility.
- **Attribution.** DL-DE-BY-2.0 requires a readable attribution to
  "© Bundesnetzagentur (Stand: YYYY-MM-DD)". This is rendered in the
  footer of every dashboard via `mastr_attribution()` and must be
  preserved by forks.
- **Code licence.** MIT. See [`LICENSE`](../LICENSE).
- **Data licence.** DL-DE-BY-2.0. See [`LICENSE-DATA.md`](../LICENSE-DATA.md).

---

## 12. Sources & references

- Bundesnetzagentur — [MaStR Datendownload](https://www.marktstammdatenregister.de/MaStR/Datendownload)
- BNetzA Katalogwerte (codelist 1808 for Bundesland IDs) — linked from
  the MaStR XML schema documentation
- Datenlizenz Deutschland 2.0 — Namensnennung — [govdata.de/dl-de/by-2-0](https://www.govdata.de/dl-de/by-2-0)
- DuckDB `httpfs` extension — [duckdb.org/docs/extensions/httpfs](https://duckdb.org/docs/extensions/httpfs)
- shinylive (WASM Shiny) — [shinylive.io](https://shinylive.io)
