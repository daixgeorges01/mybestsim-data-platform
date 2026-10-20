# Base de données

PostgreSQL. Les migrations (Flyway, `V<n>__nom.sql`) créent **uniquement la structure** ; aucune donnée métier n'est insérée.

| Migration | Contenu |
|---|---|
| `V1__create_catalog_tables.sql` | `providers`, `esim_products` (clés, contraintes, index) |
| `V2__create_import_tracking.sql` | `import_runs`, `import_errors`, lien `esim_products.last_import_run_id` |
| `V3__add_updated_at_trigger.sql` | `updated_at` mis à jour à chaque UPDATE réel |
| `V4__create_import_lock.sql` | table **technique** `import_lock` (verrou d'import, vide hors import) |

## Appliquer / vérifier
```bash
docker compose up -d postgres
docker compose run --rm migrate
docker exec -i mybestsim-postgres psql -U mybestsim -d mybestsim < database/queries/00_verify_initial_state.sql
```
Sans Docker : `flyway -url=jdbc:postgresql://HOST:5432/DB -user=… -password=… -locations=filesystem:database/migrations migrate`.

## Modèle (adapté aux 18 CSV)

- **Clé métier** : `UNIQUE (provider_id, sku)` (les SKU des sources sont uniques globalement — 5 056 SKU distincts —, mais l'unicité est garantie par fournisseur).
- `data_gb NUMERIC(8,2)` : `NULL` **et** `is_unlimited = TRUE` pour une offre illimitée ; `NULL` avec `is_unlimited = FALSE` est interdit (`ck_esim_products_data`) : une donnée manquante est rejetée à l'import, jamais confondue avec « illimité ».
- `price NUMERIC(10,2) ≥ 0`, `currency CHAR(3)`, `network IN (2G,3G,4G,5G)`, `country_code ^[A-Z]{2,3}$`, `validity_days > 0`, `top_up BOOLEAN` (« oui/non » des CSV).
- `import_runs.batch_id` regroupe les fichiers d'un même déclenchement ; au plus **un** run `RUNNING` (index unique partiel). Statuts : `RUNNING | SUCCESS | PARTIAL | FAILED`.
- `import_errors` : une ligne par rejet (`row_number`, `sku`, `error_code`, `error_message`) ; `row_number` NULL pour une erreur de fichier.
- `esim_products.last_import_run_id` : dernier run ayant **créé ou modifié** la ligne (une ligne inchangée n'est pas réécrite).
