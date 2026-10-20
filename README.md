# MyBestSim Data Platform

Plateforme d'intégration de données eSIM : des CSV fournisseurs sont importés **par MuleSoft** dans **PostgreSQL**, exposés par une **API REST** et affichés dans un **dashboard React**.

```
data/incoming/*.csv ──► Mule (scheduler / POST /imports) ──► PostgreSQL ──► Mule API (RAML/APIKit) ──► Dashboard React
   (jamais copiés ailleurs)  validate · upsert · trace         structure seule au départ     /api/v1/...        (consomme uniquement l'API)
```

Séparation stricte : **structure SQL** (`database/migrations`) · **CSV sources** (`data/`) · **flows d'import** (`mule/`) · **API** (`mule/`) · **dashboard** (`dashboard/`). Aucune ligne de CSV n'est copiée dans un script SQL, un seed, un JSON du frontend ou une config. La base créée par les migrations est **vide**.

## Rôle des dossiers

| Dossier | Rôle |
|---|---|
| `database/migrations` | Migrations Flyway (`V1`…`V4`) : tables, clés, contraintes, index. Aucune donnée métier. |
| `database/queries` | Requêtes SQL utilitaires (vérification de l'état initial). |
| `mule/mybestsim-integration-api-test` | Application Mule 4 (Community) : flows d'import, API APIkit, DataWeave, MUnit. |
| `mule/Dockerfile` | Image Mule CE (4.7.0 par défaut, `--build-arg MULE_VERSION=…`) + application. |
| `dashboard` | React + TypeScript + Vite + Recharts. |
| `config` | `application.example.yaml` : référence de toutes les propriétés. |
| `data/incoming · processed · rejected` | Répertoires locaux de CSV (exclus de Git). `data/reference` = copie intacte des sources pour les tests. |
| `scripts` | Lancement local, tests d'intégration/schéma, statistiques de référence indépendantes. |
| `docs` | `architecture.md`, `api.md`, `data-flow.md`, `deployment.md`. |

## Prérequis

Docker (PostgreSQL + Flyway), Java 17, Maven 3.9, Node 20+, Python 3.10+ (scripts de test). Versions utilisées pendant le développement : Java 17.0.19, Maven 3.9.12, Docker 29.6, Node 24, Mule Runtime CE **4.7.0** (version du projet Studio ; 4.9.0 aussi validé), PostgreSQL 16 (conteneur).
Mule Runtime n'a pas besoin d'être installé : `scripts/run-mule.ps1` le télécharge dans `.tools/`.

## Démarrage pas à pas

```bash
cp .env.example .env                       # puis changer les mots de passe
```

### 1. PostgreSQL vide + migrations
```bash
docker compose up -d postgres              # volume persistant + healthcheck, port hôte 5433
docker compose run --rm migrate                     # applique database/migrations (Flyway)
```

### 2. Vérifier que les tables métier sont vides
```bash
docker exec -i mybestsim-postgres psql -U mybestsim -d mybestsim < database/queries/00_verify_initial_state.sql
# providers / esim_products / import_runs / import_errors = 0 et is_empty = t
```
(`import_lock` est une table technique, vide hors import.) Rien n'est importé par Docker ni par les migrations.

### 3. Placer les CSV et configurer leur chemin
Les CSV sources vont dans `data/incoming/`. Le chemin vient de `mybestsim.source.directory` (voir [Configuration](#configuration)), jamais du code XML.

### 4. Lancer Mule
```powershell
powershell -ExecutionPolicy Bypass -File scripts/run-mule.ps1 -Build     # Windows (télécharge Mule CE 4.7.0 au besoin ; `-MuleVersion 4.9.0` pour une autre version)
```
ou, tout en conteneurs (PostgreSQL + migrations + Mule + dashboard, jar compilé dans l'image) : `docker compose up -d --build` → API http://localhost:8081, dashboard http://localhost:5173.
Au démarrage **aucun import n'est lancé** : l'API répond avec une base vide (`hasData:false`).

### 5. Déclencher l'import
- manuel, protégé : `curl -X POST -H "X-API-Key: <MYBESTSIM_ADMIN_API_KEY>" http://localhost:8081/api/v1/imports` (ou `scripts/import-and-report.sh`) ;
- automatique : `MYBESTSIM_SCHEDULER_ENABLED=true` + `MYBESTSIM_SCHEDULER_FREQUENCY_MS`.

### 6. Dashboard
```bash
cd dashboard && cp .env.example .env.local && npm install && npm run dev      # http://localhost:5173
```
`VITE_API_BASE_URL` (build-time) désigne l'API. La variable `MYBESTSIM_CORS_ALLOWED_ORIGIN` de Mule doit être l'origine du dashboard.

## Endpoints (`/api/v1`, contrat RAML : `mule/.../resources/api/mybestsim-api.raml`)

| Méthode | Chemin | Rôle |
|---|---|---|
| GET | `/dashboard/summary` | KPI globaux (total, > 100 €, min/max/moyenne prix, moyenne data, illimités…) |
| GET | `/dashboard/providers` | produits et prix par fournisseur |
| GET | `/dashboard/prices` | distribution des prix (7 tranches) |
| GET | `/dashboard/data` | répartition data / validité / réseau |
| GET | `/products` | catalogue : filtres, tri, pagination serveur |
| GET | `/imports/latest` | état du dernier import (par fichier) |
| POST | `/imports` | déclenche un import (en-tête `X-API-Key`) |
| GET | `/health` | sonde de vie (hors `/api/v1`) |

Détails, règles de calcul et exemples : [docs/api.md](docs/api.md).

## Configuration

Config Mule : `src/main/resources/config/{dev,prod}.yaml`, choisie par `-Dmule.env` (`dev` par défaut). Les valeurs viennent de variables d'environnement (secrets inclus) ; référence : [config/application.example.yaml](config/application.example.yaml) et [config/README.md](config/README.md).

| Variable | Rôle |
|---|---|
| `MYBESTSIM_SOURCE_DIR` → `mybestsim.source.directory` | répertoire des CSV à importer |
| `MYBESTSIM_PROCESSED_DIR` / `MYBESTSIM_REJECTED_DIR` | archivage des fichiers traités / en échec |
| `MYBESTSIM_SCHEDULER_ENABLED` / `_FREQUENCY_MS` | scheduler (désactivé par défaut) |
| `MYBESTSIM_DB_HOST/PORT/NAME/USER/PASSWORD/SSLMODE` | connexion PostgreSQL |
| `MYBESTSIM_ADMIN_API_KEY` | secret de `POST /imports` (si vide, l'opération est refusée) |
| `MYBESTSIM_CORS_ALLOWED_ORIGIN` | origine autorisée du dashboard |
| `MYBESTSIM_API_BASE_URL`, `MYBESTSIM_HTTP_PORT` | URL publique et port de l'API |
| `VITE_API_BASE_URL` | URL de l'API côté dashboard |
| `POSTGRES_*` | conteneur PostgreSQL (docker-compose) |

**Changer le chemin des CSV** : modifier `MYBESTSIM_SOURCE_DIR` (`.env` ou variable de la plateforme) et redémarrer Mule — aucun code à toucher. Le chemin est lu **par la machine qui exécute Mule** : si Mule tourne ailleurs que les CSV, monter un volume/partage (Docker `-v`, NFS/SMB, volume persistant du PaaS) ou déposer les fichiers sur la machine Mule (voir [docs/deployment.md](docs/deployment.md)).

## Tests

```bash
# Schéma (base jetable) — 7 tests
python -I scripts/tests/schema_test.py -v
# MUnit (Mule CE 4.7.0) — 16 tests, lancés par Maven
(cd mule/mybestsim-integration-api-test && mvn test)
# Intégration bout en bout : Mule + PostgreSQL démarrés — 18 tests (DESTRUCTIF pour la base de dev)
ALLOW_DESTRUCTIVE_TESTS=1 python -I scripts/tests/integration_test.py -v
# Dashboard
(cd dashboard && npm test && npm run build)
# Comparaison PostgreSQL (via l'API) ↔ 18 CSV
python -I scripts/reference_stats.py --compare http://localhost:8081/api/v1
```
Résultats d'exécution et chiffres de référence : [docs/data-flow.md](docs/data-flow.md#résultats-de-validation).

## Déploiement

Serveur distant : mybestsim.duckdns.org
