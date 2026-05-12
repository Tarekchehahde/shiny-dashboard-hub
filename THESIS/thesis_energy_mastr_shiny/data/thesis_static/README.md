# `thesis_static/` — curated tables for Shiny

Files here are **loaded at run time** from the app working directory (`thesis_energy_mastr_shiny/`).

| File | Used by | Columns (expected) |
|------|---------|--------------------|
| **`lithium_projects_de.csv`** | `03_lithium_rohstoff_kontext` | `project_name`, `region`, `bundesland`, `status`, `year_note`, `notes`, `source_url` |

**Edit in git** like normal code: small rows, UTF-8, comma-separated. Prefer HTTPS `source_url` for every factual claim you display.

Optional: add more `.csv` files here and extend app `03` (or new apps) to read them.
