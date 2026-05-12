# Data schema

This is the user-facing schema after parse. Columns marked ⚡ are synthesised
by us; everything else is passed through from MaStR XML verbatim (names and
all).

## Unit tables: `solar`, `wind`, `biomasse`, `wasser`, `geothermie`, `kernkraft`, `verbrennung`, `stromspeicher`

Common columns (present in all power-producing unit tables):

| column                    | type     | notes |
|---------------------------|----------|-------|
| `EinheitMastrNummer`      | string   | **primary key** |
| `Bruttoleistung`          | double   | kW |
| `Nettonennleistung`       | double   | kW |
| `Inbetriebnahmedatum`     | date     | |
| `EinheitRegistrierungsdatum` | date  | |
| `Betriebsstatus`          | string   | `InBetrieb`, `EndgueltigStillgelegt`, … |
| `Bundesland`              | string   | BNetzA code; join with `bundesland(code)` for name |
| `Gemeinde`                | string   | |
| `Postleitzahl`            | string   | |
| `Laengengrad`             | double   | longitude |
| `Breitengrad`             | double   | latitude |

Technology-specific columns (non-exhaustive):

| table | extra columns |
|---|---|
| `solar`        | `Hauptausrichtung`, `Leistungsbegrenzung`, `Nutzflaeche`, `AnzahlModule`, `ArtDerSolaranlage` |
| `wind`         | `Nabenhoehe`, `Rotordurchmesser`, `Hersteller`, `Typenbezeichnung`, `Lage` (Land / WindAufSee), `Seelage`, `Wassertiefe`, `KuestenEntfernung`, `NameWindpark` |
| `biomasse`     | `Hauptbrennstoff`, `Biomasseart` |
| `wasser`       | `ArtDerWasserkraftanlage`, `MindestWasserdurchfluss` |
| `stromspeicher`| `NutzbareSpeicherkapazitaet` (kWh), `Technologie`, `PumpbetriebEingangsleistung` |
| `verbrennung`  | `Hauptbrennstoff` (Erdgas / Steinkohle / Oel / …), `Wirkungsgrad` |

## EEG metadata tables: `eeg_solar`, `eeg_wind`, `eeg_biomasse`, `eeg_wasser`

| column | notes |
|---|---|
| `EegMastrNummer` | primary key |
| `InstallierteLeistung` | kW |
| `RegistrierungsDatum` | date |
| `VerknuepfteEinheit` | FK to `Einheiten*.EinheitMastrNummer` |
| `Zuschlagsnummer`, `AnlagenschluesselEeg`, `NetzbetreiberpruefungStatus` | funding metadata |

## `marktakteure`

| column | notes |
|---|---|
| `MastrNummer` | pk |
| `MarktakteurHauptTyp` | `Anlagenbetreiber`, `Netzbetreiber`, `Haendler`, `Organisation`, … |
| `Firmenname`, `Rechtsform`, `Land`, `Bundesland` | |
| `DatumRegistrierung` | date |

## `kwk`

| column | notes |
|---|---|
| `KwkMastrNummer` | pk |
| `ThermischeNutzleistung`, `ElektrischeKwkLeistung` | kW |
| `Zuschlagnummer` | funding id |

## `netzanschlusspunkte`

| column | notes |
|---|---|
| `NetzanschlusspunktMastrNummer` | pk |
| `Netzbetreiber` | FK to `marktakteure.MastrNummer` |
| `Spannungsebene` | `Niederspannung` / `Mittelspannung` / `Hochspannung` / `Hoechstspannung` |
| `Bundesland`, `Gemeinde`, `Postleitzahl` | |

## Views (present in `mastr.duckdb` and the remote httpfs view layer)

### `v_units_all` ⚡ — unified power-producing units

| column | description |
|---|---|
| `source_table` | which table the row came from (`solar`, `wind`, …) |
| `energietraeger` | canonical label (`SolareStrahlungsenergie`, `Wind`, …) |
| `mastr_nr` | `EinheitMastrNummer` |
| `bruttoleistung_kw` | double |
| `nettonennleistung_kw` | double |
| `bundesland_code`, `bundesland_name` | joined with `bundesland` lookup |
| `gemeinde`, `plz`, `lat`, `lon` | |
| `inbetriebnahme_datum` | date |
| `betriebsstatus` | string |

### `v_capacity_by_state` ⚡
`SELECT bundesland_name, energietraeger, COUNT(*) AS units, SUM(kw)/1000 AS mw FROM v_units_all`

### `v_buildout_monthly` ⚡
Capacity added per (month, Energieträger).

### `v_capacity_by_plz` ⚡
Capacity grouped per PLZ with averaged lat/lon for map plotting.

## Pre-aggregated parquets (for shinylive, shipped as release assets)

| asset | rows | size | purpose |
|---|---|---|---|
| `kpi_overview.parquet` | 1 | < 1 KB | landing-page KPIs |
| `capacity_by_state.parquet` | ≈ 100 | ~5 KB | state league tables |
| `buildout_monthly.parquet` | ~1 500 | ~80 KB | trend charts |
| `capacity_by_plz_top5000.parquet` | 5 000 | ~500 KB | geo map |
| `solar_size_classes.parquet` | ~100 | ~5 KB | solar size histogram |
| `wind_hub_height.parquet` | ~30 000 | ~500 KB | wind scatter |
| `ee_quote_by_year.parquet` | ~30 | ~2 KB | EE-share timeseries |

These are cheap to regenerate; everything the dashboards need can be derived
from the full DuckDB in < 30 s.
