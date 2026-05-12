# Thesis data storage (`thesis_energy_mastr_shiny/data/`)

Use this tree for **lithium / raw materials / project evidence** that **MaStR does not provide**. MaStR-only analysis stays in DuckDB/Parquet via `R/mastr_data.R`; anything geological, permitting, trade snapshots, or hand-curated projects lives **here**.

| Path | Purpose |
|------|--------|
| **`thesis_static/`** | Small **curated** tables shipped with the repo and read by Shiny (e.g. `lithium_projects_de.csv` for app `03_lithium_rohstoff_kontext`). **Version in git**; every row should have a **`source_url`** or documented offline source. |
| **`raw/`** | **Downloads & extracts** (PDFs, CSV dumps, API snapshots). **Do not commit large binaries** unless they are tiny; default is ignore-all except `README.md` (see `raw/.gitignore`). |
| **`processed/`** | **Cleaned** tables derived from `raw/` (R/Python outputs), ready for charts or optional merge into `thesis_static/`. Prefer small `.csv` / `.parquet` under version control when allowed by licence. |

## Provenance (thesis hygiene)

For each dataset you add, note in **`raw/README.md`** or a sibling `SOURCES.md`:

- Provider (e.g. BGR, DERA, Eurostat, Landesamt, company IR).
- Retrieval date and URL (or “offline document” + file name in `raw/`).
- Licence / redistribution rules (thesis-only vs publishable in repo).

## Shiny app wiring

- App **`03_lithium_rohstoff_kontext`** reads **`thesis_static/lithium_projects_de.csv`** (path relative to `thesis_energy_mastr_shiny/`).

If you add new static tables for other apps, keep them under **`thesis_static/`** and document columns here.
