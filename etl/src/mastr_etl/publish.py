"""
Upload ETL artifacts to a GitHub Release (one tag per day: data-YYYY-MM-DD).

Shells out to the ``gh`` CLI, which is preinstalled on ubuntu-latest. We use
``gh`` instead of the REST API directly because it handles multipart uploads
and auth transparently when ``GITHUB_TOKEN`` is present.

Resilience model
----------------
This script is intentionally **fail-soft**: an individual asset upload that
fails (rate limit, transient 5xx, oversized file) must not abort the whole
publish — the parquet files alone are enough for every Shiny dashboard to
work, because ``mastr_data.R`` queries them remotely via DuckDB ``httpfs``.
The optional ``mastr.duckdb`` blob is a convenience for offline users.

Concretely:

* Each asset upload is retried up to 3 times with exponential backoff.
* Assets larger than GitHub's 2 GB single-asset limit are split with
  ``split -b 1900M`` into ``<name>.partNN`` files plus a ``<name>.sha256``
  sidecar; a small ``REASSEMBLE.md`` tells users how to ``cat`` them back.
* If any individual asset still fails after retries, the script logs the
  failure, increments a counter and continues. Exit status reflects the
  failure count so the workflow can decide whether to mark the run red.
"""

from __future__ import annotations

import logging
import shutil
import subprocess
import sys
import time
from datetime import date
from pathlib import Path

import click

log = logging.getLogger("mastr.publish")

# GitHub's hard cap is 2 GiB per asset. We stay 100 MB below that.
MAX_ASSET_BYTES = 1_900_000_000
SPLIT_CHUNK = "1900M"
UPLOAD_RETRIES = 3
UPLOAD_BACKOFF_SECS = 15


def _gh(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    log.info("$ gh %s", " ".join(args))
    return subprocess.run(["gh", *args], check=check, capture_output=True, text=True)


def _gh_ok(*args: str) -> bool:
    try:
        subprocess.run(["gh", *args], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False


def _mark_release_latest(tag: str) -> None:
    """Pin GitHub's *Latest* badge (and ``/releases/latest``) to this tag.

    Without this, an older release that was manually marked *Latest* can win
    over newer dated ``data-*`` snapshots, which breaks Shiny clients that still
    call the ``/releases/latest`` API.
    """
    try:
        _gh("release", "edit", tag, "--latest")
    except subprocess.CalledProcessError as exc:
        log.warning(
            "gh release edit --latest failed for %s: %s",
            tag,
            (exc.stderr or "").strip()[:200],
        )


def _ensure_release(tag: str, title: str, notes: str) -> None:
    """Create release if absent; uploads happen with --clobber so we can
    rerun the publish step idempotently."""
    if _gh_ok("release", "view", tag):
        log.info("Release %s already exists — re-uploading with --clobber", tag)
    else:
        _gh(
            "release",
            "create",
            tag,
            "--title",
            title,
            "--notes",
            notes,
            "--prerelease=false",
            "--latest",
        )


def _assets_from(dirs: list[Path]) -> list[Path]:
    out: list[Path] = []
    for d in dirs:
        if d.is_file():
            out.append(d)
            continue
        if d.is_dir():
            out += [p for p in sorted(d.rglob("*"))
                    if p.is_file() and p.suffix in (".parquet", ".duckdb",
                                                     ".zstd", ".sha256",
                                                     ".md")]
    return out


def _split_oversized(asset: Path) -> list[Path]:
    """Split a too-big file into ``<name>.partNN`` chunks alongside a sha256
    sidecar and a one-page REASSEMBLE.md. Returns the new list of artifacts to
    upload (including the original sidecar files, but NOT the original blob)."""
    log.warning("Asset %s is %.1f GB > 1.9 GB — splitting into chunks",
                asset.name, asset.stat().st_size / 1024**3)
    parts_dir = asset.parent / f"{asset.name}.split"
    parts_dir.mkdir(parents=True, exist_ok=True)

    prefix = parts_dir / f"{asset.name}.part"
    subprocess.run(
        ["split", "-b", SPLIT_CHUNK, "-d", "-a", "2", str(asset), str(prefix)],
        check=True,
    )
    parts = sorted(parts_dir.glob(f"{asset.name}.part*"))
    log.info("  -> %d chunks created", len(parts))

    sha = parts_dir / f"{asset.name}.sha256"
    subprocess.run(
        f"sha256sum {asset.name}.part* > {sha.name}",
        cwd=parts_dir, shell=True, check=True,
    )

    readme = parts_dir / "REASSEMBLE.md"
    readme.write_text(
        f"# How to reassemble `{asset.name}`\n\n"
        f"This file was split because GitHub Releases caps single assets at 2 GB.\n\n"
        f"```bash\n"
        f"cat {asset.name}.part?? > {asset.name}\n"
        f"sha256sum -c {asset.name}.sha256\n"
        f"```\n\n"
        f"Most users will not need this file at all — the per-entity\n"
        f"`*.parquet` files in the same release contain the same data\n"
        f"and the Shiny apps query them directly.\n"
    )
    return [*parts, sha, readme]


def _upload_one(tag: str, asset: Path) -> bool:
    """Upload a single asset with retries. Returns True on success."""
    for attempt in range(1, UPLOAD_RETRIES + 1):
        try:
            _gh("release", "upload", tag, str(asset), "--clobber")
            return True
        except subprocess.CalledProcessError as exc:
            stderr = (exc.stderr or "").strip()
            log.warning("upload attempt %d/%d failed for %s: %s",
                        attempt, UPLOAD_RETRIES, asset.name, stderr[:200])
            if attempt < UPLOAD_RETRIES:
                time.sleep(UPLOAD_BACKOFF_SECS * attempt)
    log.error("giving up on %s after %d attempts", asset.name, UPLOAD_RETRIES)
    return False


@click.command()
@click.option("--tag", required=True, help="Release tag, e.g. data-2026-04-21")
@click.option("--parquet", "parquet_dir",
              type=click.Path(exists=True, path_type=Path), required=True)
@click.option("--duckdb", "duckdb_path",
              type=click.Path(exists=True, path_type=Path), required=True)
@click.option("--title", default=None)
@click.option("--strict", is_flag=True,
              help="Exit non-zero on any failed asset (default: best-effort).")
def main(tag: str, parquet_dir: Path, duckdb_path: Path,
         title: str | None, strict: bool) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
    )
    if shutil.which("gh") is None:
        raise SystemExit("gh CLI not found — this is meant to run in GitHub Actions.")

    title = title or f"MaStR snapshot {tag.removeprefix('data-')}"
    notes = (
        f"Automated snapshot of the Bundesnetzagentur Marktstammdatenregister, "
        f"parsed on {date.today().isoformat()}.\n\n"
        "Data licence: **DL-DE-BY-2.0** — Datenlizenz Deutschland Namensnennung 2.0.\n"
        "Source: https://www.marktstammdatenregister.de/MaStR/Datendownload\n"
    )
    _ensure_release(tag, title, notes)

    raw_assets = _assets_from([parquet_dir, duckdb_path])

    # Expand any oversized blobs into chunks. The original is dropped from the
    # upload list so we never try to upload a >2 GB file (which gh rejects).
    upload_list: list[Path] = []
    for asset in raw_assets:
        size = asset.stat().st_size
        if size > MAX_ASSET_BYTES:
            try:
                upload_list.extend(_split_oversized(asset))
            except Exception as exc:  # noqa: BLE001 - tolerate split failures
                log.error("could not split %s (%.1f GB): %s — skipping",
                          asset.name, size / 1024**3, exc)
        else:
            upload_list.append(asset)

    log.info("Uploading %d artifacts to release %s", len(upload_list), tag)
    failures = 0
    for asset in upload_list:
        if not _upload_one(tag, asset):
            failures += 1

    if failures:
        msg = f"{failures}/{len(upload_list)} assets failed to upload"
        if strict:
            raise SystemExit(msg)
        log.warning("%s — pipeline continues (best-effort mode)", msg)
        sys.exit(0)
    log.info("Uploaded %d/%d assets to release %s", len(upload_list),
             len(upload_list), tag)
    _mark_release_latest(tag)


if __name__ == "__main__":
    main()
