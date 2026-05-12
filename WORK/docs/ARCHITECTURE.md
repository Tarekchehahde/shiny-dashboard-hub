# Architecture

```
                   ┌────────────────────────────┐
                   │  BNetzA — MaStR nightly    │
                   │  Gesamtdatenauszug (ZIP)   │  ~2.8 GB
                   └─────────────┬──────────────┘
                                 │ HTTPS GET, 06:00 UTC
                                 ▼
       ┌──────────────────────────────────────────────┐
       │ GitHub Actions runner (ubuntu-latest, 14 GB) │
       │ ─────────────────────────────────────────────│
       │ mastr-download  →  mastr-parse (streaming)   │
       │ mastr-build-db  →  mastr-aggregates          │
       │ mastr-schema-diff (opens issue on change)    │
       │ mastr-publish   →  gh release upload         │
       └──────────────────────────┬───────────────────┘
                                  │ artifacts
                                  ▼
          ┌──────────────────────────────────────┐
          │  GitHub Release  data-YYYY-MM-DD     │
          │  ├── solar.parquet                   │
          │  ├── wind.parquet                    │
          │  ├── …                               │
          │  ├── mastr.duckdb                    │
          │  └── aggregates/*.parquet            │
          └──────────────┬───────────────────────┘
                         │ HTTPS Range requests
                         ▼
            ┌──────────────────────────────┐
            │ Shiny apps in RStudio        │
            │ DuckDB httpfs extension      │
            │ reads only the bytes it needs│
            └──────────────┬───────────────┘
                           │ user never downloads XML
                           ▼
                  ┌─────────────────┐
                  │ User's RStudio  │
                  │ — a few MB of R │
                  └─────────────────┘
```

## Why this design

### Problem
The MaStR XML dump is a delight for thorough analysis and a pain for
distribution: ~2.8 GB zipped, ~25 GB unzipped, dozens of files, plenty of
German-locale decimals, and a schema that evolves twice a year.

### Solution
**Separate the heavy ETL from the user.** CI owns the XML. Users only ever
see Parquet (columnar, compressed, schema-stable). DuckDB's `httpfs`
extension lets R/Python clients query Parquet over plain HTTPS with range
requests, so the user's "download" is whatever bytes their query actually
touches — typically a few KB per dashboard refresh.

### Why Parquet + DuckDB vs. a hosted API
- **No server cost.** GitHub Releases are free and effectively unlimited for
  public repos.
- **No rate limits.** DuckDB-httpfs is a direct CDN read.
- **Reproducibility.** Anyone can `wget` a release tag and reproduce a
  Shiny chart bit-exactly.
- **Offline-capable.** `mastr_use_local("mastr.duckdb")` — one line — makes
  the whole system work on a plane.

### Why shinylive on top
For casual users who don't want to install R, `shinylive` compiles the same
Shiny apps to WebAssembly and hosts them on GitHub Pages. The WASM runtime
loads the small aggregate Parquets (<10 MB total), not the full DuckDB, so it
still feels instant.

## Data flow details

| Stage        | Runtime | Artifacts produced | Disk |
|-------------|---------|--------------------|------|
| download    | 5 min   | `mastr-latest.zip` + `.sha256` | 2.8 GB |
| parse       | 20 min  | `<entity>.parquet` × ~20 | 1.5 GB |
| build-db    | 3 min   | `mastr.duckdb` | 600 MB |
| aggregates  | 30 s    | `aggregates/*.parquet` | 5 MB |
| publish     | 3 min   | GH Release assets | — |
| **Total**   | **≈ 30 min** | | peak ≈ 5 GB |

## Files an end user downloads

- **RStudio path A (recommended):** ~2 MB of R code (WORK/shiny/), + first-query
  DuckDB column metadata (~5 MB fetched on demand, cached). Queries touch
  maybe 10–50 MB of Parquet row groups over the course of a session.
- **RStudio path B (offline):** ~600 MB DuckDB file, one-shot download.
- **Browser path:** nothing; runs on github.io.

## Component contracts

### Parse (`mastr_etl.parse`)
- **Input:** `mastr-latest.zip`
- **Output:** one `{entity}.parquet` per entity, snappy-compressed
- **Invariant:** column set is a superset of the previous day's schema
- **Failure modes:** corrupt records are skipped (lxml `recover=True`);
  cast failures yield NULL, never raise

### Build-DB (`mastr_etl.build_duckdb`)
- **Input:** the parquet directory
- **Output:** `mastr.duckdb` with one table per entity + 3 views
  (`v_units_all`, `v_capacity_by_state`, `v_buildout_monthly`, `v_capacity_by_plz`)
- **Contract:** `v_units_all` always exposes
  `(mastr_nr, energietraeger, bruttoleistung_kw, bundesland_name,
    plz, lat, lon, inbetriebnahme_datum, betriebsstatus)`

### Shiny loader (`WORK/shiny/R/mastr_data.R`)
- Mirrors the DuckDB view definitions so a fresh DuckDB instance pointed at
  the remote Parquet files serves exactly the same queries as the local file
- No entity coupling outside of `.remote_entities` — add a new entity to
  both `config.py` and `mastr_data.R`, nothing else

## Security & secrets

- Only secret used is `GITHUB_TOKEN`, which CI provides automatically.
- No PII in MaStR for small private operators — the ZIP omits natural-person
  details. We redistribute as-is.
- Attribution (DL-DE-BY-2.0) is rendered in every dashboard footer.

## Non-goals

- **Historical snapshots.** We keep the last 14 releases; anyone who wants a
  reference point can fork and extend the retention logic in the
  `nightly-etl.yml` "Keep only the last 14 releases" step.
- **Time-series consumption data.** MaStR is a register, not a meter-data
  store; reserve that for SMARD / Stromnetz-BE feeds in a sibling project.
