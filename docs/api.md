# API REST

Contrat formel : `mule/mybestsim-integration-api-test/src/main/resources/api/mybestsim-api.raml` (RAML 1.0, routé par APIkit : les requêtes invalides reçoivent un 400 avant tout accès SQL). Base : `/api/v1`. JSON partout.

## Règles de calcul (toutes sur PostgreSQL)

| Indicateur | Règle |
|---|---|
| `totalProducts` | nombre de lignes de `esim_products` |
| `productsOver100` | `price > 100` (strict) |
| `priceMin` / `priceMax` | min / max de `price` |
| `priceAvg` | moyenne arithmétique de **tous** les produits (illimités inclus), arrondie à 4 décimales |
| `dataAvgGb` | moyenne de `data_gb` sur les offres **chiffrées uniquement** (les illimités ont `data_gb NULL` et sont comptés à part), 4 décimales |
| `unlimitedCount` | `is_unlimited = true` |
| tranches de prix | `(min, max]` : 0–10, 10–20, 20–30, 30–50, 50–75, 75–100, > 100 (les tranches vides sont renvoyées avec 0) |

Base vide : tous les compteurs valent 0, `priceMin/Max/Avg` et `dataAvgGb` valent `null`, `hasData:false`, listes vides — la réponse garde le même schéma.

## Endpoints

### GET `/dashboard/summary`
```json
{"hasData":true,"totalProducts":5056,"productsOver100":56,"priceMin":5.36,"priceMax":154.63,"priceAvg":29.3013,
 "dataAvgGb":14.4915,"numericDataCount":4403,"unlimitedCount":653,"providerCount":18,"countryCount":54,"currency":"EUR"}
```
### GET `/dashboard/providers` → `{"items":[{"provider","productCount","sharePercent","priceAvg","priceMin","priceMax","unlimitedCount"}]}` (tri : volume décroissant)
### GET `/dashboard/prices` → `{"currency":"EUR","buckets":[{"label":"0 – 10 €","min":0,"max":10,"count":891}, …]}`
### GET `/dashboard/data` → `{"dataDistribution":[{"label","dataGb","isUnlimited","count"}],"validityDistribution":[…],"networkDistribution":[…]}`
### GET `/products`
Paramètres : `page` (≥1), `pageSize` (1–100, défaut 25), `provider`, `country`, `network` (2G–5G), `unlimited`, `topUp`, `minPrice`, `maxPrice`, `q` (produit, SKU, pays), `sort` (`price|dataGb|validityDays|productName|provider|country`), `direction`. Réponse : `{"items":[Product],"page","pageSize","totalItems","totalPages"}`. Un `Product` ne contient aucun identifiant interne.
### GET `/imports/latest`
Dernier **lot** (un déclenchement) : statut agrégé (`SUCCESS|PARTIAL|FAILED|RUNNING`), totaux, et `runs[]` par fichier. Sans import : `hasImport:false`, `runs:[]`.
### POST `/imports` *(protégé)*
En-tête `X-API-Key`. Importe de façon **synchrone** tous les CSV du répertoire source. 200 `{batchId,status,filesFound,rowsRead,rowsInserted,rowsUpdated,rowsRejected,files[]}` (`status` = `NO_FILES` s'il n'y avait rien à traiter) · 401 clé absente/invalide · 409 import déjà en cours · 503 base/migrations/répertoire source indisponibles.

## Erreurs
`{"error":{"code":"BAD_REQUEST|NOT_FOUND|UNAUTHORIZED|IMPORT_ALREADY_RUNNING|NOT_READY|DATABASE_UNAVAILABLE|INTERNAL_ERROR","message":"…"}}` — jamais de trace SQL ni de chemin.
