"""
Build a single DuckDB database from the per-entity Parquet files.

Adds:
  * One physical table per entity (loaded from parquet)
  * Bundesland lookup table
  * Convenience views:
        v_units_all          — UNION of all power-producing units with a
                                normalised (mastr_nr, energietraeger,
                                bruttoleistung_kw, bundesland_name,
                                inbetriebnahme_datum, lat, lon)
        v_capacity_by_state  — total kW by Bundesland × Energietraeger
        v_buildout_monthly   — capacity additions per month (for trend charts)
"""

from __future__ import annotations

import logging
from pathlib import Path

import click
import duckdb

from .config import BUNDESLAND, ENTITIES

log = logging.getLogger("mastr.duckdb")

# Energy-producing unit entities (subset of ENTITIES) — only these contribute
# to the v_units_all view. Storage is included but flagged.
UNIT_ENTITIES = {
    "solar": "SolareStrahlungsenergie",
    "wind": "Wind",
    "biomasse": "Biomasse",
    "wasser": "Wasser",
    "geothermie": "GeothermieGrubenKlaerschlamm",
    "kernkraft": "Kernenergie",
    "verbrennung": "FossilOderSonstige",
    "stromspeicher": "Speicher",
}


def _create_table(con: duckdb.DuckDBPyConnection, parquet: Path, name: str) -> int:
    """Materialise a parquet file as a DuckDB table.

    Fault-tolerant: a missing or corrupt parquet logs a warning and returns 0
    instead of raising, so one bad entity can't abort the whole DuckDB build
    (which would discard ~10–15 min of work for the surviving entities).
    """
    if not parquet.exists():
        log.warning("missing parquet for %s (%s) — skipping", name, parquet)
        return 0
    try:
        con.execute(
            f"CREATE OR REPLACE TABLE {name} AS SELECT * FROM read_parquet(?)",
            [str(parquet)],
        )
        rows = con.execute(f"SELECT COUNT(*) FROM {name}").fetchone()[0]
        log.info("table %-20s %12s rows", name, f"{rows:,}")
        return rows
    except duckdb.Error as exc:
        log.error("table %s failed to load from %s: %s — continuing without it",
                  name, parquet, exc)
        # Make sure no half-built table remains, so downstream queries see
        # an absent table (information_schema returns 0 columns) rather than
        # a partially-populated one.
        try:
            con.execute(f"DROP TABLE IF EXISTS {name}")
        except duckdb.Error:
            pass
        return 0


def _create_bundesland_lookup(con: duckdb.DuckDBPyConnection) -> None:
    rows = [(code, name) for code, name in BUNDESLAND.items()]
    con.execute("CREATE OR REPLACE TABLE bundesland (code VARCHAR, name VARCHAR)")
    con.executemany("INSERT INTO bundesland VALUES (?, ?)", rows)


UNITS_VIEW_TEMPLATE = """
CREATE OR REPLACE VIEW v_units_all AS
{unions}
"""


def _table_columns(con: duckdb.DuckDBPyConnection, table: str) -> set[str]:
    """Return the set of column names on a given table (case-insensitive)."""
    rows = con.execute(
        "SELECT column_name FROM information_schema.columns WHERE table_name = ?",
        [table],
    ).fetchall()
    return {r[0].lower() for r in rows}


def _col_or_null(
    cols: set[str], name: str, cast: str | None = None, table_alias: str = "t",
) -> str:
    """Build a SELECT expression that is `t.<name>` if the column exists,
    else the string ``NULL``. Optionally wrapped in TRY_CAST(expr AS <cast>).

    Having a schema-aware projection is essential because BNetzA ships
    stripped-down schemas for some entity types (e.g. kernkraft has ~45
    columns vs solar's ~70) and a single missing column in one branch of
    the UNION ALL otherwise fails the whole view binder.
    """
    expr = f"{table_alias}.{name}" if name.lower() in cols else "NULL"
    return f"TRY_CAST({expr} AS {cast})" if cast else expr


def _build_units_view(con: duckdb.DuckDBPyConnection) -> None:
    """UNION every Einheiten* table into a single normalised stream.

    Each SELECT is built dynamically from the actual columns present in
    that table; any column that BNetzA's XML schema doesn't ship for that
    entity is replaced with ``NULL``. This keeps the view resilient to
    schema drift and heterogeneity across entity types.
    """
    selects: list[str] = []
    for key, eg in UNIT_ENTITIES.items():
        cols = _table_columns(con, key)
        if not cols:
            log.warning("table %s missing — skipping in v_units_all", key)
            continue
        mastr_nr = _col_or_null(cols, "EinheitMastrNummer")
        brutto = _col_or_null(cols, "Bruttoleistung", cast="DOUBLE")
        netto = _col_or_null(cols, "Nettonennleistung", cast="DOUBLE")
        bundesland = _col_or_null(cols, "Bundesland")
        gemeinde = _col_or_null(cols, "Gemeinde")
        plz = _col_or_null(cols, "Postleitzahl")
        lon = _col_or_null(cols, "Laengengrad", cast="DOUBLE")
        lat = _col_or_null(cols, "Breitengrad", cast="DOUBLE")
        ibn = _col_or_null(cols, "Inbetriebnahmedatum", cast="DATE")
        status = _col_or_null(cols, "Betriebsstatus")
        selects.append(f"""
            SELECT
                '{key}'           AS source_table,
                '{eg}'            AS energietraeger,
                {mastr_nr}        AS mastr_nr,
                {brutto}          AS bruttoleistung_kw,
                {netto}           AS nettonennleistung_kw,
                {bundesland}      AS bundesland_code,
                bl.name           AS bundesland_name,
                {gemeinde}        AS gemeinde,
                {plz}             AS plz,
                {lon}             AS lon,
                {lat}             AS lat,
                {ibn}             AS inbetriebnahme_datum,
                {status}          AS betriebsstatus
            FROM {key} t
            LEFT JOIN bundesland bl ON bl.code = {bundesland}
        """)
    if not selects:
        log.warning("no unit tables found — v_units_all not created")
        return
    con.execute(UNITS_VIEW_TEMPLATE.format(unions="\nUNION ALL\n".join(selects)))
    n = con.execute("SELECT COUNT(*) FROM v_units_all").fetchone()[0]
    log.info("view  v_units_all          %12s rows", f"{n:,}")


def _build_aggregate_views(con: duckdb.DuckDBPyConnection) -> None:
    con.execute("""
        CREATE OR REPLACE VIEW v_capacity_by_state AS
        SELECT
            bundesland_name,
            energietraeger,
            COUNT(*)                       AS units,
            SUM(bruttoleistung_kw) / 1000  AS bruttoleistung_mw
        FROM v_units_all
        WHERE bundesland_name IS NOT NULL
        GROUP BY 1, 2
    """)
    con.execute("""
        CREATE OR REPLACE VIEW v_buildout_monthly AS
        SELECT
            DATE_TRUNC('month', inbetriebnahme_datum) AS month,
            energietraeger,
            COUNT(*)                                  AS new_units,
            SUM(bruttoleistung_kw) / 1000             AS new_capacity_mw
        FROM v_units_all
        WHERE inbetriebnahme_datum IS NOT NULL
        GROUP BY 1, 2
        ORDER BY 1
    """)
    con.execute("""
        CREATE OR REPLACE VIEW v_capacity_by_plz AS
        SELECT
            plz,
            energietraeger,
            COUNT(*)                       AS units,
            SUM(bruttoleistung_kw) / 1000  AS bruttoleistung_mw,
            AVG(lat)                       AS lat,
            AVG(lon)                       AS lon
        FROM v_units_all
        WHERE plz IS NOT NULL AND lat IS NOT NULL
        GROUP BY 1, 2
    """)
    log.info("created aggregate views")


@click.command()
@click.option("--parquet", "parquet_dir", type=click.Path(exists=True, path_type=Path),
              required=True, help="Directory of *.parquet files written by parse.py")
@click.option("--out", "out_path", type=click.Path(path_type=Path), required=True,
              help="Output DuckDB file path")
def main(parquet_dir: Path, out_path: Path) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()
    # Spill to disk if we run out of RAM (ubuntu-latest has ~7 GB free, the
    # combined parquet set is ~600 MB compressed but ~3-4 GB hot in DuckDB).
    tmp_dir = out_path.parent / ".duckdb_tmp"
    tmp_dir.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(out_path))
    try:
        con.execute("PRAGMA threads=4")
        con.execute("PRAGMA memory_limit='4GB'")
        con.execute(f"PRAGMA temp_directory='{tmp_dir}'")
        con.execute("PRAGMA enable_progress_bar=true")
        loaded = 0
        for entity in ENTITIES:
            if _create_table(con, parquet_dir / f"{entity.key}.parquet",
                             entity.key) > 0:
                loaded += 1
        log.info("loaded %d / %d entities", loaded, len(ENTITIES))
        _create_bundesland_lookup(con)
        _build_units_view(con)
        _build_aggregate_views(con)
        con.execute("CHECKPOINT")
    finally:
        con.close()
    log.info("DuckDB written: %s (%.1f MB)", out_path,
             out_path.stat().st_size / 1024**2)


if __name__ == "__main__":
    main()
