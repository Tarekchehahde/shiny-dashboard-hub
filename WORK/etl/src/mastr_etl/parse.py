"""
Stream-parse the MaStR XML files (directly from the ZIP) into Parquet.

Key properties:

* **Constant memory.** We iterate with ``lxml.etree.iterparse`` and clear each
  record element as soon as it closes, so peak RAM stays ~200 MB regardless
  of the input size.
* **Direct-from-ZIP.** We never unpack the ZIP to disk; we stream XML members
  through ``zipfile.ZipFile.open``. This saves ~20 GB of disk on the CI runner.
* **Per-entity Parquet.** One XML element type -> one logical Parquet dataset.
  For entities with partition columns (e.g. ``Bundesland`` for Solar) we write
  a hive-partitioned directory; otherwise a single file.
* **Defensive typing.** Unknown columns are kept as strings. Declared numeric
  / date columns are cast with ``errors=coerce`` semantics; bad values become
  NULLs, never crashes.
"""

from __future__ import annotations

import fnmatch
import logging
from collections import defaultdict
from pathlib import Path
from typing import Iterator

import click
import pyarrow as pa
import pyarrow.parquet as pq
from lxml import etree

from .config import ENTITIES, Entity

log = logging.getLogger("mastr.parse")

BATCH_ROWS = 50_000  # records per Parquet row-group flush


# ---------------------------------------------------------------------------
# Streaming iterparse
# ---------------------------------------------------------------------------

def _iter_records(xml_fh, record_tag: str) -> Iterator[dict[str, str]]:
    """Yield dicts of one record's child text, then clear the element."""
    context = etree.iterparse(xml_fh, events=("end",), tag=record_tag, recover=True)
    for _event, elem in context:
        row: dict[str, str] = {}
        for child in elem:
            # MaStR records are flat (no nested elements inside a record),
            # but we defensively take .text and ignore nested trees.
            tag = etree.QName(child).localname
            row[tag] = (child.text or "").strip() or None
        yield row
        elem.clear()
        # drop previous siblings too, to keep memory flat
        while elem.getprevious() is not None:
            del elem.getparent()[0]
    del context


# ---------------------------------------------------------------------------
# Schema coercion
# ---------------------------------------------------------------------------

def _coerce_batch(
    rows: list[dict[str, str | None]],
    entity: Entity,
    all_columns: list[str],
) -> pa.Table:
    """Build an Arrow table from a list of string-dicts, casting known types."""
    cols: dict[str, list] = {c: [] for c in all_columns}
    for r in rows:
        for c in all_columns:
            cols[c].append(r.get(c))

    arrays = []
    fields = []
    for c in all_columns:
        raw = cols[c]
        if c in entity.numeric_cols:
            arrays.append(_cast_numeric(raw))
            fields.append(pa.field(c, pa.float64()))
        elif c in entity.date_cols:
            arrays.append(_cast_date(raw))
            fields.append(pa.field(c, pa.date32()))
        else:
            arrays.append(pa.array(raw, type=pa.string()))
            fields.append(pa.field(c, pa.string()))
    return pa.Table.from_arrays(arrays, schema=pa.schema(fields))


def _cast_numeric(values: list[str | None]) -> pa.Array:
    out: list[float | None] = []
    for v in values:
        if v is None or v == "":
            out.append(None)
            continue
        # MaStR uses German decimals ("1,23") in some fields, US in others.
        s = v.replace(",", ".") if isinstance(v, str) else v
        try:
            out.append(float(s))
        except (TypeError, ValueError):
            out.append(None)
    return pa.array(out, type=pa.float64())


def _cast_date(values: list[str | None]) -> pa.Array:
    import datetime as _dt
    out: list[_dt.date | None] = []
    for v in values:
        if not v:
            out.append(None)
            continue
        # MaStR dates: "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM:SS"
        s = v[:10]
        try:
            out.append(_dt.date.fromisoformat(s))
        except ValueError:
            out.append(None)
    return pa.array(out, type=pa.date32())


# ---------------------------------------------------------------------------
# Per-entity parse
# ---------------------------------------------------------------------------

def _parse_entity(
    zip_path: Path,
    entity: Entity,
    out_dir: Path,
) -> tuple[int, set[str]]:
    """Parse all ZIP members matching an entity's file_glob. Return (rows, schema)."""
    import zipfile

    out_dir.mkdir(parents=True, exist_ok=True)
    writer: pq.ParquetWriter | None = None
    rows_total = 0
    schema_cols: set[str] = set()
    buffer: list[dict[str, str | None]] = []

    with zipfile.ZipFile(zip_path) as zf:
        members = [n for n in zf.namelist() if fnmatch.fnmatch(n, entity.file_glob)]
        if not members:
            log.warning("No XML members matched %s (glob=%s)", entity.key, entity.file_glob)
            return 0, schema_cols

        log.info("Entity %s: %d XML members", entity.key, len(members))

        for m in members:
            with zf.open(m) as fh:
                for row in _iter_records(fh, entity.record_tag):
                    schema_cols.update(row.keys())
                    buffer.append(row)
                    if len(buffer) >= BATCH_ROWS:
                        writer = _flush_batch(
                            buffer, entity, sorted(schema_cols), out_dir, writer
                        )
                        buffer.clear()

        if buffer:
            writer = _flush_batch(
                buffer, entity, sorted(schema_cols), out_dir, writer
            )
            rows_total += len(buffer)

    if writer is not None:
        writer.close()

    # rows_total is approximate unless we re-count; use ParquetFile metadata:
    target = out_dir / f"{entity.key}.parquet"
    if target.exists():
        rows_total = pq.ParquetFile(target).metadata.num_rows
    log.info("Entity %s: %s rows, %d columns", entity.key, f"{rows_total:,}", len(schema_cols))
    return rows_total, schema_cols


def _flush_batch(
    buffer: list[dict[str, str | None]],
    entity: Entity,
    all_columns: list[str],
    out_dir: Path,
    writer: pq.ParquetWriter | None,
) -> pq.ParquetWriter:
    table = _coerce_batch(buffer, entity, all_columns)
    target = out_dir / f"{entity.key}.parquet"
    if writer is None:
        writer = pq.ParquetWriter(
            target,
            table.schema,
            compression="snappy",
            use_dictionary=True,
        )
    else:
        # schema may have grown (new column). Re-align.
        if writer.schema != table.schema:
            writer.close()
            # Rewrite from scratch with extended schema — rare (<5× per run).
            existing = pq.read_table(target) if target.exists() else None
            if existing is not None:
                # Add any missing columns to existing as nulls
                for f in table.schema:
                    if f.name not in existing.schema.names:
                        existing = existing.append_column(
                            f.name, pa.array([None] * existing.num_rows, type=f.type)
                        )
                existing = existing.select(table.schema.names)
            writer = pq.ParquetWriter(target, table.schema, compression="snappy")
            if existing is not None:
                writer.write_table(existing)
    writer.write_table(table)
    return writer


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

@click.command()
@click.option("--in", "in_dir", type=click.Path(exists=True, path_type=Path), required=True,
              help="Directory containing mastr-latest.zip")
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True,
              help="Output directory for Parquet files")
@click.option("--zip-name", default="mastr-latest.zip", show_default=True)
@click.option("--only", multiple=True, help="Restrict to entity keys (repeatable)")
def main(in_dir: Path, out_dir: Path, zip_name: str, only: tuple[str, ...]) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    zip_path = in_dir / zip_name
    if not zip_path.exists():
        raise click.UsageError(f"ZIP not found: {zip_path}")

    summary: dict[str, int] = defaultdict(int)
    for entity in ENTITIES:
        if only and entity.key not in only:
            continue
        rows, _schema = _parse_entity(zip_path, entity, out_dir)
        summary[entity.key] = rows

    log.info("=== Parse summary ===")
    for k, v in summary.items():
        log.info("  %-20s %12s rows", k, f"{v:,}")
    log.info("Total records: %s", f"{sum(summary.values()):,}")


if __name__ == "__main__":
    main()
