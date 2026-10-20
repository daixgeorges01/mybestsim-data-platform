# Flux de données et validation

## Inspection des sources (phase 1)

- Sources : `donnees-test-mybestsim.zip` (18 CSV) et le PDF du test (Partie 1 : dashboard en ligne avec total, > 100 €, fourchette de prix, data moyenne par carte, prix moyen, répartition par fournisseur, + statistiques bonus).
- 18 fichiers, **5 056 lignes**, UTF-8 sans BOM, séparateur `,`, en-tête identique : `sku,provider,product_name,country_code,country_name,data_gb,data_display,validity_days,price,currency,network,top_up`.
- 5 056 SKU distincts (aucun doublon, ni intra-fichier ni inter-fichiers) ; 18 fournisseurs ; 54 codes pays (dont des régions : `EU`, `AS`, `NA`, `WW`) ; devise unique EUR ; réseaux 4G/5G ; validité 7/15/30 jours ; `top_up` = `oui`/`non`.
- **653 offres illimitées** : `data_gb` vide **et** `data_display = "Illimité"`. Aucune autre valeur vide dans les 12 colonnes.
- Choix assumé : « data moyenne par carte » = moyenne sur les 4 403 offres chiffrées (les illimitées n'ont pas de volume) ; elles sont comptées à part.

## Parcours d'un import

1. **Déclenchement** : `scheduled-import-flow` (si activé) ou `POST /imports` → `run-import-batch-flow`.
2. **Préconditions** (`import-preflight-flow`) : les 5 tables existent, version Flyway ≥ `required-schema-version`, répertoire source lisible — sinon `MYBESTSIM:NOT_READY` (503 / log WARN pour le scheduler, aucun fichier touché).
3. **Verrou** (`import_lock`) ; si déjà pris → `IMPORT_ALREADY_RUNNING` (409). Les runs `RUNNING` orphelins sont clos `FAILED`.
4. Pour chaque `*.csv` (ordre alphabétique) → `process-provider-file-flow` :
   1. création d'un `import_runs` (`RUNNING`) ;
   2. lecture (`file:read`, UTF-8) et validation DataWeave (`RowValidator`) ;
   3. en-tête incomplet → fichier `FAILED` (`INVALID_HEADER`) ;
   4. `load-products-flow` (transaction) : upsert des lignes valides, insertion des rejets, clôture du run (compteurs, statut) ;
   5. archivage (`archive-file-flow`).
5. Libération du verrou ; réponse agrégée.

## Règles de validation (par ligne)

| Code | Règle |
|---|---|
| `INVALID_SKU` | non vide, ≤ 100 car., `[A-Za-z0-9._-]` |
| `INVALID_PROVIDER` / `INVALID_PRODUCT_NAME` / `INVALID_COUNTRY_NAME` / `INVALID_DATA_DISPLAY` | non vides, longueurs max |
| `INVALID_COUNTRY_CODE` | 2–3 lettres majuscules |
| `MISSING_DATA` | `data_gb` vide **sans** libellé illimité (`illimité`, `unlimited`) |
| `INVALID_DATA` / `INCONSISTENT_DATA` | décimal > 0 (≤ 2 décimales) ; valeur numérique + libellé illimité = incohérent |
| `INVALID_VALIDITY` | entier > 0 |
| `INVALID_PRICE` | décimal ≥ 0, ≤ 2 décimales |
| `INVALID_CURRENCY` | dans `allowed-currencies` |
| `INVALID_NETWORK` | 2G/3G/4G/5G |
| `INVALID_TOP_UP` | oui/non (yes/no/true/false/1/0) |
| `DUPLICATE_SKU` | même `(provider, sku)` déjà vu **dans le fichier** : la 1ʳᵉ occurrence est conservée |

Entre fichiers, la même clé métier est un **upsert** : la dernière importation fait foi.

## Stratégie de traitement des fichiers

| Résultat | Statut du run | Fichier source | Traces |
|---|---|---|---|
| aucune ligne rejetée (y compris fichier vide) | `SUCCESS` | → `processed/<nom>_<horodatage>.csv` | compteurs |
| certaines lignes rejetées | `PARTIAL` | → `processed/` | `import_errors` + `rejected/rejected_rows_<nom>_<horodatage>.csv` (raison + colonnes d'origine) |
| lignes lues, aucune valide / en-tête invalide / fichier illisible / échec SQL (rollback) | `FAILED` | → `rejected/` | `import_errors` (erreur de fichier) |
| base ou répertoire source indisponible | — | **reste dans `incoming/`** | log ; réessai au prochain déclenchement |

Aucun fichier n'est supprimé ni écrasé (horodatage à la milliseconde). Réimporter un fichier ne crée aucun doublon : `rows_inserted = rows_updated = 0` si rien n'a changé.

## Résultats de validation

Exécutés le 17/10/2026 sur la pile locale (Docker PostgreSQL 16, Mule CE 4.7.0 sous Windows ; Docker : image Mule CE 4.7.0) :

| Vérification | Résultat |
|---|---|
| `scripts/tests/schema_test.py` (migrations, tables métier vides, contraintes, verrous, trigger) | 7/7 OK |
| MUnit (`mvn test`, validation DW, flows mockés, erreurs, verrou, préconditions) | 16/16 OK |
| `scripts/tests/integration_test.py` (base vide, import valide, illimités, lignes invalides, SKU dupliqués, réimport, mise à jour, en-tête invalide, fichier vide, API protégée, CORS, 400/404, répertoire source absent, **panne PostgreSQL**, run orphelin, **imports concurrents (200 + 409)**, filtres/pagination vs CSV, injection SQL, `imports/latest`) | 18/18 OK |
| Dashboard : `npm test` (état vide, erreur API, KPI) et `npm run build` | 4/4 OK, build OK |
| Scheduler : import déclenché automatiquement (18 fichiers, `trigger_type=SCHEDULER`) | OK |
| Image Docker Mule (config `prod`, volumes) : import des 18 fichiers | OK |

**Comparaison PostgreSQL ↔ CSV** (`scripts/reference_stats.py --compare`, calcul indépendant en Python/`Decimal` sur `data/reference`) :

| Indicateur | CSV | API (PostgreSQL) |
|---|---|---|
| Produits | 5 056 | 5 056 |
| > 100 € | 56 | 56 |
| Prix min / max | 5,36 / 154,63 € | 5,36 / 154,63 € |
| Prix moyen | 29,3013 € | 29,3013 € |
| Data moyenne (4 403 offres chiffrées) | 14,4915 Go | 14,4915 Go |
| Illimités | 653 | 653 |
| Par fournisseur (18) et 7 tranches de prix | identiques | identiques |

Par fournisseur : Airalo 722, Ubigi 562, eSIMX 432, Saily 382, GigSky 342, Nomad 312, Instabridge 282, aloSIM 262, Holafly 242, Yesim 222, Jetpac 212, Truphone 202, JamboSIM 182, Flexiroam 172, Yatelo 162, Maya Mobile 152, Roamic 122, 4S eSIM 92.
