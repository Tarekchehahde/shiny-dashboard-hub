"""
Catalog of MaStR entities and their XML record element names.

The MaStR Gesamtdatenauszug ZIP contains ~80 XML files. Each file holds one
entity type; some very large entities (Solar, Wind) are split into numbered
parts (e.g. EinheitenSolar_1.xml, EinheitenSolar_2.xml, ...).

We treat the ZIP as a flat pool: every XML whose root-matches one of the
record element names below is routed to the configured entity.

Attribute names are the canonical MaStR field names — we keep them as-is so
the Parquet schema matches the BNetzA docs exactly.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Entity:
    """One MaStR entity type -> one Parquet file."""

    key: str                    # short key used in filenames, e.g. "solar"
    record_tag: str             # XML element name of one record, e.g. "EinheitSolar"
    file_glob: str              # matches XML filenames in the ZIP, e.g. "EinheitenSolar_*.xml"
    description: str
    energietraeger: str | None = None   # for unit entities, the canonical Energietraeger label
    parquet_partition_cols: tuple[str, ...] = ()

    # Columns we try to cast to numeric / date during parse. Everything else
    # stays as string. If a column is missing in a given record we emit NULL.
    numeric_cols: tuple[str, ...] = ()
    date_cols: tuple[str, ...] = ()

    # Keys that identify a row (used for dedup if the ZIP contains overlaps).
    id_cols: tuple[str, ...] = ("EinheitMastrNummer",)


COMMON_UNIT_NUMERIC = (
    "Bruttoleistung",
    "Nettonennleistung",
    "Laengengrad",
    "Breitengrad",
    "Nabenhoehe",
    "Rotordurchmesser",
    "Nutzflaeche",
    "HerstellungsDatum",
    "AnzahlModule",
)

COMMON_UNIT_DATES = (
    "DatumLetzteAktualisierung",
    "EinheitRegistrierungsdatum",
    "GeplantesInbetriebnahmeDatum",
    "Inbetriebnahmedatum",
    "DatumEndgueltigeStilllegung",
    "DatumBeginnVoruebergehendeStilllegung",
    "DatumWiederaufnahmeBetrieb",
)


# ---------------------------------------------------------------------------
# Energy-producing units (Einheiten...)
# ---------------------------------------------------------------------------

ENTITIES: list[Entity] = [
    Entity(
        key="solar",
        record_tag="EinheitSolar",
        file_glob="EinheitenSolar*.xml",
        description="PV units (Solareinheiten)",
        energietraeger="SolareStrahlungsenergie",
        numeric_cols=COMMON_UNIT_NUMERIC + ("Leistungsbegrenzung",),
        date_cols=COMMON_UNIT_DATES,
        parquet_partition_cols=("Bundesland",),
    ),
    Entity(
        key="wind",
        record_tag="EinheitWind",
        file_glob="EinheitenWind*.xml",
        description="Wind units onshore + offshore",
        energietraeger="Wind",
        numeric_cols=COMMON_UNIT_NUMERIC + ("Seelage",),
        date_cols=COMMON_UNIT_DATES,
        parquet_partition_cols=("Bundesland",),
    ),
    Entity(
        key="biomasse",
        record_tag="EinheitBiomasse",
        file_glob="EinheitenBiomasse*.xml",
        description="Biomass / biogas units",
        energietraeger="Biomasse",
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="wasser",
        record_tag="EinheitWasser",
        file_glob="EinheitenWasser*.xml",
        description="Hydro units (run-of-river, storage, pumped)",
        energietraeger="Wasser",
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="geothermie",
        record_tag="EinheitGeoSolarthermieGrubenKlaerschlammDruckentspannung",
        file_glob="EinheitenGeoSolarthermie*.xml",
        description="Geothermal, solar thermal, mine/waste-gas, decompression",
        energietraeger="GeoSolarthermieGrubenKlaerschlammDruckentspannung",
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="kernkraft",
        record_tag="EinheitKernkraft",
        file_glob="EinheitenKernkraft*.xml",
        description="Nuclear units (historical)",
        energietraeger="Kernenergie",
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="verbrennung",
        record_tag="EinheitVerbrennung",
        file_glob="EinheitenVerbrennung*.xml",
        description="Conventional combustion (gas, coal, oil)",
        energietraeger=None,  # multiple (Erdgas, Steinkohle, ...)
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="stromspeicher",
        record_tag="EinheitStromSpeicher",
        file_glob="EinheitenStromSpeicher*.xml",
        description="Electricity storage (battery + pumped)",
        energietraeger="Speicher",
        numeric_cols=COMMON_UNIT_NUMERIC + ("NutzbareSpeicherkapazitaet",),
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="gaserzeuger",
        record_tag="EinheitGasErzeuger",
        file_glob="EinheitenGasErzeuger*.xml",
        description="Gas producers (biogas, synthetic gas)",
        energietraeger=None,
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="gasverbraucher",
        record_tag="EinheitGasVerbraucher",
        file_glob="EinheitenGasVerbraucher*.xml",
        description="Gas consumers",
        energietraeger=None,
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="gasspeicher",
        record_tag="EinheitGasSpeicher",
        file_glob="EinheitenGasSpeicher*.xml",
        description="Gas storage",
        energietraeger=None,
        numeric_cols=COMMON_UNIT_NUMERIC,
        date_cols=COMMON_UNIT_DATES,
    ),
    Entity(
        key="kwk",
        record_tag="AnlageKwk",
        file_glob="AnlagenKwk*.xml",
        description="Combined heat & power (KWK) plants",
        energietraeger=None,
        numeric_cols=("ThermischeNutzleistung", "ElektrischeKwkLeistung"),
        date_cols=COMMON_UNIT_DATES,
        id_cols=("KwkMastrNummer",),
    ),
    Entity(
        key="eeg_solar",
        record_tag="AnlageEegSolar",
        file_glob="AnlagenEegSolar*.xml",
        description="EEG-Anlagen Solar (funding metadata)",
        numeric_cols=("InstallierteLeistung", "AnlagenschluesselEeg"),
        date_cols=("RegistrierungsDatum",),
        id_cols=("EegMastrNummer",),
    ),
    Entity(
        key="eeg_wind",
        record_tag="AnlageEegWind",
        file_glob="AnlagenEegWind*.xml",
        description="EEG-Anlagen Wind",
        numeric_cols=("InstallierteLeistung",),
        date_cols=("RegistrierungsDatum",),
        id_cols=("EegMastrNummer",),
    ),
    Entity(
        key="eeg_biomasse",
        record_tag="AnlageEegBiomasse",
        file_glob="AnlagenEegBiomasse*.xml",
        description="EEG-Anlagen Biomasse",
        numeric_cols=("InstallierteLeistung",),
        date_cols=("RegistrierungsDatum",),
        id_cols=("EegMastrNummer",),
    ),
    Entity(
        key="eeg_wasser",
        record_tag="AnlageEegWasser",
        file_glob="AnlagenEegWasser*.xml",
        description="EEG-Anlagen Wasser",
        numeric_cols=("InstallierteLeistung",),
        date_cols=("RegistrierungsDatum",),
        id_cols=("EegMastrNummer",),
    ),
    Entity(
        key="marktakteure",
        record_tag="Marktakteur",
        file_glob="Marktakteure*.xml",
        description="Market actors (Betreiber, Händler, Netzbetreiber...)",
        numeric_cols=(),
        date_cols=("DatumLetzeAktualisierung", "DatumRegistrierung"),
        id_cols=("MastrNummer",),
    ),
    Entity(
        key="netzanschlusspunkte",
        record_tag="Netzanschlusspunkt",
        file_glob="Netzanschlusspunkte*.xml",
        description="Grid connection points",
        numeric_cols=("Spannungsebene",),
        id_cols=("NetzanschlusspunktMastrNummer",),
    ),
    Entity(
        key="bilanzierungsgebiete",
        record_tag="Bilanzierungsgebiet",
        file_glob="Bilanzierungsgebiete*.xml",
        description="Balancing zones (Strom)",
        id_cols=("Code",),
    ),
    Entity(
        key="lokationen",
        record_tag="Lokation",
        file_glob="Lokationen*.xml",
        description="Locations (geographic / grid topology)",
        id_cols=("MastrNummer",),
    ),
]


ENTITIES_BY_KEY: dict[str, Entity] = {e.key: e for e in ENTITIES}
ENTITIES_BY_TAG: dict[str, Entity] = {e.record_tag: e for e in ENTITIES}


# ---------------------------------------------------------------------------
# Download source
# ---------------------------------------------------------------------------

MASTR_DOWNLOAD_PAGE = "https://www.marktstammdatenregister.de/MaStR/Datendownload"

# BNetzA publishes the link as a relative path on the Datendownload page.
# This URL has been stable since 2021; if it moves, download.py falls back to
# scraping the page. Override via the MASTR_DOWNLOAD_URL env var.
DEFAULT_ZIP_URL = (
    "https://download.marktstammdatenregister.de/Gesamtdatenexport_latest.zip"
)


# ---------------------------------------------------------------------------
# Bundesland lookup (for maps + aggregates)
# ---------------------------------------------------------------------------

# Verified empirically by correlating each code with its dominant PLZ prefix
# across the full MaStR solar table (2026-04-21 data release). Do NOT reorder
# without re-running that check — the BNetzA Katalog ordering is NOT alphabetic.
BUNDESLAND = {
    "1400": "Brandenburg",
    "1401": "Berlin",
    "1402": "Baden-Württemberg",
    "1403": "Bayern",
    "1404": "Bremen",
    "1405": "Hessen",
    "1406": "Hamburg",
    "1407": "Mecklenburg-Vorpommern",
    "1408": "Niedersachsen",
    "1409": "Nordrhein-Westfalen",
    "1410": "Rheinland-Pfalz",
    "1411": "Schleswig-Holstein",
    "1412": "Saarland",
    "1413": "Sachsen",
    "1414": "Sachsen-Anhalt",
    "1415": "Thüringen",
    "1416": "Ausschließliche Wirtschaftszone",
}
