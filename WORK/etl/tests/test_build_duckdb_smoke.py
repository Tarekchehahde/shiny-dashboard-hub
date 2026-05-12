"""
Smoke test for the DuckDB builder.

This test deliberately reproduces the production failure mode that bit run #4
of the nightly ETL: heterogeneous schemas across unit entities, where one
table (kernkraft in production, here a synthetic equivalent) lacks several
columns that the others ship. A naive UNION ALL would raise a Binder Error;
the schema-aware projection in _build_units_view should project NULLs.

Running this on every push (via mastr-etl-ci.yml) costs ~2 seconds and would
have caught run #4 in CI instead of after a 30-minute production run.

It also exercises:
  * _build_aggregate_views (which depends on v_units_all)
  * _create_table fault tolerance (a missing parquet must not abort the build)
  * the wind_hub_height aggregate's dynamic-SQL skinny-schema path
"""
from __future__ import annotations

from pathlib import Path

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from mastr_etl.aggregates import _wind_hub_height_sql
from mastr_etl.build_duckdb import (
    _build_aggregate_views,
    _build_units_view,
    _create_bundesland_lookup,
    _create_table,
)


# A "rich" schema, modelled on what BNetzA ships for solar/wind/biomasse.
RICH_COLS = [
    "EinheitMastrNummer", "Bruttoleistung", "Nettonennleistung",
    "Bundesland", "Gemeinde", "Postleitzahl",
    "Laengengrad", "Breitengrad",
    "Inbetriebnahmedatum", "Betriebsstatus",
]
# A "skinny" schema like kernkraft: missing Gemeinde, PLZ, geo, status.
SKINNY_COLS = [
    "EinheitMastrNummer", "Bruttoleistung", "Nettonennleistung",
    "Bundesland", "Inbetriebnahmedatum",
]


def _write_parquet(path: Path, columns: list[str], rows: int = 3) -> None:
    """Write a tiny parquet file with the given column set."""
    data = {}
    for c in columns:
        if c in ("Bruttoleistung", "Nettonennleistung", "Laengengrad", "Breitengrad"):
            data[c] = [str(1.0 + i) for i in range(rows)]
        elif c == "EinheitMastrNummer":
            data[c] = [f"MAST{i:010d}" for i in range(rows)]
        elif c == "Bundesland":
            data[c] = ["1402", "1403", "1404"][:rows]
        elif c == "Inbetriebnahmedatum":
            data[c] = ["2024-01-01"] * rows
        elif c == "Betriebsstatus":
            data[c] = ["InBetrieb"] * rows
        else:
            data[c] = [f"v{i}" for i in range(rows)]
    pq.write_table(pa.table(data), path)


@pytest.fixture()
def heterogeneous_parquet(tmp_path: Path) -> Path:
    """Build a fake parquet directory mirroring the eight unit entity types,
    with kernkraft deliberately skinny."""
    out = tmp_path / "parquet"
    out.mkdir()
    for key in ("solar", "wind", "biomasse", "wasser",
                "geothermie", "verbrennung", "stromspeicher"):
        _write_parquet(out / f"{key}.parquet", RICH_COLS)
    _write_parquet(out / "kernkraft.parquet", SKINNY_COLS)  # the troublemaker
    return out


def test_build_duckdb_handles_skinny_kernkraft(heterogeneous_parquet: Path) -> None:
    """Reproduce run #4: kernkraft lacks Gemeinde/PLZ/geo/Betriebsstatus.

    With the schema-aware projection these become NULLs and the v_units_all
    view binds successfully. Without it (the old code) DuckDB raised:
        Binder Error: Table "t" does not have a column named "Betriebsstatus"
    """
    con = duckdb.connect(":memory:")
    try:
        for key in ("solar", "wind", "biomasse", "wasser", "geothermie",
                    "kernkraft", "verbrennung", "stromspeicher"):
            n = _create_table(con, heterogeneous_parquet / f"{key}.parquet", key)
            assert n == 3, f"{key} should have loaded 3 rows"

        _create_bundesland_lookup(con)
        _build_units_view(con)  # this is the call that used to fail

        total = con.execute("SELECT COUNT(*) FROM v_units_all").fetchone()[0]
        assert total == 8 * 3  # 8 entities × 3 rows

        # Skinny kernkraft rows must show NULL for missing columns.
        skinny = con.execute("""
            SELECT gemeinde, plz, lat, lon, betriebsstatus
            FROM v_units_all
            WHERE source_table = 'kernkraft'
        """).fetchall()
        for row in skinny:
            assert row == (None, None, None, None, None), (
                f"kernkraft row should have NULLs for missing cols, got {row}"
            )

        # Rich rows must NOT be NULL.
        rich = con.execute("""
            SELECT gemeinde, betriebsstatus
            FROM v_units_all
            WHERE source_table = 'solar' LIMIT 1
        """).fetchone()
        assert rich[0] is not None and rich[1] is not None
    finally:
        con.close()


def test_aggregate_views_build_on_skinny_data(heterogeneous_parquet: Path) -> None:
    """_build_aggregate_views must succeed even when some tables are skinny."""
    con = duckdb.connect(":memory:")
    try:
        for key in ("solar", "wind", "biomasse", "wasser", "geothermie",
                    "kernkraft", "verbrennung", "stromspeicher"):
            _create_table(con, heterogeneous_parquet / f"{key}.parquet", key)
        _create_bundesland_lookup(con)
        _build_units_view(con)
        _build_aggregate_views(con)

        # Each view should query without error and return a non-negative count.
        for view in ("v_capacity_by_state", "v_buildout_monthly",
                     "v_capacity_by_plz"):
            n = con.execute(f"SELECT COUNT(*) FROM {view}").fetchone()[0]
            assert n >= 0
    finally:
        con.close()


def test_create_table_tolerates_missing_parquet(tmp_path: Path) -> None:
    """A missing parquet must log + return 0, never raise."""
    con = duckdb.connect(":memory:")
    try:
        rows = _create_table(con, tmp_path / "does-not-exist.parquet", "ghost")
        assert rows == 0
        # The phantom table must NOT exist after the call.
        n = con.execute(
            "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'ghost'"
        ).fetchone()[0]
        assert n == 0
    finally:
        con.close()


def test_units_view_skips_missing_entity_tables(tmp_path: Path) -> None:
    """If only some unit tables exist, v_units_all is built from those alone."""
    parquet_dir = tmp_path / "parquet"
    parquet_dir.mkdir()
    _write_parquet(parquet_dir / "solar.parquet", RICH_COLS)
    _write_parquet(parquet_dir / "wind.parquet", RICH_COLS)

    con = duckdb.connect(":memory:")
    try:
        _create_table(con, parquet_dir / "solar.parquet", "solar")
        _create_table(con, parquet_dir / "wind.parquet", "wind")
        _create_bundesland_lookup(con)
        _build_units_view(con)
        n = con.execute("SELECT COUNT(*) FROM v_units_all").fetchone()[0]
        assert n == 6  # 2 entities × 3 rows
        # source_table column must only have the two existing entities
        sources = sorted(r[0] for r in con.execute(
            "SELECT DISTINCT source_table FROM v_units_all").fetchall())
        assert sources == ["solar", "wind"]
    finally:
        con.close()


def test_wind_hub_height_dynamic_sql_skips_when_table_missing() -> None:
    """If wind never loaded, the aggregate query is skipped (returns None),
    not raised. Mirrors aggregates._wind_hub_height_sql behaviour."""
    con = duckdb.connect(":memory:")
    try:
        sql = _wind_hub_height_sql(con)
        assert sql is None
    finally:
        con.close()


def test_wind_hub_height_dynamic_sql_handles_skinny_wind(tmp_path: Path) -> None:
    """If wind exists but lacks Nabenhoehe/Rotordurchmesser, those project NULL."""
    parquet_dir = tmp_path / "parquet"
    parquet_dir.mkdir()
    _write_parquet(parquet_dir / "wind.parquet",
                   ["EinheitMastrNummer", "Bruttoleistung", "Bundesland"])

    con = duckdb.connect(":memory:")
    try:
        _create_table(con, parquet_dir / "wind.parquet", "wind")
        sql = _wind_hub_height_sql(con)
        assert sql is not None
        # The query must execute without binder errors even though
        # Nabenhoehe/Rotordurchmesser are absent.
        result = con.execute(sql).fetchall()
        # Filter "WHERE Nabenhoehe IS NOT NULL" -> 0 rows when the column is NULL.
        assert result == []
    finally:
        con.close()
