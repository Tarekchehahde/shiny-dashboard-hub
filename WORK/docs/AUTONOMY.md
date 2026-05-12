# Autonomy model

## The short answer

**95% hands-off.** You interact with the system 3–6 times a year: when the
BNetzA schema drifts (it does, roughly every 6 months) and when you want a
new dashboard.

## What runs by itself

| Loop | Trigger | Action | Evidence |
|---|---|---|---|
| Ingest | cron 06:00 UTC daily | `nightly-etl.yml` downloads, parses, publishes | Release tagged `data-YYYY-MM-DD` |
| Browser deploy | on successful ingest | `shinylive-deploy.yml` rebuilds Pages | github.io URL refreshed |
| Retention | same job | delete releases older than 14 days | `gh release delete` |
| Schema watch | same job | `schema_diff` vs. committed snapshot | issue filed with label `schema-drift` |
| CI on code | PR / push | `etl-ci.yml` runs ruff + pytest | green check on PR |

## Where a human (me) still steps in

### 1. Schema drift
When BNetzA adds or removes an XML field, `schema_diff.py` writes a report
and the workflow files a GitHub Issue. Fix is usually:

```python
# in WORK/etl/src/mastr_etl/config.py
Entity(key="solar", ..., numeric_cols=COMMON_UNIT_NUMERIC + ("NeueSpalte",))
```

Then run `make schema-check` locally (or let the next nightly pass) and
commit the updated `WORK/etl/schema_snapshot.json`.

### 2. New dashboard requests
Copy an existing `apps/0N_x/` folder, adjust SQL, submit a PR. All plumbing
(theme, attribution, data connection) is inherited from `WORK/shiny/R/`.

### 3. Hard failures
If a nightly fails twice in a row, the workflow's default `Actions → Re-run`
is usually enough. Deeper failures surface as failing CI emails. The
`concurrency: mastr-nightly` block prevents duplicate runs from piling up.

## State machine

```
             ┌──────────┐
             │ HEALTHY  │◄────────────┐
             └────┬─────┘             │
                  │ nightly run       │ green build
                  ▼                   │
      ┌────────────────────┐          │
      │ running            │──────────┘
      └───┬──────────┬─────┘
          │ ok       │ schema drift
          ▼          ▼
       HEALTHY    SCHEMA_ISSUE
                     │ human edits config.py + snapshot
                     ▼
                 HEALTHY

      ┌─────────────────┐
      │  PARSE_FAILED   │ ← if lxml or ZIP cannot be opened
      └───────┬─────────┘
              │ re-run action (often transient network)
              ▼
           HEALTHY
```

## Cost model

- GitHub Actions free tier: unlimited minutes for **public** repos. The
  nightly run takes ~30 min, so ~15 hours/month; at private-repo rates that
  would be $1.20/month — but there's no reason to keep the repo private
  since the data is public anyway.
- GitHub Releases storage: no per-repo cap documented; each nightly is ~3 GB
  of assets, and with 14-day retention we stabilise at ~40 GB.
- GitHub Pages: 1 GB soft cap, 100 GB/month bandwidth. The shinylive build
  is ~20 MB, so comfortable.

## Why "only 95%"

There's no known way to predict schema drift automatically. BNetzA doesn't
publish an XSD diff feed. A heuristic parser could try to guess the type of
a new column, but we've chosen to flag and wait for a human rather than
silently drop or mis-cast data.
