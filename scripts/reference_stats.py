"""Independent reference statistics computed directly from the CSV files (no database, no Mule).

Usage:
    python -I scripts/reference_stats.py [csv_directory]            # prints JSON
    python -I scripts/reference_stats.py --compare http://localhost:8081/api/v1 [csv_directory]

With --compare the figures returned by the API (computed from PostgreSQL) are checked against the CSV figures;
the exit code is 1 on any difference. The CSV directory defaults to data/reference/ (pristine copy of the sources).
"""
import csv
import json
import sys
import urllib.request
from collections import Counter
from decimal import Decimal
from pathlib import Path


def load(directory: Path):
    rows = []
    files = sorted(directory.glob("*.csv"))
    for f in files:
        with f.open(encoding="utf-8-sig", newline="") as fh:
            rows.extend(csv.DictReader(fh))
    return files, rows


def compute(rows):
    prices = [Decimal(r["price"]) for r in rows]
    data = [Decimal(r["data_gb"]) for r in rows if r["data_gb"].strip()]
    per_provider = Counter(r["provider"] for r in rows)
    unlimited = sum(1 for r in rows if not r["data_gb"].strip())
    buckets = [("0 – 10 €", None, 10), ("10 – 20 €", 10, 20), ("20 – 30 €", 20, 30), ("30 – 50 €", 30, 50),
               ("50 – 75 €", 50, 75), ("75 – 100 €", 75, 100), ("> 100 €", 100, None)]
    price_buckets = {}
    for label, lo, hi in buckets:
        price_buckets[label] = sum(1 for p in prices if (lo is None or p > lo) and (hi is None or p <= hi))
    return {
        "totalProducts": len(rows),
        "productsOver100": sum(1 for p in prices if p > 100),
        "priceMin": float(min(prices)),
        "priceMax": float(max(prices)),
        "priceAvg": float(round(sum(prices) / len(prices), 4)),
        "dataAvgGb": float(round(sum(data) / len(data), 4)),
        "numericDataCount": len(data),
        "unlimitedCount": unlimited,
        "providerCount": len(per_provider),
        "countryCount": len({r["country_code"] for r in rows}),
        "perProvider": dict(per_provider),
        "priceBuckets": price_buckets,
    }


def fetch(base, path):
    with urllib.request.urlopen(base.rstrip("/") + path, timeout=30) as resp:
        return json.load(resp)


def compare(base, expected):
    summary = fetch(base, "/dashboard/summary")
    providers = fetch(base, "/dashboard/providers")["items"]
    prices = fetch(base, "/dashboard/prices")["buckets"]
    problems = []
    for key in ("totalProducts", "productsOver100", "numericDataCount", "unlimitedCount", "providerCount", "countryCount"):
        if summary[key] != expected[key]:
            problems.append(f"{key}: api={summary[key]} csv={expected[key]}")
    for key in ("priceMin", "priceMax", "priceAvg", "dataAvgGb"):
        if abs(summary[key] - expected[key]) > 0.00005:
            problems.append(f"{key}: api={summary[key]} csv={expected[key]}")
    api_providers = {p["provider"]: p["productCount"] for p in providers}
    if api_providers != expected["perProvider"]:
        problems.append(f"perProvider differs: api={api_providers} csv={expected['perProvider']}")
    api_buckets = {b["label"]: b["count"] for b in prices}
    if api_buckets != expected["priceBuckets"]:
        problems.append(f"priceBuckets differs: api={api_buckets} csv={expected['priceBuckets']}")
    return problems


if __name__ == "__main__":
    args = sys.argv[1:]
    api = None
    if args and args[0] == "--compare":
        api = args[1]
        args = args[2:]
    directory = Path(args[0]) if args else Path(__file__).resolve().parent.parent / "data" / "reference"
    files, rows = load(directory)
    stats = compute(rows)
    stats["files"] = len(files)
    if api:
        problems = compare(api, stats)
        print(json.dumps({k: v for k, v in stats.items() if k not in ("perProvider", "priceBuckets")}, ensure_ascii=False))
        if problems:
            print("MISMATCH:\n  " + "\n  ".join(problems))
            sys.exit(1)
        print("OK: API figures (PostgreSQL) match the CSV figures")
    else:
        print(json.dumps(stats, ensure_ascii=False, indent=2))
