#!/usr/bin/env python3
"""Fetch Germany-focused Eurostat natural-gas cubes for the diversification dashboard.

Cubes (geo=DE slices; not the dense EU-wide cartesian products):
  nrg_ti_gas     annual imports by partner (ultimate origin)
  nrg_ti_gasm    monthly imports by partner (last transit country)
  nrg_ind_id     energy import dependency (DE + EU27)
  nrg_stk_gasm   monthly gas stocks
  nrg_cb_gasm    monthly supply / consumption
  nrg_pc_202     household gas prices
  nrg_pc_203     industrial gas prices

Re-fetch only when any cube `updated` stamp changed.
"""
from __future__ import annotations

import csv
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data"
UA = "mastr-eurostat-de-gas/1.0 (https://82.165.167.86/)"
OUT_DIR = Path(os.environ.get("MASTR_EUROSTAT_DIR", "/var/lib/mastr-shiny/eurostat/nrg_gas_de"))
STATE = Path(os.environ.get("MASTR_EUROSTAT_STATE", "/var/lib/mastr-shiny/eurostat-de-gas-updated"))

CUBES = [
    {
        "code": "nrg_ti_gas",
        "file": "imports_annual.csv",
        "dims": ["siec", "partner", "time"],
        "params": [("geo", "DE"), ("unit", "TJ_GCV"), ("lang", "en")],
    },
    {
        "code": "nrg_ti_gasm",
        "file": "imports_monthly.csv",
        "dims": ["siec", "partner", "time"],
        "params": [("geo", "DE"), ("unit", "TJ_GCV"), ("lang", "en")],
    },
    {
        "code": "nrg_ind_id",
        "file": "dependency.csv",
        "dims": ["siec", "geo", "time"],
        "params": [("geo", "DE"), ("geo", "EU27_2020"), ("lang", "en")],
    },
    {
        "code": "nrg_stk_gasm",
        "file": "stocks_monthly.csv",
        "dims": ["stk_flow", "time"],
        "params": [("geo", "DE"), ("unit", "TJ_GCV"), ("siec", "G3000"), ("lang", "en")],
    },
    {
        "code": "nrg_cb_gasm",
        "file": "supply_monthly.csv",
        "dims": ["nrg_bal", "time"],
        "params": [("geo", "DE"), ("unit", "TJ_GCV"), ("siec", "G3000"), ("lang", "en")],
    },
    {
        "code": "nrg_pc_202",
        "file": "prices_household.csv",
        "dims": ["nrg_cons", "tax", "time"],
        "params": [
            ("geo", "DE"),
            ("unit", "KWH"),
            ("currency", "EUR"),
            ("lang", "en"),
        ],
    },
    {
        "code": "nrg_pc_203",
        "file": "prices_industrial.csv",
        "dims": ["nrg_cons", "tax", "time"],
        "params": [
            ("geo", "DE"),
            ("unit", "KWH"),
            ("currency", "EUR"),
            ("lang", "en"),
        ],
    },
]


def http_json(code: str, params: list[tuple[str, str]]) -> dict:
    q = urllib.parse.urlencode(params)
    url = f"{API}/{code}?{q}"
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as resp:
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


def keep_dims(rows: list[dict], dims: list[str]) -> list[dict]:
    out = []
    for r in rows:
        rec = {d: r.get(d, "") for d in dims}
        rec.update({f"{d}_label": r.get(f"{d}_label", rec[d]) for d in dims})
        rec["value"] = r.get("value")
        out.append(rec)
    return out


def write_csv(path: Path, rows: list[dict], cols: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def probe_updated() -> dict[str, str]:
    stamps = {}
    for cube in CUBES:
        # lastTimePeriod=1 is enough to read `updated`
        params = list(cube["params"]) + [("lastTimePeriod", "1")]
        js = http_json(cube["code"], params)
        stamps[cube["code"]] = str(js.get("updated") or "")
    return stamps


def ingest(force: bool = False) -> str:
    prev = {}
    if STATE.exists():
        raw = STATE.read_text(encoding="utf-8").strip()
        if raw.startswith("{"):
            prev = json.loads(raw)
        elif raw:
            prev = {"_legacy": raw}

    stamps = probe_updated()
    if not force and prev == stamps and (OUT_DIR / "meta.json").exists():
        return "unchanged " + ",".join(f"{k}={v}" for k, v in stamps.items())

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    counts = {}
    titles = {}
    for cube in CUBES:
        js = http_json(cube["code"], cube["params"])
        titles[cube["code"]] = js.get("label")
        stamps[cube["code"]] = str(js.get("updated") or stamps.get(cube["code"], ""))
        rows = keep_dims(flatten(js), cube["dims"])
        cols = []
        for d in cube["dims"]:
            cols.extend([d, f"{d}_label"])
        cols.append("value")
        write_csv(OUT_DIR / cube["file"], rows, cols)
        counts[cube["code"]] = len(rows)

    meta = {
        "source": "Eurostat",
        "geo": "DE",
        "unit_imports": "TJ_GCV",
        "updated": stamps,
        "titles": titles,
        "n": counts,
        "note": (
            "Annual nrg_ti_gas is country of origin; monthly nrg_ti_gasm is last "
            "transit country. Do not mix the two in one chart."
        ),
        "browser": {
            c["code"]: f"https://ec.europa.eu/eurostat/databrowser/view/{c['code']}/default/table?lang=en"
            for c in CUBES
        },
    }
    (OUT_DIR / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(stamps, indent=2) + "\n", encoding="utf-8")
    return f"refreshed -> {OUT_DIR} " + json.dumps(counts)


def main() -> int:
    force = "--force" in sys.argv
    try:
        msg = ingest(force=force)
    except Exception as exc:
        print(f"eurostat-de-gas: FAIL {exc}", file=sys.stderr)
        return 1
    print(f"eurostat-de-gas: {msg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
