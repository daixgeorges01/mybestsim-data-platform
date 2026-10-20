"""End-to-end integration tests against the running local stack (PostgreSQL in Docker + Mule runtime).

DESTRUCTIVE for the dev database: it TRUNCATEs the catalogue tables and moves CSV files in data/.
Run it only on the local dev stack:

    ALLOW_DESTRUCTIVE_TESTS=1 python -I scripts/tests/integration_test.py -v

Prerequisites: docker compose up -d postgres; migrations applied; Mule running (scripts/run-mule.ps1 or
scripts/redeploy-local.sh) with the dev configuration (scheduler disabled).
"""
import csv
import io
import json
import os
import subprocess
import sys
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
INCOMING, PROCESSED, REJECTED, REFERENCE = (ROOT / "data" / d for d in ("incoming", "processed", "rejected", "reference"))
API = os.environ.get("API_BASE_URL", "http://localhost:8081/api/v1")
KEY = os.environ.get("MYBESTSIM_ADMIN_API_KEY", "dev-only-change-me")
PG_CONTAINER = "mybestsim-postgres"
DB = os.environ.get("POSTGRES_DB", "mybestsim")
DB_USER = os.environ.get("POSTGRES_USER", "mybestsim")
HEADER = "sku,provider,product_name,country_code,country_name,data_gb,data_display,validity_days,price,currency,network,top_up"


def psql(sql, db=DB):
    out = subprocess.run(["docker", "exec", "-i", PG_CONTAINER, "psql", "-U", DB_USER, "-d", db, "-At", "-F", "|", "-v", "ON_ERROR_STOP=1"],
                         input=sql, capture_output=True, text=True, encoding="utf-8")
    if out.returncode:
        raise RuntimeError(out.stderr.strip())
    return [line.split("|") for line in out.stdout.strip().splitlines() if line]


def scalar(sql):
    return psql(sql)[0][0]


def call(path, method="GET", headers=None, timeout=300):
    req = urllib.request.Request(API + path, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, (json.loads(body) if body else None), dict(resp.headers)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8")
        return e.code, (json.loads(body) if body else None), dict(e.headers)


def trigger():
    return call("/imports", "POST", {"X-API-Key": KEY})


def clean_dirs():
    for d in (INCOMING, PROCESSED, REJECTED):
        for f in d.iterdir():
            if f.is_file() and f.name != ".gitkeep":
                f.unlink()


def reset():
    psql("TRUNCATE import_errors, import_runs, esim_products, providers, import_lock RESTART IDENTITY CASCADE")
    clean_dirs()


def write_csv(name, lines, header=HEADER):
    (INCOMING / name).write_text(header + "\n" + "\n".join(lines) + ("\n" if lines else ""), encoding="utf-8", newline="\n")


def files(directory, prefix):
    return sorted(f.name for f in directory.iterdir() if f.name.startswith(prefix))


def row(sku, price="10.00", data="5", display=None, validity="7", cc="FR", cn="France", cur="EUR", net="4G", top="oui", provider="TestProv"):
    display = display if display is not None else (f"{data} Go" if data else "Illimité")
    return f"{sku},{provider},eSIM {cn} {display} {validity} jours,{cc},{cn},{data},{display},{validity},{price},{cur},{net},{top}"


def wait_for_db(timeout=90):
    end = time.time() + timeout
    while time.time() < end:
        try:
            if scalar("select 1") == "1":
                return True
        except Exception:
            time.sleep(2)
    return False


class IntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("ALLOW_DESTRUCTIVE_TESTS") != "1":
            raise unittest.SkipTest("set ALLOW_DESTRUCTIVE_TESTS=1 (the dev database is truncated)")
        status, _, _ = call("/dashboard/summary")
        assert status == 200, "Mule API not reachable"
        reset()

    # ---- 01: empty database ------------------------------------------------------------
    def test_01_empty_database_endpoints_are_consistent(self):
        s, body, h = call("/dashboard/summary")
        self.assertEqual(s, 200)
        self.assertFalse(body["hasData"])
        self.assertEqual((body["totalProducts"], body["productsOver100"], body["unlimitedCount"]), (0, 0, 0))
        for k in ("priceMin", "priceMax", "priceAvg", "dataAvgGb"):
            self.assertIsNone(body[k])
        self.assertEqual(call("/dashboard/providers")[1], {"items": []})
        prices = call("/dashboard/prices")[1]
        self.assertEqual(len(prices["buckets"]), 7)
        self.assertTrue(all(b["count"] == 0 for b in prices["buckets"]))
        data = call("/dashboard/data")[1]
        self.assertEqual((data["dataDistribution"], data["validityDistribution"], data["networkDistribution"]), ([], [], []))
        products = call("/products")[1]
        self.assertEqual((products["items"], products["totalItems"], products["totalPages"]), ([], 0, 0))
        latest = call("/imports/latest")[1]
        self.assertFalse(latest["hasImport"])
        self.assertEqual(latest["runs"], [])

    # ---- 02: valid file with an unlimited offer ----------------------------------------------
    def test_02_valid_file_with_unlimited_offer(self):
        write_csv("test_valid.csv", [row("tv-1", "10.00", "5"), row("tv-2", "20.50", "10"), row("tv-3", "30.00", "", cn="Italie", cc="IT")])
        s, body, _ = trigger()
        self.assertEqual(s, 200, body)
        self.assertEqual((body["status"], body["filesFound"], body["rowsRead"], body["rowsInserted"], body["rowsRejected"]), ("SUCCESS", 1, 3, 3, 0))
        self.assertEqual(psql("select sku, data_gb, is_unlimited from esim_products where sku='tv-3'"), [["tv-3", "", "t"]])
        summary = call("/dashboard/summary")[1]
        self.assertEqual((summary["totalProducts"], summary["unlimitedCount"], summary["numericDataCount"]), (3, 1, 2))
        self.assertAlmostEqual(summary["dataAvgGb"], 7.5)
        self.assertAlmostEqual(summary["priceAvg"], 20.1667, places=3)
        self.assertEqual(files(INCOMING, "test_valid"), [])
        self.assertEqual(len(files(PROCESSED, "test_valid_")), 1)
        run = psql("select status, rows_read, rows_inserted, rows_updated, rows_rejected from import_runs")
        self.assertEqual(run, [["SUCCESS", "3", "3", "0", "0"]])

    # ---- 03: re-import is idempotent -----------------------------------------------------------
    def test_03_reimport_same_file_creates_no_duplicate(self):
        write_csv("test_valid.csv", [row("tv-1", "10.00", "5"), row("tv-2", "20.50", "10"), row("tv-3", "30.00", "", cn="Italie", cc="IT")])
        s, body, _ = trigger()
        self.assertEqual((s, body["status"], body["rowsRead"], body["rowsInserted"], body["rowsUpdated"]), (200, "SUCCESS", 3, 0, 0))
        self.assertEqual(scalar("select count(*) from esim_products"), "3")
        self.assertEqual(scalar("select count(*) from providers"), "1")
        self.assertEqual(len(files(PROCESSED, "test_valid_")), 2, "a second archive copy is kept, never overwritten")

    # ---- 04: update of an existing product -----------------------------------------------
    def test_04_changed_row_is_updated_not_duplicated(self):
        write_csv("test_valid.csv", [row("tv-1", "11.11", "5"), row("tv-2", "20.50", "10"), row("tv-3", "30.00", "", cn="Italie", cc="IT")])
        s, body, _ = trigger()
        self.assertEqual((s, body["rowsInserted"], body["rowsUpdated"]), (200, 0, 1))
        self.assertEqual(scalar("select price from esim_products where sku='tv-1'"), "11.11")
        self.assertEqual(scalar("select count(*) from esim_products"), "3")

    # ---- 05: invalid rows, duplicate SKU --------------------------------------------------
    def test_05_invalid_rows_and_duplicate_sku_are_rejected_not_fatal(self):
        write_csv("test_mixed.csv", [
            row("m-ok", "9.90", "3", provider="MixProv"),
            row("m-badprice", "abc", provider="MixProv"),
            row("m-negprice", "-5", provider="MixProv"),
            row("m-nodata", "9.00", "", display="N/A", provider="MixProv"),
            row("m-usd", "9.00", "3", cur="USD", provider="MixProv"),
            row("m-badcc", "9.00", "3", cc="F", provider="MixProv"),
            row("m-badnet", "9.00", "3", net="9G", provider="MixProv"),
            row("m-badtop", "9.00", "3", top="peut-etre", provider="MixProv"),
            row("m-baddays", "9.00", "3", validity="0", provider="MixProv"),
            row("m-dup", "9.00", "3", provider="MixProv"),
            row("m-dup", "19.00", "3", provider="MixProv"),
            row("m-unl", "40.00", "", provider="MixProv"),
        ])
        s, body, _ = trigger()
        self.assertEqual(s, 200, body)
        f = body["files"][0]
        self.assertEqual((f["status"], f["rowsRead"], f["rowsInserted"], f["rowsRejected"]), ("PARTIAL", 12, 3, 9))
        codes = sorted(r[0] for r in psql("select error_code from import_errors"))
        self.assertEqual(codes, sorted(["INVALID_PRICE", "INVALID_PRICE", "MISSING_DATA", "INVALID_CURRENCY", "INVALID_COUNTRY_CODE",
                                        "INVALID_NETWORK", "INVALID_TOP_UP", "INVALID_VALIDITY", "DUPLICATE_SKU"]))
        self.assertEqual(scalar("select price from esim_products where sku='m-dup'"), "9.00", "first occurrence wins")
        self.assertEqual(scalar("select count(*) from esim_products where provider_id=(select id from providers where name='MixProv')"), "3")
        sample = psql("select row_number, sku from import_errors where error_code='DUPLICATE_SKU'")
        self.assertEqual(sample, [["12", "m-dup"]])
        rejected_csv = files(REJECTED, "rejected_rows_test_mixed_")
        self.assertEqual(len(rejected_csv), 1, "rejected rows are written to a CSV, nothing is lost silently")
        content = (REJECTED / rejected_csv[0]).read_text(encoding="utf-8")
        self.assertIn("row_number,sku,error_code,error_message", content)
        self.assertEqual(len(list(csv.DictReader(io.StringIO(content)))), 9)
        self.assertEqual(len(files(PROCESSED, "test_mixed_")), 1)
        self.assertEqual(psql("select status, error_message from import_runs where source_file='test_mixed.csv'")[0][0], "PARTIAL")

    # ---- 06: file where every row is invalid ----------------------------------------------
    def test_06_file_without_any_valid_row_is_failed_and_moved_to_rejected(self):
        before = scalar("select count(*) from esim_products")
        write_csv("test_allbad.csv", [row("b-1", "xx"), row("b-2", "yy")])
        s, body, _ = trigger()
        f = body["files"][0]
        self.assertEqual((f["status"], f["rowsRejected"], f["rowsInserted"]), ("FAILED", 2, 0))
        self.assertEqual(scalar("select count(*) from esim_products"), before)
        self.assertEqual(len(files(REJECTED, "test_allbad_")), 1)
        self.assertEqual(files(INCOMING, "test_allbad"), [])

    # ---- 07: invalid header ---------------------------------------------------------------
    def test_07_invalid_header_fails_the_whole_file_without_touching_catalogue(self):
        before = scalar("select count(*) from esim_products")
        write_csv("test_badheader.csv", ["x1,P,n,FR,France,5,5 Go,7,10,EUR,4G,oui"], header="sku,provider,name,country_code")
        s, body, _ = trigger()
        f = body["files"][0]
        self.assertEqual(f["status"], "FAILED")
        self.assertIn("Missing required columns", f["errorMessage"])
        self.assertNotIn(str(ROOT), json.dumps(body), "no local path leaks through the API")
        self.assertEqual(scalar("select count(*) from esim_products"), before)
        self.assertEqual(psql("select error_code from import_errors where source_file='test_badheader.csv'"), [["INVALID_HEADER"]])
        self.assertEqual(len(files(REJECTED, "test_badheader_")), 1)

    # ---- 08: header-only file ---------------------------------------------------------------
    def test_08_header_only_file_is_a_successful_empty_import(self):
        write_csv("test_empty.csv", [])
        s, body, _ = trigger()
        f = body["files"][0]
        self.assertEqual((f["status"], f["rowsRead"], f["rowsInserted"]), ("SUCCESS", 0, 0))

    # ---- 09: security and API behaviour ------------------------------------------------------
    def test_09_admin_endpoint_is_protected(self):
        self.assertEqual(call("/imports", "POST")[0], 401)
        self.assertEqual(call("/imports", "POST", {"X-API-Key": "wrong"})[0], 401)

    def test_10_cors_preflight_and_headers(self):
        s, _, h = call("/dashboard/summary", "OPTIONS", {"Origin": "http://localhost:5173", "Access-Control-Request-Method": "GET"})
        self.assertEqual(s, 204)
        self.assertEqual({k.lower(): v for k, v in h.items()}["access-control-allow-origin"], "http://localhost:5173")

    def test_11_query_validation_returns_400(self):
        self.assertEqual(call("/products?pageSize=500")[0], 400)
        self.assertEqual(call("/products?sort=id")[0], 400)
        self.assertEqual(call("/products?network=7G")[0], 400)
        self.assertEqual(call("/does-not-exist")[0], 404)

    # ---- 12: source directory unavailable ---------------------------------------------------------
    def test_12_missing_source_directory_returns_503_not_ready(self):
        hidden = INCOMING.with_name("incoming_hidden")
        INCOMING.rename(hidden)
        try:
            s, body, _ = trigger()
            self.assertEqual((s, body["error"]["code"]), (503, "NOT_READY"))
            self.assertNotIn(str(ROOT), json.dumps(body))
        finally:
            hidden.rename(INCOMING)
        self.assertEqual(scalar("select count(*) from import_lock"), "0", "lock released after a failed preflight")

    # ---- 13: PostgreSQL down ----------------------------------------------------------------------------
    def test_13_postgres_outage_is_reported_and_files_are_kept(self):
        write_csv("test_outage.csv", [row("o-1", "10.00", "5", provider="OutProv")])
        subprocess.run(["docker", "stop", PG_CONTAINER], check=True, capture_output=True)
        try:
            s, body, _ = trigger()
            self.assertEqual((s, body["error"]["code"]), (503, "DATABASE_UNAVAILABLE"), body)
            self.assertEqual(call("/dashboard/summary")[0], 503)
            self.assertEqual(files(INCOMING, "test_outage"), ["test_outage.csv"], "file untouched when the database is down")
        finally:
            subprocess.run(["docker", "start", PG_CONTAINER], check=True, capture_output=True)
            self.assertTrue(wait_for_db(), "PostgreSQL did not come back")
        time.sleep(3)
        s, body, _ = trigger()
        self.assertEqual((s, body["status"], body["rowsInserted"]), (200, "SUCCESS", 1), body)
        self.assertEqual(call("/dashboard/summary")[0], 200)

    # ---- 14: stale RUNNING run is closed by the next batch ----------------------------------------------
    def test_14_crashed_run_is_closed_by_next_import(self):
        psql("INSERT INTO import_runs (batch_id, source_file) VALUES (gen_random_uuid(), 'crashed.csv')")
        s, body, _ = trigger()
        self.assertEqual(s, 200)
        self.assertEqual(psql("select status from import_runs where source_file='crashed.csv'"), [["FAILED"]])

    # ---- 15: real data, concurrency, PostgreSQL vs CSV figures --------------------------------------
    def test_15_real_csv_concurrent_triggers_and_reference_comparison(self):
        reset()
        for f in REFERENCE.glob("*.csv"):
            (INCOMING / f.name).write_bytes(f.read_bytes())
        results = []

        def go():
            results.append(trigger()[0])

        threads = [threading.Thread(target=go) for _ in range(2)]
        threads[0].start()
        time.sleep(0.3)
        threads[1].start()
        for t in threads:
            t.join()
        self.assertEqual(sorted(results), [200, 409], "exactly one concurrent import must run")
        self.assertEqual(scalar("select count(*) from esim_products"), "5056")
        self.assertEqual(scalar("select count(*) from import_lock"), "0")
        check = subprocess.run([sys.executable, "-I", str(ROOT / "scripts" / "reference_stats.py"), "--compare", API],
                               capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(check.returncode, 0, check.stdout + check.stderr)

    def test_16_product_filters_match_csv_figures(self):
        rows = []
        for f in sorted(REFERENCE.glob("*.csv")):
            with f.open(encoding="utf-8", newline="") as fh:
                rows.extend(csv.DictReader(fh))
        expected_unl_airalo = sum(1 for r in rows if r["provider"] == "Airalo" and not r["data_gb"])
        s, body, _ = call("/products?provider=Airalo&unlimited=true&pageSize=5")
        self.assertEqual((s, body["totalItems"], len(body["items"])), (200, expected_unl_airalo, min(5, expected_unl_airalo)))
        self.assertTrue(all(i["isUnlimited"] and i["dataGb"] is None for i in body["items"]))
        expected_fr_5g = sum(1 for r in rows if r["country_code"] == "FR" and r["network"] == "5G" and 10 <= float(r["price"]) <= 30)
        s, body, _ = call("/products?country=FR&network=5G&minPrice=10&maxPrice=30&pageSize=100")
        self.assertEqual(body["totalItems"], expected_fr_5g)
        s, body, _ = call("/products?sort=price&direction=desc&pageSize=3")
        self.assertEqual([i["price"] for i in body["items"]], sorted((float(r["price"]) for r in rows), reverse=True)[:3])
        s, p1, _ = call("/products?pageSize=100&page=1")
        s, p2, _ = call("/products?pageSize=100&page=2")
        self.assertEqual((p1["totalPages"], p1["totalItems"]), (51, 5056))
        self.assertFalse({i["sku"] for i in p1["items"]} & {i["sku"] for i in p2["items"]}, "pages never overlap")
        s, body, _ = call("/products?page=999")
        self.assertEqual((s, body["items"], body["totalItems"]), (200, [], 5056))
        # no database identifier and no local path in the payload
        self.assertNotIn("id", p1["items"][0])
        self.assertNotIn(str(ROOT), json.dumps(p1))

    def test_17_sql_injection_attempts_are_inert(self):
        for q in ("'; DROP TABLE esim_products; --", "%", "_", "\\"):
            s, body, _ = call("/products?" + urllib.parse.urlencode({"q": q, "provider": q}))
            self.assertEqual(s, 200, q)
        self.assertEqual(scalar("select count(*) from esim_products"), "5056")
        # LIKE wildcards are escaped: "%" is searched literally and matches nothing
        self.assertEqual(call("/products?q=%25")[1]["totalItems"], 0)

    def test_18_latest_import_endpoint(self):
        s, body, _ = call("/imports/latest")
        self.assertTrue(body["hasImport"])
        self.assertEqual(body["status"], "SUCCESS")
        self.assertEqual((body["filesCount"], body["rowsRead"], body["rowsInserted"]), (18, 5056, 5056))
        self.assertTrue(body["startedAt"].endswith("Z"))
        self.assertNotIn(str(ROOT), json.dumps(body))


if __name__ == "__main__":
    unittest.main(verbosity=2)
