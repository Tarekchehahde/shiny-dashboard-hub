#!/usr/bin/env python3
"""Fetch Eurostat migr_asyrescra as small aggregated slices (not the 214M cube).

The catalogue 'values' count is the dense cartesian product (mostly zeros).
We query JSON-stat with TOTAL filters so the dashboard stays a few tens of
thousands of rows. Re-fetch only when the source `updated` timestamp changes.
"""
from __future__ import annotations

import csv
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

DATASET = "migr_asyrescra"
API = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data"
UA = "mastr-eurostat-resettled/1.0 (https://82.165.167.86/)"
OUT_DIR = Path(os.environ.get("MASTR_EUROSTAT_DIR", "/var/lib/mastr-shiny/eurostat/migr_asyrescra"))
STATE = Path(os.environ.get("MASTR_EUROSTAT_STATE", "/var/lib/mastr-shiny/eurostat-resettled-updated"))


def http_json(params: dict) -> dict:
    q = urllib.parse.urlencode(params)
    url = f"{API}/{DATASET}?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def dim_codes(js: dict, dim: str) -> list[str]:
    idx = js["dimension"][dim]["category"]["index"]
    if isinstance(idx, dict):
        ordered = [""] * len(idx)
        for code, pos in idx.items():
            ordered[int(pos)] = code
        return ordered
    return list(idx)


def dim_label(js: dict, dim: str, code: str) -> str:
    return (js["dimension"][dim]["category"].get("label") or {}).get(code, code)


def flatten(js: dict) -> list[dict]:
    ids = js["id"]
    sizes = js["size"]
    codes = {d: dim_codes(js, d) for d in ids}
    rows = []
    for lin, val in (js.get("value") or {}).items():
        i = int(lin)
        rec = {"value": val}
        for di, d in enumerate(ids):
            stride = 1
            for s in sizes[di + 1 :]:
                stride *= int(s)
            pos = (i // stride) % int(sizes[di])
            code = codes[d][pos]
            rec[d] = code
            rec[f"{d}_label"] = dim_label(js, d, code)
        rows.append(rec)
    return rows


def write_csv(path: Path, rows: list[dict], cols: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def keep_dims(rows: list[dict], dims: list[str]) -> list[dict]:
    out = []
    for r in rows:
        rec = {d: r.get(d, "") for d in dims}
        rec.update({f"{d}_label": r.get(f"{d}_label", rec[d]) for d in dims})
        rec["value"] = r.get("value")
        out.append(rec)
    return out


def source_updated() -> str:
    js = http_json({"sex": "T", "age": "TOTAL", "citizen": "TOTAL", "c_resid": "TOTAL", "lang": "en"})
    return str(js.get("updated") or "")


def ingest(force: bool = False) -> str:
    prev = STATE.read_text().strip() if STATE.exists() else ""
    # Probe with the smallest slice
    geo_js = http_json(
        {"sex": "T", "age": "TOTAL", "citizen": "TOTAL", "c_resid": "TOTAL", "lang": "en"}
    )
    updated = str(geo_js.get("updated") or "")
    if not force and prev and prev == updated and (OUT_DIR / "meta.json").exists():
        return f"unchanged {updated}"

    citizen_js = http_json(
        {"sex": "T", "age": "TOTAL", "c_resid": "TOTAL", "lang": "en"}
    )
    origin_js = http_json(
        {"sex": "T", "age": "TOTAL", "citizen": "TOTAL", "lang": "en"}
    )
    agesex_js = http_json(
        {"citizen": "TOTAL", "c_resid": "TOTAL", "lang": "en"}
    )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    geo_rows = keep_dims(flatten(geo_js), ["geo", "time"])
    cit_rows = keep_dims(flatten(citizen_js), ["geo", "citizen", "time"])
    ori_rows = keep_dims(flatten(origin_js), ["geo", "c_resid", "time"])
    as_rows = keep_dims(flatten(agesex_js), ["geo", "sex", "age", "time"])

    write_csv(OUT_DIR / "by_geo.csv", geo_rows, ["geo", "geo_label", "time", "value"])
    write_csv(
        OUT_DIR / "by_citizen.csv",
        cit_rows,
        ["geo", "geo_label", "citizen", "citizen_label", "time", "value"],
    )
    write_csv(
        OUT_DIR / "by_origin.csv",
        ori_rows,
        ["geo", "geo_label", "c_resid", "c_resid_label", "time", "value"],
    )
    write_csv(
        OUT_DIR / "by_age_sex.csv",
        as_rows,
        ["geo", "geo_label", "sex", "sex_label", "age", "age_label", "time", "value"],
    )
    meta = {
        "dataset": DATASET,
        "title": geo_js.get("label"),
        "updated": updated,
        "source": "Eurostat",
        "browser": f"https://ec.europa.eu/eurostat/databrowser/view/{DATASET}/default/table?lang=en",
        "note": "Aggregated TOTAL slices only; full cube is ~214 million dense cells.",
        "n_geo": len(geo_rows),
        "n_citizen": len(cit_rows),
        "n_origin": len(ori_rows),
        "n_age_sex": len(as_rows),
    }
    (OUT_DIR / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(updated + "\n", encoding="utf-8")
    return f"refreshed {updated} -> {OUT_DIR}"


def main() -> int:
    force = "--force" in sys.argv
    try:
        msg = ingest(force=force)
    except Exception as exc:
        print(f"eurostat-resettled: FAIL {exc}", file=sys.stderr)
        return 1
    print(f"eurostat-resettled: {msg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
