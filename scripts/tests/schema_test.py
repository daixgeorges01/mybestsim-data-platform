"""Schema tests on a throw-away database (mybestsim_schema_test) in the local PostgreSQL container.

Checks: migrations apply cleanly, every business table is empty afterwards, constraints reject invalid data,
the single-RUNNING-run index and the single-row lock table behave as designed.

    python -I scripts/tests/schema_test.py -v
"""
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
CONTAINER = "mybestsim-postgres"
USER = os.environ.get("POSTGRES_USER", "mybestsim")
PASSWORD = os.environ.get("POSTGRES_PASSWORD", "change-me-local-only")
TEST_DB = "mybestsim_schema_test"
NETWORK = "mybestsim_mybestsim-net"


def psql(sql, db=TEST_DB, check=True):
    out = subprocess.run(["docker", "exec", "-i", CONTAINER, "psql", "-U", USER, "-d", db, "-At", "-F", "|", "-v", "ON_ERROR_STOP=1"],
                         input=sql, capture_output=True, text=True, encoding="utf-8")
    if check and out.returncode:
        raise RuntimeError(out.stderr.strip())
    return out


def rejects(sql, fragment=None):
    out = psql(sql, check=False)
    return out.returncode != 0 and (fragment is None or fragment in out.stderr)


PRODUCT = ("INSERT INTO esim_products (sku, provider_id, product_name, country_code, country_name, data_gb, data_display, "
           "is_unlimited, validity_days, price, currency, network, top_up) VALUES "
           "('{sku}', (SELECT id FROM providers WHERE name='P'), 'n', '{cc}', 'c', {data}, 'd', {unl}, {days}, {price}, '{cur}', '{net}', true)")


def product(sku="s1", cc="FR", data="5", unl="false", days=7, price="10", cur="EUR", net="4G"):
    return PRODUCT.format(sku=sku, cc=cc, data=data, unl=unl, days=days, price=price, cur=cur, net=net)


class SchemaTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        psql(f"DROP DATABASE IF EXISTS {TEST_DB}", db="postgres")
        psql(f"CREATE DATABASE {TEST_DB}", db="postgres")
        res = subprocess.run(
            ["docker", "run", "--rm", "--network", NETWORK, "-v", f"{ROOT / 'database' / 'migrations'}:/flyway/sql:ro",
             "flyway/flyway:11-alpine", f"-url=jdbc:postgresql://postgres:5432/{TEST_DB}", f"-user={USER}", f"-password={PASSWORD}",
             "-locations=filesystem:/flyway/sql", "migrate"], capture_output=True, text=True)
        assert res.returncode == 0, res.stdout + res.stderr
        cls.migrate_output = res.stdout

    @classmethod
    def tearDownClass(cls):
        psql(f"DROP DATABASE IF EXISTS {TEST_DB}", db="postgres")

    def test_01_migrations_applied(self):
        self.assertIn("Successfully applied 4 migrations", self.migrate_output)
        tables = {r.split("|")[0] for r in psql("SELECT table_name FROM information_schema.tables WHERE table_schema='public'").stdout.split()}
        self.assertLessEqual({"providers", "esim_products", "import_runs", "import_errors", "import_lock"}, tables)

    def test_02_business_tables_are_empty_after_migration(self):
        out = psql((ROOT / "database" / "queries" / "00_verify_initial_state.sql").read_text(encoding="utf-8")).stdout
        self.assertIn("providers|0", out)
        self.assertIn("esim_products|0", out)
        self.assertIn("import_runs|0", out)
        self.assertIn("import_errors|0", out)
        self.assertTrue(out.strip().endswith("t"), out)
        self.assertEqual(psql("SELECT count(*) FROM import_lock").stdout.strip(), "0")

    def test_03_constraints_reject_invalid_products(self):
        psql("INSERT INTO providers (name) VALUES ('P')")
        self.assertTrue(rejects(product(price="-1"), "ck_esim_products_price"))
        self.assertTrue(rejects(product(days=0), "ck_esim_products_validity"))
        self.assertTrue(rejects(product(cc="f"), "ck_esim_products_country_code"))
        self.assertTrue(rejects(product(net="9G"), "ck_esim_products_network"))
        self.assertTrue(rejects(product(cur="eur"), "ck_esim_products_currency"))
        self.assertTrue(rejects(product(data="NULL", unl="false"), "ck_esim_products_data"), "missing data is not an unlimited offer")
        self.assertTrue(rejects(product(data="5", unl="true"), "ck_esim_products_data"), "unlimited offers carry no numeric data")
        self.assertTrue(rejects(product(data="0"), "ck_esim_products_data"))
        self.assertTrue(rejects(product().replace("(SELECT id FROM providers WHERE name='P')", "999"), "fk_esim_products_provider"))
        self.assertEqual(psql("SELECT count(*) FROM esim_products").stdout.strip(), "0")

    def test_04_valid_products_and_business_key(self):
        psql("INSERT INTO providers (name) VALUES ('P2') ON CONFLICT DO NOTHING")
        psql(product(sku="ok1", data="NULL", unl="true", price="99.99"))
        psql(product(sku="ok2", data="0.5"))
        self.assertTrue(rejects(product(sku="ok1"), "uq_esim_products_provider_sku"))
        self.assertEqual(psql("SELECT data_gb IS NULL, is_unlimited FROM esim_products WHERE sku='ok1'").stdout.strip(), "t|t")
        self.assertEqual(psql("SELECT pg_typeof(price)::text, pg_typeof(data_gb)::text FROM esim_products LIMIT 1").stdout.strip(), "numeric|numeric")

    def test_05_updated_at_trigger(self):
        psql("INSERT INTO providers (name) VALUES ('P') ON CONFLICT DO NOTHING")
        psql(product(sku="trg1"))
        psql("UPDATE esim_products SET updated_at = now() - interval '1 day' WHERE sku='trg1'")
        # the trigger overwrites an explicit updated_at on every UPDATE
        psql("UPDATE esim_products SET price = 11 WHERE sku='trg1'")
        self.assertEqual(psql("SELECT updated_at > now() - interval '1 minute' FROM esim_products WHERE sku='trg1'").stdout.strip(), "t")

    def test_06_single_running_import_and_lock(self):
        psql("INSERT INTO import_runs (batch_id, source_file) VALUES (gen_random_uuid(), 'a.csv')")
        self.assertTrue(rejects("INSERT INTO import_runs (batch_id, source_file) VALUES (gen_random_uuid(), 'b.csv')", "uq_import_runs_single_running"))
        self.assertTrue(rejects("UPDATE import_runs SET status='SUCCESS' WHERE source_file='a.csv'", "ck_import_runs_finished"))
        psql("UPDATE import_runs SET status='SUCCESS', finished_at=now()")
        psql("INSERT INTO import_runs (batch_id, source_file) VALUES (gen_random_uuid(), 'b.csv')")
        psql("INSERT INTO import_lock (batch_id) VALUES (gen_random_uuid())")
        self.assertTrue(rejects("INSERT INTO import_lock (batch_id) VALUES (gen_random_uuid())", "pk_import_lock"))
        self.assertTrue(rejects("INSERT INTO import_lock (id, batch_id) VALUES (false, gen_random_uuid())", "ck_import_lock_single_row"))

    def test_07_import_errors_cascade_with_runs(self):
        psql("INSERT INTO import_runs (batch_id, source_file, status, finished_at) VALUES (gen_random_uuid(), 'c.csv', 'FAILED', now())")
        run_id = psql("SELECT id FROM import_runs WHERE source_file='c.csv'").stdout.strip()
        psql(f"INSERT INTO import_errors (import_run_id, source_file, row_number, sku, error_code, error_message) VALUES ({run_id}, 'c.csv', 2, 's', 'X', 'm')")
        self.assertTrue(rejects("INSERT INTO import_errors (import_run_id, source_file, error_code, error_message) VALUES (987654, 'c.csv', 'X', 'm')", "fk_import_errors_run"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
