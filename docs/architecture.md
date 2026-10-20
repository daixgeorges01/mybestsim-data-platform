# Architecture

## Composants

| Couche | Technologie | Responsabilité |
|---|---|---|
| Sources | 18 CSV (un par fournisseur) dans `data/incoming/` | lues uniquement par Mule |
| Intégration | Mule Runtime **Community 4.7.0** (projet Studio `mybestsim-integration-api-test`), DataWeave, connecteurs HTTP 1.9.3 / Sockets 1.2.4 / File 1.5.2 / Database 1.14.10 / APIkit 1.10.4, MUnit 3.2.1 | import idempotent + API REST |
| Stockage | PostgreSQL 16 (migrations Flyway) | catalogue + traçabilité des imports |
| Présentation | React 18, TypeScript, Vite, Recharts | consomme **uniquement** l'API |

Le frontend n'accède ni au système de fichiers ni à PostgreSQL ; l'API n'expose ni identifiants de base ni chemins locaux (les `source_file` sont des noms de fichier, les messages d'erreur stockés sont génériques, les détails vont dans le log Mule).

## Application Mule (`mybestsim-integration-api`)

| Fichier | Contenu |
|---|---|
| `global.xml` | propriétés par environnement, listener HTTP, APIkit, pool PostgreSQL, connecteurs File |
| `api.xml` | `mybestsim-api-main` (listener `/api/v1/*`, CORS, router APIkit, gestion d'erreurs unifiée), `/health` |
| `dashboard.xml` | flows APIkit de consultation (SQL d'agrégation → JSON) |
| `import.xml` | `scheduled-import-flow`, `run-import-batch-flow`, `process-provider-file-flow`, `load-products-flow`, verrou, archivage |
| `dw/*.dwl` | modules DataWeave : `RowValidator` (validation), `Responses` (mapping), `ProductQuery` (filtres/tri whitelist) |

**Contrainte réelle Mule Community** : le composant `ee:transform` (Transform Message) n'existe que dans l'édition Enterprise (le runtime CE refuse le namespace `ee`). Toute la logique DataWeave est donc écrite en **modules `.dwl`** importés dans des expressions `#[ … ]` (`set-payload`/`set-variable`), ce qui fonctionne en CE et reste testable avec MUnit. Autres points vérifiés à l'exécution : `requiredProduct: MULE` dans `mule-artifact.json`, versions de connecteurs et de MUnit compatibles avec le runtime visé (les versions récentes déclarent Java 25 et ne se chargent pas sur 4.9.0 ; pour 4.7.0 : MUnit 3.2.1, Database 1.14.10 ; pour 4.9.0 : MUnit 3.4.0, Database 1.14.17, HTTP 1.10.6). `javaSpecificationVersions` = 1.8, 11, 17.

## Décisions

- **Idempotence** : `INSERT … ON CONFLICT (provider_id, sku) DO UPDATE … WHERE (colonnes) IS DISTINCT FROM (nouvelles valeurs)` ; une ligne inchangée n'est ni réécrite ni comptée.
- **Une requête SQL paramétrée par fichier** : le lot valide est passé en un paramètre JSON (`jsonb_to_recordset`) — pas de concaténation SQL, une seule instruction atomique (providers + produits), compteurs `inserted/updated` via `xmax = 0`.
- **Transaction** : `load-products-flow` = upsert + insertion des rejets + clôture du run dans une transaction locale (`ALWAYS_BEGIN`) ; l'échec annule tout et le run est marqué `FAILED` hors transaction (traçabilité).
- **Ligne invalide ≠ catalogue en échec** : les lignes invalides sont rejetées individuellement (`import_errors` + CSV `rejected_rows_*` dans `data/rejected`), les valides sont chargées → statut `PARTIAL`.
- **Concurrence** : verrou en base (`import_lock`, une seule ligne, expiration configurable) → fonctionne aussi avec plusieurs instances ; index unique partiel « un seul run RUNNING » ; `disallowConcurrentExecution` sur le scheduler ; un run resté `RUNNING` après un crash est clos au prochain import.
- **Pas de suppression automatique** de produits absents d'un nouveau CSV (aucune règle métier définie) ; fichiers jamais supprimés, seulement déplacés.
- **Devise** : seules les devises listées dans `mybestsim.import.allowed-currencies` (EUR) sont acceptées, pour que prix moyen/min/max restent comparables.
- **Sécurité** : `POST /imports` exige `X-API-Key` (secret par variable d'environnement, refus si non configuré) ; lectures publiques (dashboard public) ; CORS limité à l'origine du dashboard ; SQL paramétré, `ORDER BY` issu d'une liste blanche, jokers `LIKE` échappés ; messages d'erreur génériques.

## Résilience PostgreSQL
Connexion paramétrée avec `connectTimeout`/`loginTimeout`/`socketTimeout`, reconnexion bornée (2×2 s) et `c3p0.properties` (2 tentatives) : une base arrêtée renvoie **503 `DATABASE_UNAVAILABLE` en < 1 s** (au lieu de ~96 s avec les valeurs par défaut du pool), les fichiers restent dans `incoming`, et l'API se rétablit seule au redémarrage de la base.
