# WORK/docs — documentation index

## IONOS VPS server (start here)

| File | Purpose | Git / GitHub |
|------|---------|--------------|
| **[SERVER.md](SERVER.md)** | Complete server runbook — URLs, ports, deploy, Grafana, troubleshooting | ✅ Safe to push |
| **[SERVER.credentials.local.md](SERVER.credentials.local.md)** | Passwords and login table | ❌ **Local only** (gitignored) |

**On your Mac:** keep both files in this folder — that is your single local reference (runbook + passwords).

**On GitHub:** only `SERVER.md` is published; credentials never leave your machine.

**Public web copy** (no passwords): http://82.165.167.86/portal/docs/ — dashboard guides for visitors.

---

## Agent / project handoffs

| File | Purpose |
|------|---------|
| [AGENT_HANDOFF_IONOS_VPS.md](AGENT_HANDOFF_IONOS_VPS.md) | Agent continuation prompt, erwicon unlock, file index |
| [AGENT_HANDOFF.md](AGENT_HANDOFF.md) | MaStR ETL, data releases, most_visited / Candida |

---

## Legacy redirects

| Old file | Use instead |
|----------|-------------|
| [IONOS_VPS_HUB.md](IONOS_VPS_HUB.md) | [SERVER.md](SERVER.md) |

---

## Other docs

| File | Topic |
|------|--------|
| [RUN.md](RUN.md) | Local RStudio without VPS |
| [ARCHITECTURE.md](ARCHITECTURE.md) | App architecture |
| [DATA_SCHEMA.md](DATA_SCHEMA.md) | MaStR data schema |
| [Posit_RStudio_Licensing_Use_Case_Assessment.md](Posit_RStudio_Licensing_Use_Case_Assessment.md) | Licensing memo |
| [References_PhD_Scholar_Verification_Process.md](References_PhD_Scholar_Verification_Process.md) | Reference-check methodology (private bibliography — not on public portal) |
