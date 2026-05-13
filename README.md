# MaStR monorepo — `WORK` + `THESIS`

One GitHub repository for **two top-level product lines** that both use **BundesnetzAgen­tur MaStR** data (via the same nightly release assets where applicable). Use **one clone on any laptop**; open the folder that matches what you are doing that day.

| Folder | Use on | Contents |
|--------|--------|----------|
| **[`WORK/`](WORK/)** | This machine / Candida-style flagship dashboards and the rest of the production Shiny suite | Python **ETL**, **GitHub Actions** (root `.github/`), launcher + apps under `WORK/shiny/`, docs under `WORK/docs/` |
| **[`THESIS/`](THESIS/)** | Other laptop / battery & thesis dashboards | Self-contained **`THESIS/thesis_energy_mastr_shiny/`** — thesis launcher, three battery-related apps, `R/mastr_data.R` |

**Default branch:** `main` (there is no requirement to use a branch named `master`; agents and `runGitHub` should use `ref = "main"` unless you add `master` yourself.)

### Path trap — `runGitHub` `subdir` must include `WORK/` or `THESIS/`

The repo was reorganised into a **monorepo**. Production Shiny is **not** at repo root `shiny/` anymore.

| Wrong (old) | Right (current) |
|---------------|-----------------|
| `subdir = "shiny"` | `subdir = "WORK/shiny"` |
| `subdir = "shiny/apps/most_visited"` | `subdir = "WORK/shiny/apps/most_visited"` |

If you see **`No Shiny application exists at the path …/mastr-shiny-main/shiny/apps/...`**, you are still using the **pre-monorepo** `subdir`. Use the **`WORK/shiny/...`** form above. Thesis launcher: **`THESIS/thesis_energy_mastr_shiny`** (not `thesis_energy_mastr_shiny` at repo root).

See also: [`WORK/docs/AGENT_HANDOFF.md`](WORK/docs/AGENT_HANDOFF.md) §0, [`WORK/docs/RUN.md`](WORK/docs/RUN.md) §Monorepo paths.

---

## Verify layout (after `git pull` or before teaching someone `runGitHub`)

**A — Local clone (repository root):** these files must exist.

```bash
# macOS / Linux / Git Bash
test -f WORK/shiny/app.R && test -f WORK/shiny/apps/most_visited/app.R && \
  test -f THESIS/thesis_energy_mastr_shiny/run_app_thesis_energy.R && echo "OK: monorepo layout"
```

```powershell
# Windows PowerShell (repo root)
@("WORK/shiny/app.R","WORK/shiny/apps/most_visited/app.R","THESIS/thesis_energy_mastr_shiny/run_app_thesis_energy.R") | ForEach-Object { if (-not (Test-Path $_)) { throw "Missing $_" } }; "OK: monorepo layout"
```

**B — No clone (sanity-check GitHub `main` has the launcher):**

```r
u <- "https://raw.githubusercontent.com/Tarekchehahde/mastr-shiny/main/WORK/shiny/app.R"
f <- tempfile(fileext = ".R")
if (download.file(u, f, quiet = TRUE) != 0L) stop("WORK/shiny/app.R not reachable — check branch/network")
if (!file.exists(f) || file.info(f)$size < 100) stop("Unexpected download — wrong path?")
unlink(f)
message("OK: WORK/shiny/app.R on GitHub main")
```

**C — Quick Shiny smoke test (downloads tarball once):**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "WORK/shiny/apps/most_visited", ref = "main", launch.browser = FALSE)
# If this errors with path …/shiny/apps/… you used the old subdir; use WORK/shiny/apps/…
```

**D — ETL / CI (contributors):** from repo root, Python 3.12+ with network for pip:

```bash
pip install -e "WORK/etl[dev]" && ruff check WORK/etl && pytest WORK/etl/tests -q
```

---

## Quick links

- **WORK runbook:** [`WORK/docs/RUN.md`](WORK/docs/RUN.md) — `runGitHub` and `runApp` paths start with `WORK/shiny/…`.
- **WORK agent handoff:** [`WORK/docs/AGENT_HANDOFF.md`](WORK/docs/AGENT_HANDOFF.md) — Candida / flagship context, ETL, release resolution.
- **RStudio matrix (both tracks):** [`WORK/docs/RSTUDIO_CONTEXTS.md`](WORK/docs/RSTUDIO_CONTEXTS.md) — includes THESIS `runGitHub` after the monorepo move.
- **THESIS run + env:** [`THESIS/thesis_energy_mastr_shiny/README.md`](THESIS/thesis_energy_mastr_shiny/README.md) and [`THESIS/thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md`](THESIS/thesis_energy_mastr_shiny/AGENT_CONTEXT_THESIS_MASTR_SHINY.md).

---

## `runGitHub` (single repo, two `subdir` roots)

**WORK launcher (production dashboards, incl. flagship / “most visited”):**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde", subdir = "WORK/shiny", ref = "main")
```

**WORK single app (example):**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "WORK/shiny/apps/most_visited", ref = "main")
```

**THESIS launcher:**

```r
shiny::runGitHub("mastr-shiny", "Tarekchehahde",
                 subdir = "THESIS/thesis_energy_mastr_shiny", ref = "main")
```

---

## Clone layout (any PC)

```bash
git clone https://github.com/Tarekchehahde/mastr-shiny.git
```

```r
# WORK
shiny::runApp("mastr-shiny/WORK/shiny")

# THESIS
setwd("mastr-shiny/THESIS/thesis_energy_mastr_shiny")
shiny::runApp("run_app_thesis_energy.R")
```

---

## Data & ETL

- **BNetzA** publishes the official MaStR export.
- **Nightly ETL** still lives under **`WORK/etl/`**; workflows remain in **`.github/workflows/`** at the repository root.
- **GitHub Releases** on this repo (`data-YYYY-MM-DD`) are produced by that pipeline — same consumer URLs as before, with **code paths** under `WORK/` for contributors.

---

## Licence

MaStR data: [Datenlizenz Deutschland — Namensnennung](LICENSE-DATA.md). Code: MIT where noted in [LICENSE](LICENSE).
