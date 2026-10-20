# Déploiement

> **État réel** : rien n'a été déployé (aucun accès à un compte Vercel/Netlify ni à un hébergeur de conteneurs). Les artefacts sont prêts et testés localement ; le lien public reste à créer avec vos accès.

## 1. PostgreSQL (accessible de façon sécurisée)
Instance managée (Neon, Supabase, RDS, Azure DB, Scaleway…), TLS obligatoire (`MYBESTSIM_DB_SSLMODE=require` ou `verify-full`), utilisateur applicatif dédié, accès limité aux IP/réseau de l'API.
Appliquer les migrations **avant** le premier démarrage de l'API :
```bash
docker run --rm -v "$PWD/database/migrations:/flyway/sql:ro" flyway/flyway:11-alpine \
  -url=jdbc:postgresql://HOST:5432/DB?sslmode=require -user=… -password=… migrate
```
Droits de l'utilisateur applicatif : `SELECT/INSERT/UPDATE/DELETE` sur les tables du schéma `public` (le droit `DELETE` sert au verrou et aux tests) et `SELECT` sur `flyway_schema_history`. Les tables restent vides jusqu'au premier import.

## 2. API Mule (Mule Runtime compatible)
Image : `mule/Dockerfile` (Mule CE 4.7.0 par défaut — `--build-arg MULE_VERSION=…` pour une autre version — + application, utilisateur non root, healthcheck `/health`).
```bash
(cd mule/mybestsim-integration-api-test && mvn package)
docker build -f mule/Dockerfile -t mybestsim-mule .
```
À déployer sur un hébergeur de conteneurs avec **volume persistant** (Render, Fly.io, Railway, Azure Container Apps, ECS, VM…). CloudHub est une option Enterprise (non requise ici). Variables à définir sur la plateforme (secrets pour les deux premières) :

`MYBESTSIM_DB_PASSWORD`, `MYBESTSIM_ADMIN_API_KEY`, `MYBESTSIM_DB_HOST`, `MYBESTSIM_DB_PORT`, `MYBESTSIM_DB_NAME`, `MYBESTSIM_DB_USER`, `MYBESTSIM_DB_SSLMODE`, `MYBESTSIM_CORS_ALLOWED_ORIGIN` (URL publique du dashboard), `MYBESTSIM_API_BASE_URL`, `MYBESTSIM_SCHEDULER_ENABLED`, `MYBESTSIM_SCHEDULER_FREQUENCY_MS` (les chemins `/data/...` sont déjà définis dans l'image). Exposer le port 8081 en HTTPS (proxy de la plateforme).

### Chemin des CSV en production
Le runtime lit `MYBESTSIM_SOURCE_DIR` (`/data/incoming` dans l'image) : **ce chemin doit exister dans le conteneur**. Monter un volume persistant sur `/data` et y déposer les CSV (upload plateforme, `rsync`/`scp`, tâche de synchronisation depuis un stockage objet…). Vérification : `GET /health`, puis `POST /api/v1/imports` ; une réponse 503 `NOT_READY` signale un répertoire inaccessible ou des migrations non appliquées. Si les fichiers arrivent par SFTP/S3, remplacer le `file:list`/`file:read` par les connecteurs correspondants (le reste des flows est inchangé).

## 3. Dashboard (Vercel ou Netlify)
- Racine du projet : `dashboard/` ; build `npm run build` ; sortie `dist` (`vercel.json` / `netlify.toml` fournis).
- Variable de build : `VITE_API_BASE_URL=https://<api-publique>/api/v1`.
- Puis renseigner l'URL du dashboard dans `MYBESTSIM_CORS_ALLOWED_ORIGIN` côté API et redémarrer l'API.
- Contenu mixte : l'API doit être servie en HTTPS pour un dashboard en HTTPS.

## 4. Mise en service
1. Migrations appliquées → tables vides (`database/queries/00_verify_initial_state.sql`).
2. CSV déposés dans le volume source.
3. `POST /api/v1/imports` (ou scheduler) → `GET /api/v1/imports/latest`.
4. Ouvrir le dashboard ; comparer éventuellement avec `scripts/reference_stats.py --compare <api>`.

## Local
`docker compose up -d postgres` · `docker compose up -d --build` lance tout (postgres, migrate, mule, dashboard) ; ou `docker compose up -d postgres migrate` puis `scripts/run-mule.ps1` · `npm run dev` dans `dashboard/`.
