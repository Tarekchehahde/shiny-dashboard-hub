"""
Download the MaStR Gesamtdatenexport ZIP from BNetzA.

* Streamed (doesn't hold the ~2.8 GB ZIP in RAM).
* Retried with exponential backoff.
* SHA-256 written next to the ZIP for downstream verification.
* Prints a progress bar when run in a TTY; structured log lines in CI.
"""

from __future__ import annotations

import hashlib
import logging
import os
import re
import sys
from pathlib import Path

import click
import requests
from tenacity import retry, stop_after_attempt, wait_exponential
from tqdm import tqdm

from .config import DEFAULT_ZIP_URL, MASTR_DOWNLOAD_PAGE

log = logging.getLogger("mastr.download")

CHUNK = 1024 * 1024  # 1 MiB


def _resolve_url(explicit: str | None) -> str:
    """Prefer env var, then CLI arg, then default. Scrape as last resort."""
    if explicit:
        return explicit
    env = os.environ.get("MASTR_DOWNLOAD_URL")
    if env:
        return env
    # Default first; only scrape if the default HEADs as a non-200.
    try:
        head = requests.head(DEFAULT_ZIP_URL, allow_redirects=True, timeout=30)
        if head.status_code < 400:
            return DEFAULT_ZIP_URL
    except requests.RequestException as exc:
        log.warning("HEAD of default URL failed (%s); trying page scrape", exc)
    return _scrape_zip_url()


def _scrape_zip_url() -> str:
    """
    Fallback: fetch the Datendownload page and pick the latest ZIP link.

    The page has been structurally stable since 2021; the first ZIP link in the
    'Gesamtdatenauszug vom Vortag' section is always the nightly export.
    """
    r = requests.get(MASTR_DOWNLOAD_PAGE, timeout=60)
    r.raise_for_status()
    matches = re.findall(r'href="([^"]+\.zip)"', r.text)
    if not matches:
        raise RuntimeError("No .zip link found on MaStR Datendownload page")
    url = matches[0]
    if url.startswith("/"):
        url = "https://www.marktstammdatenregister.de" + url
    log.info("Resolved ZIP URL via scrape: %s", url)
    return url


# Per-chunk read timeout. With CHUNK = 1 MiB even a 50 KB/s stall would still
# deliver a chunk every ~20 s, so 180 s gives generous margin while failing
# loudly if BNetzA's CDN truly silences us. tenacity then retries.
_CONNECT_TIMEOUT = 30
_READ_TIMEOUT = 180


@retry(stop=stop_after_attempt(5), wait=wait_exponential(multiplier=5, max=120))
def _stream_download(url: str, dest: Path) -> int:
    """Stream ``url`` into ``dest`` with a progress log every ~5 % (CI-friendly)."""
    import time
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    log.info("attempt: GET %s (connect=%ds, read=%ds)", url, _CONNECT_TIMEOUT, _READ_TIMEOUT)
    with requests.get(url, stream=True, timeout=(_CONNECT_TIMEOUT, _READ_TIMEOUT)) as r:
        r.raise_for_status()
        total = int(r.headers.get("Content-Length") or 0)
        sha = hashlib.sha256()
        written = 0
        is_tty = sys.stderr.isatty()
        bar = tqdm(
            total=total or None,
            unit="B",
            unit_scale=True,
            desc="MaStR ZIP",
            disable=not is_tty,
        )
        # CI-friendly heartbeat: log every 5 % or every 30 s
        next_pct = 0.05
        last_log = time.monotonic()
        with tmp.open("wb") as fh:
            for chunk in r.iter_content(chunk_size=CHUNK):
                if not chunk:
                    continue
                fh.write(chunk)
                sha.update(chunk)
                written += len(chunk)
                bar.update(len(chunk))
                if not is_tty:
                    pct = (written / total) if total else 0
                    now = time.monotonic()
                    if pct >= next_pct or now - last_log > 30:
                        if total:
                            log.info(
                                "download progress: %5.1f %%  (%.1f / %.1f MiB)",
                                pct * 100, written / 1024**2, total / 1024**2,
                            )
                        else:
                            log.info(
                                "download progress: %.1f MiB (total unknown)",
                                written / 1024**2,
                            )
                        sys.stderr.flush()
                        next_pct = pct + 0.05
                        last_log = now
        bar.close()
    if total and abs(written - total) > 1024:
        # Length mismatch usually means a truncated transfer.
        raise IOError(
            f"Short read: got {written} bytes, expected {total}. Will retry."
        )
    tmp.rename(dest)
    dest.with_suffix(dest.suffix + ".sha256").write_text(
        f"{sha.hexdigest()}  {dest.name}\n"
    )
    log.info("Downloaded %s (%.1f GiB)", dest, written / 1024**3)
    return written


@click.command()
@click.option("--out", "out_dir", type=click.Path(path_type=Path), required=True,
              help="Output directory (ZIP + sha256 written here).")
@click.option("--url", default=None, help="Override ZIP URL.")
@click.option("--filename", default="mastr-latest.zip", show_default=True)
def main(out_dir: Path, url: str | None, filename: str) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s :: %(message)s",
        stream=sys.stderr,
    )
    # Reconfigure stdout/stderr to be line-buffered (belt-and-braces alongside
    # PYTHONUNBUFFERED=1 / python -u). Guarantees every log line flushes to
    # the GH Actions log stream the moment it is emitted.
    try:
        sys.stdout.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
        sys.stderr.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
    except Exception:
        pass
    # Build banner: proves in the logs which code revision is executing.
    # Bump this string whenever download.py is touched.
    log.info("mastr.download build=heartbeat-v3 (unbuffered, 180s read, 5 retries)")
    resolved = _resolve_url(url)
    dest = out_dir / filename
    log.info("Downloading %s -> %s", resolved, dest)
    _stream_download(resolved, dest)


if __name__ == "__main__":
    main()
