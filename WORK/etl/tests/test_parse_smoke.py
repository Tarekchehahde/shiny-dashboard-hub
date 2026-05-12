"""
Smoke test for the streaming parser.

We build a tiny synthetic ZIP with two fake <EinheitSolar> records and verify
that parse._parse_entity writes a Parquet file with the expected columns.
"""
from __future__ import annotations

import zipfile
from pathlib import Path

import pyarrow.parquet as pq

from mastr_etl.config import ENTITIES_BY_KEY
from mastr_etl.parse import _parse_entity


SAMPLE_XML = """<?xml version="1.0" encoding="utf-8"?>
<EinheitenSolar>
  <EinheitSolar>
    <EinheitMastrNummer>SEE900000000001</EinheitMastrNummer>
    <Bruttoleistung>9,84</Bruttoleistung>
    <Bundesland>1408</Bundesland>
    <Inbetriebnahmedatum>2021-03-15</Inbetriebnahmedatum>
    <Laengengrad>11.581</Laengengrad>
    <Breitengrad>48.135</Breitengrad>
  </EinheitSolar>
  <EinheitSolar>
    <EinheitMastrNummer>SEE900000000002</EinheitMastrNummer>
    <Bruttoleistung>330.0</Bruttoleistung>
    <Bundesland>1404</Bundesland>
    <Inbetriebnahmedatum>2022-07-01</Inbetriebnahmedatum>
  </EinheitSolar>
</EinheitenSolar>
"""


def test_parse_solar_tiny(tmp_path: Path) -> None:
    zip_path = tmp_path / "mastr-tiny.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("EinheitenSolar_1.xml", SAMPLE_XML)

    rows, cols = _parse_entity(zip_path, ENTITIES_BY_KEY["solar"], tmp_path / "out")
    assert rows == 2
    assert "EinheitMastrNummer" in cols
    assert "Bruttoleistung" in cols

    t = pq.read_table(tmp_path / "out" / "solar.parquet")
    assert t.num_rows == 2
    # numeric coercion: "9,84" -> 9.84
    vals = t.column("Bruttoleistung").to_pylist()
    assert 9.83 < vals[0] < 9.85
    assert vals[1] == 330.0
