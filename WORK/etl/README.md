# mastr-etl

Python pipeline that turns the BNetzA Marktstammdatenregister XML dump into
columnar Parquet and a query-ready DuckDB index.

```
ZIP (~2.8 GB)
   │  download.py     -- streamed, retried, SHA-256 verified
   ▼
*.xml  (~80 files, ~25 GB unpacked)
   │  parse.py        -- lxml.iterparse, constant memory, per-entity Parquet
   ▼
data/parquet/<entity>.parquet     (~1.5 GB total, snappy)
   │  build_duckdb.py -- views, indices, Bundesland lookups
   ▼
data/mastr.duckdb                 (~600 MB)
   │  aggregates.py   -- pre-rolled small slices for shinylive
   ▼
data/parquet/aggregates/*.parquet (~5 MB total)
   │  publish.py      -- gh release create / upload
   ▼
GitHub Release: tag = data-YYYY-MM-DD
```

Designed to run unattended in `ubuntu-latest` (~25 min, fits in 14 GB
ephemeral disk by streaming and immediately deleting source XML once each
entity is parsed).

## Local dev

```bash
make venv install
make all      # download + parse + duckdb + aggregates  (~30 min, ~5 GB peak disk)
make test
```
