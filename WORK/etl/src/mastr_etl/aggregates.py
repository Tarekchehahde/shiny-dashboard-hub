"""
Write small pre-aggregated Parquet files for the in-browser (shinylive) build.

The full DuckDB is ~600 MB, which is too heavy to ship through a browser's
WebAssembly environment. Each file emitted here is typically <1 MB and answers
one dashboard question directly.

End users who run the apps in RStudio don't strictly need these — the full
DuckDB serves everything — but the shinylive build relies on them.
"""

from __future__ import annotations

import logging
from pathlib import Path

import click
import duckdb

log = logging.getLogger("mastr.aggregates")


def _table_columns(con: duckdb.DuckDBPyConnection, table: str) -> set[str]:
    """Lower-cased column set for a given table; empty if the table is missing."""
    try:
        rows = con.execute(
            "SELECT column_name FROM information_schema.columns WHERE table_name = ?",
            [table],
        ).fetchall()
    except duckdb.Error:
        return set()
    return {r[0].lower() for r in rows}


def _col_or_null(cols: set[str], name: str, cast: str | None = None) -> str:
    expr = name if name.lower() in cols else "NULL"
    return f"TRY_CAST({expr} AS {cast})" if cast else expr


def _wind_hub_height_sql(con: duckdb.DuckDBPyConnection) -> str | None:
    """Build the wind-spec query only over columns that actually exist; if
    the wind table is missing entirely, return None so the aggregate is
    skipped instead of raising."""
    cols = _table_columns(con, "wind")
    if not cols:
        return None
    return f"""
        SELECT
            {_col_or_null(cols, 'Nabenhoehe',       cast='DOUBLE')} AS nabenhoehe_m,
            {_col_or_null(cols, 'Rotordurchmesser', cast='DOUBLE')} AS rotor_m,
            {_col_or_null(cols, 'Bruttoleistung',   cast='DOUBLE')} / 1000 AS mw,
            {_col_or_null(cols, 'Bundesland')}                        AS bundesland_code
        FROM wind
        WHERE {_col_or_null(cols, 'Nabenhoehe')} IS NOT NULL
    """


QUERIES: dict[str, str] = {
    # KPI tiles on overview
    "kpi_overview.parquet": """
        SELECT
            COUNT(*)                          AS units_total,
            SUM(bruttoleistung_kw) / 1e6      AS capacity_gw,
            COUNT(*) FILTER (WHERE energietraeger IN
                ('SolareStrahlungsenergie','Wind','Biomasse','Wasser','GeothermieGrubenKlaerschlamm')
            )                                 AS ee_units,
            SUM(bruttoleistung_kw) FILTER (WHERE energietraeger IN
                ('SolareStrahlungsenergie','Wind','Biomasse','Wasser','GeothermieGrubenKlaerschlamm')
            ) / 1e6                           AS ee_capacity_gw,
            CURRENT_DATE                      AS as_of
        FROM v_units_all
    """,
    # State league table
    "capacity_by_state.parquet": "SELECT * FROM v_capacity_by_state",
    # Monthly build-out
    "buildout_monthly.parquet": "SELECT * FROM v_buildout_monthly",
    # PLZ-level capacity for maps (only top PLZs to keep file small)
    "capacity_by_plz_top5000.parquet": """
        SELECT *
        FROM v_capacity_by_plz
        WHERE bruttoleistung_mw IS NOT NULL
        ORDER BY bruttoleistung_mw DESC
        LIMIT 5000
    """,
    # Solar size-class distribution
    "solar_size_classes.parquet": """
        SELECT
            bundesland_name,
            CASE
              WHEN bruttoleistung_kw < 10    THEN '0–10 kW'
              WHEN bruttoleistung_kw < 30    THEN '10–30 kW'
              WHEN bruttoleistung_kw < 100   THEN '30–100 kW'
              WHEN bruttoleistung_kw < 750   THEN '100–750 kW'
              WHEN bruttoleistung_kw < 10000 THEN '0.75–10 MW'
              ELSE '>10 MW'
            END AS size_class,
            COUNT(*)                          AS units,
            SUM(bruttoleistung_kw)/1000       AS capacity_mw
        FROM v_units_all
        WHERE energietraeger = 'SolareStrahlungsenergie'
        GROUP BY 1, 2
    """,
    # Wind turbine physical spec distribution — built dynamically below so
    # missing columns degrade to NULL instead of raising. Sentinel value;
    # replaced in main() once we have a connection.
    "wind_hub_height.parquet": "__DYNAMIC__",
    # EEG quota by year
    "ee_quote_by_year.parquet": """
        SELECT
            EXTRACT(YEAR FROM inbetriebnahme_datum) AS year,
            SUM(bruttoleistung_kw) / 1e6 AS total_gw,
            SUM(bruttoleistung_kw) FILTER (WHERE energietraeger IN
                ('SolareStrahlungsenergie','Wind','Biomasse','Wasser','GeothermieGrubenKlaerschlamm')
            ) / 1e6 AS ee_gw
        FROM v_units_all
        WHERE inbetriebnahme_datum IS NOT NULL
          AND EXTRACT(YEAR FROM inbetriebnahme_datum) BETWEEN 1990 AND 2100
        GROUP BY 1
        ORDER BY 1
    """,
}


@click.command()
@click.option("--duckdb", "duckdb_path", type=click.Path(exists=True, path_type=Path),
              required=True)
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True)
def main(duckdb_path: Path, out_dir: Path) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    out_dir.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(str(duckdb_path), read_only=True)
    written = 0
    skipped = 0
    for name, sql in QUERIES.items():
        target = out_dir / name
        if sql == "__DYNAMIC__" and name == "wind_hub_height.parquet":
            sql = _wind_hub_height_sql(con)
            if sql is None:
                log.warning("aggregate %s skipped — wind table not present", name)
                skipped += 1
                continue
        try:
            con.execute(f"COPY ({sql}) TO '{target}' (FORMAT PARQUET, COMPRESSION ZSTD)")
            size = target.stat().st_size
            log.info("wrote %-40s %8.1f KB", name, size / 1024)
            written += 1
        except duckdb.Error as exc:
            # Fail-soft: log and continue. Each aggregate is independent and
            # its absence only affects one Shiny tile, not the whole pipeline.
            log.error("aggregate %s failed: %s", name, exc)
            skipped += 1
    con.close()
    log.info("aggregates: %d written, %d skipped", written, skipped)


if __name__ == "__main__":
    main()
