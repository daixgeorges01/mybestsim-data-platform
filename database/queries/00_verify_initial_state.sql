-- Run after the migrations: every business table must be empty.
-- Expected: all row counts = 0 and "is_empty" = true.
SELECT 'providers'     AS table_name, count(*) AS row_count FROM providers
UNION ALL SELECT 'esim_products', count(*) FROM esim_products
UNION ALL SELECT 'import_runs',   count(*) FROM import_runs
UNION ALL SELECT 'import_errors', count(*) FROM import_errors;

SELECT (SELECT count(*) FROM providers) + (SELECT count(*) FROM esim_products)
     + (SELECT count(*) FROM import_runs) + (SELECT count(*) FROM import_errors) = 0 AS is_empty;
