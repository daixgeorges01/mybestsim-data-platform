#!/usr/bin/env bash
# DEV ONLY: empties the catalogue tables and puts the pristine CSV copies back in data/incoming.
# (Technical Flyway history is kept; the schema is untouched.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker exec mybestsim-postgres psql -q -U "${POSTGRES_USER:-mybestsim}" -d "${POSTGRES_DB:-mybestsim}" -c \
  "TRUNCATE import_errors, import_runs, esim_products, providers, import_lock RESTART IDENTITY CASCADE"
find "$ROOT/data/incoming" "$ROOT/data/processed" "$ROOT/data/rejected" -type f ! -name .gitkeep -delete
cp "$ROOT"/data/reference/*.csv "$ROOT/data/incoming/"
echo "reset done: $(ls "$ROOT/data/incoming" | grep -c csv) CSV in data/incoming, tables empty"
