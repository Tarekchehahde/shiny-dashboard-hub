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

This loads **`app.R`** (thesis menu). In a plain `runGitHub` session, **Start** may only return a path and exit; for the **menu → child app** chain in RStudio, use `shiny::runApp("run_app_thesis_energy.R")` after cloning, or point `runGitHub` at a single app, e.g. `subdir = "THESIS/thesis_energy_mastr_shiny/apps/thesis_battery_lithium/01_batteries_deutschland"`.

- **`R/mastr_data.R`** — GitHub Releases + DuckDB `httpfs`; default **`MASTR_REPO`** is often **`Tarekchehahde/transtek`**. Override with **`MASTR_REPO`**, **`MASTR_TAG`**, or **`MASTR_LOCAL_DB`** as needed.
- **App `03_*`** uses **`data/thesis_static/lithium_projects_de.csv`** (not MaStR).

See **`AGENT_CONTEXT_THESIS_MASTR_SHINY.md`** for agents and **`apps/thesis_battery_lithium/README.md`** for troubleshooting.
