# WORK — production MaStR dashboards & ETL

Everything for **daily / Candida-style** use of the main Shiny suite and the **nightly Python pipeline** that builds Parquet + DuckDB and publishes **GitHub Releases** on `Tarekchehahde/mastr-shiny`.

| Path | Role |
|------|------|
| [`shiny/`](shiny/) | R/Shiny launcher + all production apps (incl. flagship `apps/most_visited`). |
| [`etl/`](etl/) | Python package `mastr_etl` — download, parse, DuckDB, aggregates, publish. |
| [`docs/`](docs/) | `RUN.md`, `AGENT_HANDOFF.md`, `RSTUDIO_CONTEXTS.md`, architecture, schema. |
| [`Makefile`](../Makefile) (repo root) | Local developer shortcuts for `WORK/etl` (optional). |

**Start here:** [`docs/RUN.md`](docs/RUN.md) — all `subdir` values use the prefix **`WORK/shiny/…`**.

Sister tree for battery / thesis-only apps: [`../THESIS/README.md`](../THESIS/README.md).
