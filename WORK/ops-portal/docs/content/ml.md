# Machine learning on this server

This VPS is primarily a **Shiny dashboard host**, not a dedicated ML platform. ML work happens through **RStudio Server** (installed) or optional Python tooling you install yourself.

---

## RStudio Server (installed)

**URL:** [http://82.165.167.86:8787/](http://82.165.167.86:8787/)  
**Login:** required (credentials are private — not listed in public docs).

This is the main environment for development and ML on the server:

| Use case | R packages |
|----------|------------|
| Classical ML | **tidymodels**, **caret**, **randomForest**, **xgboost** |
| Deep learning | **torch** (R) |
| EDA & reports | **R Markdown**, **ggplot2**, **duckdb** |
| Same stack as production Shiny apps | **shiny**, **bslib**, **plotly** |

### Quick start in RStudio

```r
# Example: load MaStR data the same way dashboards do
source("/opt/mastr-shiny/WORK/shiny/R/mastr_data.R")

# tidymodels workflow
library(tidymodels)
# ... split, recipe, model, evaluate
```

Project code lives at `/opt/mastr-shiny/` on the VPS (same repo as the dashboards).

---

## Python / JupyterLab (not installed)

JupyterLab is **not** set up yet. If you need scikit-learn, pandas, or PyTorch in the browser:

1. SSH to the server
2. Install JupyterLab for the `rstudio` user (or a dedicated user)
3. Put nginx behind a password-protected path (do **not** expose an open notebook server)

RStudio already supports **reticulate** if you only need occasional Python from R.

---

## What does not belong on this VPS

| Tool | Why |
|------|-----|
| Orange, KNIME, RapidMiner | Desktop GUI apps — run locally |
| Heavy GPU training | No GPU on this VPS; use cloud or local machine |
| Public unauthenticated notebooks | Security risk on a public IP |

---

## Relation to the dashboards

The Shiny apps on this server are **interactive visualizations**, not ML training pipelines. Typical workflow:

1. **Train / explore** in RStudio on `:8787`
2. **Deploy** results as a Shiny app under `WORK/shiny/apps/`
3. **Monitor** live usage via Grafana and site traffic

---

## Resources

- [Mission Control](/portal/) — gateway back to hub & monitoring
- [Infrastructure](?doc=infrastructure) — ports, deploy paths
- [Documentation index](/portal/docs/) — all guides
