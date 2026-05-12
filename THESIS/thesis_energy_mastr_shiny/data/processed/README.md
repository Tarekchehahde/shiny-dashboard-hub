# `processed/` — cleaned tables for analysis & charts

Use this for outputs you generate from **`../raw/`** (e.g. R `readxl` → tidy CSV, joined Eurostat tables, normalised permit dates).

- Prefer **small, documented** `.csv` or `.parquet` if licence allows redistribution in the repo.
- If a file is **derived from** `raw/`, note the script name and commit hash in a comment row or in `../README.md` ingest section.
- **Do not** put secrets or unpublished third-party data here without clearance.
