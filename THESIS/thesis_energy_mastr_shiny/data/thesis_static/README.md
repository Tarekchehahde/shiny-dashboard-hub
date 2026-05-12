# `thesis_static/` — curated tables for Shiny

Files here are **loaded at run time** from the app working directory (`thesis_energy_mastr_shiny/`).

| File | Used by | Columns (expected) |
|------|---------|--------------------|
| **`lithium_projects_de.csv`** | `03_lithium_rohstoff_kontext` | `project_name`, `region`, `bundesland`, `status`, `year_note`, `notes`, `source_url` |

**Edit in git** like normal code: small rows, UTF-8, comma-separated. Prefer HTTPS `source_url` for every factual claim you display.

Optional: add more `.csv` files here and extend app `03` (or new apps) to read them.

## Curated rows in `lithium_projects_de.csv`

The table is **seeded** with a mix of (a) **Germany-focused industrial projects** and (b) **official / statistical reference URLs** (BGR, DERA, Eurostat, EU law). Rows are **not** a complete mine register; **verify status and claims** before citing them in your thesis text—company pages age quickly and Eurostat needs your own HS series selection.
