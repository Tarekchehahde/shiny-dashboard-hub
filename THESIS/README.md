# THESIS — battery / research Shiny track

Isolated **thesis** dashboards (Germany batteries, storage technology mix, lithium CSV context). Intended for the **second laptop** or any session where you only need this bundle — still **the same Git repo** as [`WORK/`](../WORK/) so agents and `runGitHub` use one remote.

| Path | Role |
|------|------|
| [`thesis_energy_mastr_shiny/`](thesis_energy_mastr_shiny/) | Entire R working directory: `run_app_thesis_energy.R`, `R/`, `apps/`, `data/thesis_static/`. |

**Run:** set working directory to `THESIS/thesis_energy_mastr_shiny/`, then `shiny::runApp("run_app_thesis_energy.R")`.

**From GitHub (no clone):**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "THESIS/thesis_energy_mastr_shiny", ref = "main")
```

**Data:** `thesis_energy_mastr_shiny/R/mastr_data.R` — GitHub Releases / DuckDB `httpfs`; default `MASTR_REPO` is often `Tarekchehahde/transtek` unless you override (see app README + agent context).

**Agent handoff:** [`thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md`](thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md).

Production + ETL: [`../WORK/README.md`](../WORK/README.md).
