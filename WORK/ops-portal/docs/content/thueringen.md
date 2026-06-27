# Thüringen demos (erwicon connect 2026)

Seven interactive dashboards built for **erwicon connect 2026** in Erfurt. They combine MaStR energy data with regional Kreis-level views and, where noted, external APIs.

**Shared code:** `WORK/shiny/R/thueringen_helpers.R` — Kreis names, geo joins, SQL helpers for Thüringen-filtered MaStR queries.

---

## Demo 1 — Gewerbe-Strom (`/thueringen_gewerbe_strom/`)

- Day-ahead electricity price (DE-LU bidding zone) — live or recent from Energy-Charts
- Commercial & industrial PV plus storage assets in Thüringen by Kreis
- Interactive price time-series chart

---

## Demo 2 — Wärmepumpen & Gebäude-Energie (`/thueringen_waermepumpe_gebaeude/`)

- Storage, home-scale PV, and biomass units aggregated by Kreis
- Building-energy transition narrative for the Freistaat

---

## Demo 3 — Regionalwirtschaft (`/thueringen_fachkraefte/`)

- Employment and demand indicators by Kreis (BA Statistik)
- **Currently hidden** from the public hub and blocked on nginx until the event — re-enable via `HUB_HIDDEN_IDS` in `hub/app.R` and restart services

---

## Demo 4 — Logistik & Standort (`/thueringen_logistik/`)

- A4 / A9 / A38 corridor context
- Commuter flows and commercial PV near logistics hubs
- Erfurt as logistics hub narrative

---

## Demo 5 — Tourismus & Konsum (`/thueringen_tourismus/`)

- Overnight stays and seasonal strength by Kreis
- Wartburg, Weimar, Thüringer Wald regional highlights

---

## Demo 6 — Kommunal & Infrastruktur (`/thueringen_kommunal/`)

- Large-scale solar, battery storage, and onshore wind by Kreis
- Target audience: municipal utilities, districts, planners
- Leaflet Kreis map + reactable summary

**Data notes:** Wind query uses `WindAnLandOderAufSee` filter when `Lage` column is absent in parquet.

---

## Demo 7 — Mittelstand-Digital (`/thueringen_mittelstand_digital/`)

- Cockpit-style catalog linking all erwicon demos
- Illustrative weekly KPIs — “live data instead of Excel PDF” pitch

---

## Demo 0 — Solar-Wirtschaft (`/thueringen_solar_wirtschaft/`)

Entry-level Thüringen PV overview (not numbered 1–7 but part of the same event set):

- Kreis ranking of installed PV capacity
- Erfurt spotlight
- Monthly build-out trend

---

## Design choices

- Hub badges show **Thüringen** (neutral `bg-secondary`) — no event-specific marketing pills on the public hub
- All demos use the same responsive CSS and MaStR data layer as the flagship apps
- Ports **3845–3853** on the VPS (one systemd service each)
