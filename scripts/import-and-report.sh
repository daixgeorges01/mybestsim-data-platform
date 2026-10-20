#!/usr/bin/env bash
# Triggers POST /imports and prints a compact report.
B="${API_BASE_URL:-http://localhost:8081/api/v1}"; KEY="${MYBESTSIM_ADMIN_API_KEY:-dev-only-change-me}"
curl -s -m 300 -w "\n[HTTP %{http_code}]\n" -X POST -H "X-API-Key: $KEY" "$B/imports" | python -I -c "
import sys,json
t=sys.stdin.read(); body,code=t.rsplit('\n[HTTP',1)
print('HTTP',code.strip(' ]\n'))
d=json.loads(body)
if 'files' not in d: print(d); sys.exit()
print({k:v for k,v in d.items() if k!='files'})
for f in d['files']: print(' ',f['sourceFile'],f['status'],'read',f['rowsRead'],'ins',f['rowsInserted'],'upd',f['rowsUpdated'],'rej',f['rowsRejected'],f.get('errorMessage') or '')
"
