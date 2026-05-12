# shinylive build — zero-install browser dashboards

The `shinylive-deploy.yml` workflow compiles every app in `WORK/shiny/apps/` into
a static site that runs entirely in the browser via WebAssembly.

## Limitations vs. RStudio

| Feature | RStudio | shinylive |
|---|---|---|
| Reads full DuckDB | ✅ | ⚠️ aggregate parquets only |
| Custom SQL | ✅ | ⚠️ limited to pre-defined views |
| Full entity tables | ✅ | ❌ too heavy for WASM |
| First-load time | instant | 5–10 s (Pyodide init) |
| Install burden | R + ~12 packages | none |

## Local preview

```r
install.packages("shinylive")
shinylive::export("shiny", "_site", subdir = "apps")
# then serve the static site:
httpuv::runStaticServer("_site", port = 8000)
```

## Deployment

Automatic. Every successful `nightly-etl` run triggers `shinylive-deploy`,
which:

1. Installs R + `shinylive`
2. Exports every app to `_site/apps/<id>/`
3. Publishes the result to GitHub Pages.

The Pages URL appears in the repo's "About" sidebar after the first deploy.

## Tuning file size

If the WASM bundle becomes too heavy, move rarely used apps into a
`shiny/apps-heavy/` sub-directory (keep them for RStudio) and exclude that
folder from the export call in `shinylive-deploy.yml`.
