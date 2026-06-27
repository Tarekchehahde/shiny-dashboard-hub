# All dashboards

Each app runs as its own Shiny process behind nginx at `/{id}/`. Open any dashboard from the [hub](http://82.165.167.86/) or the links below.

---

## Flagship & live data

### Most Visited (`/most_visited/`)

**Purpose:** In-house R Shiny replica of the monthly Tableau panel Candida's team publishes — monthly new solar capacity (MW) by segment with YTD comparison table.

**Data:** BNetzA MaStR solar units via DuckDB on parquet (same source as Tableau, typically one night newer).

**Segments:** Home (&lt;10 kW), C&amp;I (&lt;1 MW), Large Scale, Grand Total — bucketed on Bruttoleistung at query time.

**Charts:** Four stacked small-multiple line charts (one per segment) + reactable YTD table mirroring the Candida layout.

---

### Deutschland Solar Radiation (`/deutschland_solar_radiation/`)

**Purpose:** Live map of global horizontal irradiance (GHI) across Germany.

**Data:** Open-Meteo API (DWD satellite models) — no API key.

**UI:** Leaflet map + hourly chart, auto-refresh.

---

### EU Electricity — Live Prices (`/eu_electricity_live/`)

**Purpose:** Day-ahead power prices across European bidding zones.

**Data:** Fraunhofer ISE Energy-Charts API (free, no key). Zones include DE-LU, FR, NL, BE, AT, PL, CZ, CH, DK1, IT-North, ES.

**UI:** Leaflet map (color by price), comparison chart, zone table. Refreshes every 15 minutes.

---

## Classic demos

### Health and Wealth of Nations (`/health_wealth_nations/`)

**Purpose:** Hans Rosling–style animated bubble chart — life expectancy vs GDP per capita over time.

**Data:** Gapminder-style dataset bundled in the app.

---

### Lebanese Elections (`/lebanese_elections/`)

**Purpose:** 2022 parliamentary election casas — voter density, candidates, interactive treemap.

**Author:** Tarek Chehade. Tableau-to-Shiny style replica.

---

### MyManager Demo (`/my_manager_demo/`)

**Purpose:** Executive pitch deck in Shiny form — hub navigation, live interactivity, delivery pipeline overview, live catalog of what's deployed.

**Audience:** Manager / stakeholder presentations.

---

### Demo Dashboard (`/dummy_demo/`)

**Purpose:** Smoke-test slot — dummy KPIs and charts to verify hub routing and deployment.

---

## Thüringen / erwicon connect 2026

Seven themed demos for **erwicon connect** (Erfurt, June 2026). See the dedicated [Thüringen demos](?doc=thueringen) page for detail.

| Demo | URL | Topic |
|------|-----|-------|
| Solar-Wirtschaft | `/thueringen_solar_wirtschaft/` | PV Kreis-Ranking, Erfurt spotlight |
| Gewerbe-Strom | `/thueringen_gewerbe_strom/` | Day-ahead price + Gewerbe-PV |
| Wärmepumpen & Gebäude | `/thueringen_waermepumpe_gebaeude/` | Storage, home-PV, biomass by Kreis |
| Regionalwirtschaft | `/thueringen_fachkraefte/` | *Hidden from hub* — unlock for event |
| Logistik & Standort | `/thueringen_logistik/` | A4/A9/A38, Pendler, Gewerbe-PV |
| Tourismus & Konsum | `/thueringen_tourismus/` | Overnight stays by Kreis |
| Kommunal & Infrastruktur | `/thueringen_kommunal/` | Großsolar, storage, wind by Kreis |
| Mittelstand-Digital | `/thueringen_mittelstand_digital/` | Cockpit catalog + illustrative KPIs |

---

## Internal / admin (not on public hub)

### Site traffic (`/site_traffic/`)

**Purpose:** nginx access-log analytics — page views, visitor IPs, dashboard popularity.

**Auth:** Password (not listed on hub). See **Monitoring & ops**.

---

## Shared UI features

All public dashboards share helpers from `WORK/shiny/R/ui_helpers.R`:

- Responsive layout (mobile / tablet breakpoints)
- Consistent bslib theme (`mastr_theme()`)
- Optional LinkedIn QR dock (auto-hides after 5s, edge tab to reopen)

Hub cards and nginx routes are defined in `WORK/shiny/hub/app.R`.
