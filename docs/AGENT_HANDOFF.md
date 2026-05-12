# Agent handoff — MaStR-Shiny operations & naming (2026-05-12)

This file is for **humans and coding agents** on any machine. It records what was diagnosed and changed when the **Flagship / “Most Visited”** solar dashboard showed **stale or implausible** numbers (e.g. **May 2026 = 0**, **April 2026** far too low, **Stand** stuck on an old date).

---

## 1. Internal vocabulary: **“Candida dashboard”**

Across the repo (comments, this doc, some Roxygen), **“Candida”** refers to an **internal Tableau workbook / monthly panel** that the in-house team used as a visual reference. In code, the **R Shiny equivalent** is:

| Codename / agent search term | Location | Shiny launcher label |
|--------------------------------|----------|------------------------|
| **Candida dashboard**, **Candida panel**, **Flagship (Tableau parity)** | `shiny/apps/most_visited/` | **“Most Visited”** (`id = "most_visited"`) |

**When talking to another agent**, you can say: *“Fix the **Candida dashboard** path”* or *“the **most_visited** flagship”* — they mean the same app. **End-user UI** no longer shows the name “Candida”; it remains in **comments and docs** for traceability.

---

## 2. Data path (how Shiny gets MaStR)

1. **BNetzA** publishes the MaStR Gesamtdatenauszug (ZIP/XML).
2. **GitHub Actions** (`/.github/workflows/nightly-etl.yml`) downloads, parses to Parquet, builds DuckDB, uploads assets to a **GitHub Release** tagged `data-YYYY-MM-DD` (UTC date from the workflow unless `workflow_dispatch` **tag override** is set).
3. **Shiny** (`shiny/R/mastr_data.R`) resolves which release to use, then queries **remote Parquet** via **DuckDB `httpfs`** (no local XML).

---

## 3. Incident summary (why numbers looked “wrong”)

### 3.1 GitHub **`/releases/latest`** pointed at an old snapshot

The REST endpoint **`/repos/{owner}/{repo}/releases/latest`** follows GitHub’s **“Latest”** flag, not “newest `data-*` by calendar”. An older tag (**`data-22-04-2026`**) stayed **Latest** while newer releases (**`data-2026-05-04`**, etc.) existed. Shiny originally used only **`/releases/latest`**, so users saw **Stand** on **22-04-2026** and **incomplete** 2026 months.

**Fix (client):** `shiny/R/mastr_data.R` — list releases, keep non-draft, non-prerelease tags starting with **`data-`**, pick the one with the greatest **`published_at`**. Optional env: **`MASTR_TAG`** to pin a tag; **`MASTR_REPO`** for forks. Fallback remains **`/releases/latest`**.

**Commit reference:** `6cc34dc` (*fix(data): resolve newest data-* release by published_at; pin Latest on publish*).

### 3.2 Nightly **cleanup** deleted the wrong releases

Step **“Keep only the last 14 releases”** used **`sort_by(.createdAt)`**. Many **`data-*`** releases shared the **same** GitHub **`created_at`**, so sort order was **unstable**; **`reverse | .[14:]`** could drop **newly published** nightlies immediately after publish. Result: workflow **green**, but **no new releases** after **`data-2026-05-05`** for several days.

**Fix (CI):** same workflow step now sorts by **`publishedAt`**. Added **“Verify release exists”** after publish (`gh release view "$TAG"`).

**Commit reference:** `a33a859` (*fix(ci): retain releases by publishedAt; verify release after publish*).

### 3.3 Publisher never re-pinned **Latest**

**Fix (ETL):** `etl/src/mastr_etl/publish.py` — `gh release create … --latest` and **`gh release edit <tag> --latest`** after a successful full upload so **`/releases/latest`** matches the nightly snapshot when clients still use it.

### 3.4 Partial current month (not an ETL failure)

For **YTD through the current calendar month**, totals for **that month** stay low until the MaStR export and registrations catch up. Compare footer **Stand** to the month before treating a dip as a bug.

### 3.5 Thesis / downstream projects

Any **other** Shiny (or R) project that reuses **`shiny/R/mastr_data.R`** or the same **GitHub Release** URLs consumes **this** ETL output — there is no separate MaStR publish for a thesis fork unless you maintain one. For **reproducible** thesis numbers, pin **`MASTR_TAG`** (see [`RSTUDIO_CONTEXTS.md`](RSTUDIO_CONTEXTS.md)).

---

## 4. Files touched (quick index)

| Area | File | Role |
|------|------|------|
| Shiny release pick | `shiny/R/mastr_data.R` | Newest `data-*` by `published_at`; `MASTR_TAG` / `MASTR_REPO` |
| Shiny UX | `shiny/apps/most_visited/app.R` | Flagship charts + table; comments keep “Candida” for parity notes |
| Launcher | `shiny/app.R` | Dashboard list; comments keep flagship ↔ Tableau context |
| ETL publish | `etl/src/mastr_etl/publish.py` | `--latest` / `release edit --latest` |
| CI | `.github/workflows/nightly-etl.yml` | `publishedAt` retention + post-publish verify |
| User cache note | `shiny/README.md` | `MASTR_TAG` example |

---

## 5. Operational checklist for agents

1. **Footer “Stand”** = suffix of the resolved release tag (`data-` stripped). If it lags calendar by many days, check **Releases** on GitHub and **`mastr-nightly-etl`** logs (Publish + Verify steps).
2. **Force a run:** Actions → **mastr-nightly-etl** → **Run workflow** → branch **main**; leave **tag override** empty for **`data-$(date -u +%F)`** in UTC.
3. **Pin a snapshot in R:** `Sys.setenv(MASTR_TAG = "data-2026-05-12")` before `runApp` / after `library(shiny)`.
4. **Do not** use ad-hoc tag shapes like **`data-22-04-2026`** (DD-MM-YYYY inside tag); pipeline and sorting assume **`data-YYYY-MM-DD`**.

---

## 6. Related documentation

- [`RUN.md`](RUN.md) — launch commands.
- [`RSTUDIO_CONTEXTS.md`](RSTUDIO_CONTEXTS.md) — work vs. thesis env + full `runGitHub` list.
- [`SOLUTION.md`](SOLUTION.md) — architecture and pipeline.
- [`AUTONOMY.md`](AUTONOMY.md) — CI autonomy model.

---

*Last updated: 2026-05-12 (session: release resolution, CI retention bug, publish Latest pin, UI copy neutralised for “Candida” while retaining code comments for agents).*
