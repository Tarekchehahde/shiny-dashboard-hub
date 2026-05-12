"""
Detect BNetzA schema drift.

We maintain a tiny ``WORK/etl/schema_snapshot.json`` file that records, for each
entity, the set of XML child-element names we have ever observed. After every
nightly parse, this tool:

  1. Scans the fresh parquet files' columns
  2. Compares them to the snapshot
  3. If new/removed columns are found, writes a report + non-zero exits so CI
     can open a GitHub issue.

This is the **one place** where a human (me, the agent) still needs to
intervene — typically 1–2 times per year.
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import click
import pyarrow.parquet as pq

log = logging.getLogger("mastr.schema")


def _load_snapshot(path: Path) -> dict[str, list[str]]:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def _current_schema(parquet_dir: Path) -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for pq_file in sorted(parquet_dir.glob("*.parquet")):
        key = pq_file.stem
        out[key] = sorted(pq.ParquetFile(pq_file).schema_arrow.names)
    return out


def _diff(old: dict[str, list[str]], new: dict[str, list[str]]) -> dict[str, dict[str, list[str]]]:
    report: dict[str, dict[str, list[str]]] = {}
    keys = set(old) | set(new)
    for k in sorted(keys):
        o = set(old.get(k, []))
        n = set(new.get(k, []))
        added = sorted(n - o)
        removed = sorted(o - n)
        if added or removed:
            report[k] = {"added": added, "removed": removed}
    return report


@click.command()
@click.option("--parquet", "parquet_dir", type=click.Path(exists=True, path_type=Path),
              required=True)
@click.option("--snapshot", type=click.Path(path_type=Path), required=True,
              help="Path to schema_snapshot.json (committed to repo)")
@click.option("--update", is_flag=True, help="Write current schema to snapshot file")
@click.option("--report", "report_path", type=click.Path(path_type=Path),
              default=Path("schema_diff_report.md"), show_default=True)
def main(parquet_dir: Path, snapshot: Path, update: bool, report_path: Path) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    current = _current_schema(parquet_dir)

    if update:
        snapshot.write_text(json.dumps(current, indent=2, ensure_ascii=False))
        log.info("snapshot updated: %s (%d entities)", snapshot, len(current))
        return

    old = _load_snapshot(snapshot)
    if not old:
        log.warning("No snapshot at %s — creating one and exiting 0", snapshot)
        snapshot.write_text(json.dumps(current, indent=2, ensure_ascii=False))
        return

    report = _diff(old, current)
    if not report:
        log.info("Schema unchanged. ✔")
        return

    # Human-readable markdown report
    lines = ["# MaStR schema drift detected", ""]
    for entity, changes in report.items():
        lines.append(f"## `{entity}`")
        if changes["added"]:
            lines.append("**Added columns:**")
            lines += [f"- `{c}`" for c in changes["added"]]
        if changes["removed"]:
            lines.append("**Removed columns:**")
            lines += [f"- `{c}`" for c in changes["removed"]]
        lines.append("")
    report_path.write_text("\n".join(lines))
    log.error("Schema drift in %d entities — see %s", len(report), report_path)
    sys.exit(2)


if __name__ == "__main__":
    main()
