# Data Licence — MaStR (Marktstammdatenregister)

The data redistributed by this project as Parquet/DuckDB artifacts originates
from the **Bundesnetzagentur (BNetzA)** Marktstammdatenregister.

It is licensed under:

> **Datenlizenz Deutschland — Namensnennung — Version 2.0**
> ("Data licence Germany — attribution — Version 2.0", DL-DE-BY-2.0)
> https://www.govdata.de/dl-de/by-2-0

## Required attribution

Every redistribution, including this repository's GitHub Releases, Parquet
files, DuckDB databases, and the Shiny dashboards built on top of them, must
display the following notice:

> Datenquelle: Marktstammdatenregister — © Bundesnetzagentur (Stand: <YYYY-MM-DD>),
> bereitgestellt unter Datenlizenz Deutschland — Namensnennung — Version 2.0
> (https://www.govdata.de/dl-de/by-2-0).

Each Shiny app in `WORK/shiny/apps/` renders this notice in its footer.

## What this project adds

- Conversion of the BNetzA XML dump to columnar Parquet
- A DuckDB index with views for cross-entity queries
- Pre-aggregated rollups for the in-browser shinylive build

These derived artifacts are also distributed under DL-DE-BY-2.0 to preserve
attribution.

## Code licence

All code in this repository (`WORK/etl/`, `WORK/shiny/`, `.github/workflows/`, `WORK/docs/`, `THESIS/`)
is released under the MIT licence — see [`LICENSE`](LICENSE).
