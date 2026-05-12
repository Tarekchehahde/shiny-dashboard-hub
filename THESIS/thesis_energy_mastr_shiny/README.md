# `thesis_energy_mastr_shiny/` — battery / thesis Shiny (monorepo)

Part of **`Tarekchehahde/mastr-shiny`**, folder **`THESIS/`**. Production dashboards + ETL live under **`WORK/`** in the same repository.

## Run

```r
# From this directory as working directory:
shiny::runApp("run_app_thesis_energy.R")
```

**From GitHub (no clone):**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "THESIS/thesis_energy_mastr_shiny", ref = "main")
```

This loads **`app.R`** (thesis menu). Choosing **Start** ends the menu session and opens the selected app in a **new** Shiny run (via `session$onSessionEnded`). If the child fails to start (e.g. temp extract cleaned early), clone the repo and use `shiny::runApp("run_app_thesis_energy.R")`, or call `runGitHub` with a single app `subdir` (see below).

- **`R/mastr_data.R`** — GitHub Releases + DuckDB `httpfs`; default **`MASTR_REPO`** is often **`Tarekchehahde/transtek`**. Override with **`MASTR_REPO`**, **`MASTR_TAG`**, or **`MASTR_LOCAL_DB`** as needed.
- **App `03_*`** uses **`data/thesis_static/lithium_projects_de.csv`** (not MaStR).

See **`AGENT_CONTEXT_THESIS_MASTR_SHINY.md`** for agents and **`apps/thesis_battery_lithium/README.md`** for troubleshooting.
