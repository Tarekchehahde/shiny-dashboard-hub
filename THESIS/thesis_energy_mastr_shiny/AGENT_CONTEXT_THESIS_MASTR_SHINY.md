# Agent context — Thesis track (Batterie, Speicher, Lithium) — MaStR Shiny

**Purpose:** Hand off the **thesis / research** Shiny track. This code lives in **`Tarekchehahde/mastr-shiny`** under **`THESIS/thesis_energy_mastr_shiny/`** (same monorepo as production **WORK/** dashboards and ETL — not the Transtek website repo).

**Remote:** The **authoritative** source is **GitHub** `Tarekchehahde/mastr-shiny`, branch **`main`**. A sibling **`MaStR/`** folder on a laptop (optional README stubs) is **not** the codebase; commit thesis changes **here** under **`THESIS/`**.

---

## Mirror: **WORK** track (same repo)

- **WORK** ([`Tarekchehahde/mastr-shiny`](https://github.com/Tarekchehahde/mastr-shiny) → folder **`WORK/`**): nightly **ETL** + production Shiny (Candida / flagship = `WORK/shiny/apps/most_visited/`). Publishes dated GitHub Releases consumed by `R/mastr_data.R` here unless you override **`MASTR_REPO`**. Agent handoff: [`WORK/docs/AGENT_HANDOFF.md`](https://github.com/Tarekchehahde/mastr-shiny/blob/main/WORK/docs/AGENT_HANDOFF.md).
- **Optional local umbrella:** some machines keep **`MaStR/`** with README stubs — metadata only; clone **`mastr-shiny`** once for both WORK and THESIS.

---

## Copy this prompt into a new chat

```
I'm continuing the MaStR Shiny thesis track (battery storage, technology mix, lithium/raw-materials context).

Repo: Tarekchehahde/mastr-shiny
Folder: THESIS/thesis_energy_mastr_shiny/  (entire R working directory for this track)

Please read:
1. THESIS/thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md — this file
2. THESIS/thesis_energy_mastr_shiny/README.md — runbook + env vars

Constraints:
- This folder is self-contained: run_app_thesis_energy.R, R/, apps/thesis_battery_lithium/, data/.
- MaStR data: R/mastr_data.R — GitHub Releases / DuckDB httpfs; default MASTR_REPO is Tarekchehahde/mastr-shiny (same as WORK track) unless overridden.
- Lithium app (03_*) uses data/thesis_static/lithium_projects_de.csv — not MaStR.

Working directory for R (from clone root): THESIS/thesis_energy_mastr_shiny/
```

---

## What this project is

| Layer | Role |
|--------|------|
| **Thesis launcher** | `run_app_thesis_energy.R` — separate menu for thesis apps only. |
| **Data layer** | `R/mastr_data.R` — remote Parquet/DuckDB via GitHub Releases (default repo configurable). |
| **UI helpers** | `R/ui_helpers.R` — shared bslib pieces. |

Production MaStR dashboards (launcher + 01–24 style apps) live in the **same** repository under **`WORK/shiny/`** — do not merge this thesis launcher into **`WORK/`** unless the user explicitly asks.

---

## Thesis apps

| Path | Title | Data |
|------|-------|------|
| `apps/thesis_battery_lithium/01_batteries_deutschland` | Batteriespeicher Deutschland | MaStR |
| `apps/thesis_battery_lithium/02_speicher_technologie_mix` | Speicher-Technologien | MaStR |
| `apps/thesis_battery_lithium/03_lithium_rohstoff_kontext` | Lithium & Rohstoffe (Kontext) | CSV + context |

---

## How to run

From **`thesis_energy_mastr_shiny/`**:

```r
install.packages("renv"); renv::restore()   # once per machine
shiny::runApp("run_app_thesis_energy.R")
```

Single app:

```r
shiny::runApp("apps/thesis_battery_lithium/01_batteries_deutschland")
```

From GitHub (no full clone of parent folder structure — `subdir` must point at this app):

```r
shiny::runGitHub(
  "mastr-shiny",
  "Tarekchehahde",
  ref    = "main",
  subdir = "THESIS/thesis_energy_mastr_shiny/apps/thesis_battery_lithium/01_batteries_deutschland"
)
```

---

## Troubleshooting

See **README.md** in this folder (release API, `MASTR_TAG`, `GITHUB_TOKEN`, `MASTR_LOCAL_DB`).

---

## Repo map

```
mastr-shiny/
└── THESIS/
    └── thesis_energy_mastr_shiny/
        ├── run_app_thesis_energy.R
        ├── renv.lock
        ├── R/mastr_data.R
        ├── R/ui_helpers.R
        ├── apps/thesis_battery_lithium/
        └── data/thesis_static/lithium_projects_de.csv
```

*Last updated: monorepo — thesis tree under `THESIS/` in `Tarekchehahde/mastr-shiny` alongside `WORK/` (ETL + production Shiny).*
