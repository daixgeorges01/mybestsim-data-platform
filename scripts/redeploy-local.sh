#!/usr/bin/env bash
# Rebuilds the Mule app and (re)starts the local Mule Community runtime (.tools/) in the background.
#   MULE_VERSION=4.7.0 (default) | 4.9.0 | ...   -> .tools/mule-standalone-<version>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MULE_VERSION="${MULE_VERSION:-4.7.0}"
PROJECT="$ROOT/mule/mybestsim-integration-api-test"
MULE_HOME_DIR="$ROOT/.tools/mule-standalone-$MULE_VERSION"
if [ ! -d "$MULE_HOME_DIR" ]; then
  mkdir -p "$ROOT/.tools"
  curl -fsSL -o "$ROOT/.tools/mule-$MULE_VERSION.zip" "https://repository.mulesoft.org/releases/org/mule/distributions/mule-standalone/$MULE_VERSION/mule-standalone-$MULE_VERSION.zip"
  unzip -q "$ROOT/.tools/mule-$MULE_VERSION.zip" -d "$ROOT/.tools"
fi
# Mule 4.7.x on Windows: quote the launcher module path (install path contains spaces)
if [[ "$MULE_VERSION" == 4.7.* ]]; then python "$ROOT/scripts/patch_mule47_launcher.py" "$MULE_HOME_DIR"; fi
(cd "$PROJECT" && mvn -q -B -DskipTests package)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/stop-mule.ps1" || true
sleep 5
APPS="$MULE_HOME_DIR/apps"
rm -rf "$APPS"/mybestsim-integration-api* 2>/dev/null || true
cp "$PROJECT"/target/mybestsim-integration-api-test-*-mule-application.jar "$APPS/mybestsim-integration-api.jar"
set -a; . "$ROOT/.env"; set +a
export MYBESTSIM_SOURCE_DIR="$ROOT/data/incoming" MYBESTSIM_PROCESSED_DIR="$ROOT/data/processed" MYBESTSIM_REJECTED_DIR="$ROOT/data/rejected"
nohup "$MULE_HOME_DIR/bin/mule.bat" -M-Dmule.env=dev "${@}" > "$ROOT/.tools/mule-console.log" 2>&1 &
for i in $(seq 1 60); do
  if [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' localhost:8081/api/v1/dashboard/summary)" != "000" ] && \
     [ "$(curl -s -m 2 -o /dev/null -w '%{http_code}' localhost:8081/api/v1/dashboard/summary)" != "503" ]; then echo "mule $MULE_VERSION up"; exit 0; fi
  sleep 3
done
echo "app did not come up; see .tools/mule-console.log and $MULE_HOME_DIR/logs/mule.log" >&2; exit 1
