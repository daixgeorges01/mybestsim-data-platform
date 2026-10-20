# Configuration

`application.example.yaml` documents every property (fictitious values). The live configuration is split by environment:

- `mule/mybestsim-integration-api-test/src/main/resources/config/dev.yaml`
- `mule/mybestsim-integration-api-test/src/main/resources/config/prod.yaml`

Environment selection: `-Dmule.env=dev|prod` (`dev` by default; the Docker image starts with `prod`).
Each value is a `${ENV_VAR}` placeholder resolved from the process environment, so secrets (`MYBESTSIM_DB_PASSWORD`, `MYBESTSIM_ADMIN_API_KEY`) are never stored in the repository. Locally, `scripts/run-mule.ps1` loads them from `.env` (git-ignored).

## Changing the CSV directory
1. Set `MYBESTSIM_SOURCE_DIR` (and `MYBESTSIM_PROCESSED_DIR`, `MYBESTSIM_REJECTED_DIR`) — e.g. in `.env` or the platform's variables.
2. Restart Mule. No XML or code change.

The path is resolved by the **machine running Mule**. If the CSV live elsewhere:
- Docker: bind-mount/volume them to `/data/incoming` (`-v /host/csv:/data/incoming`);
- remote machine: mount a share (NFS/SMB) or sync files (rsync, cloud storage agent) into the directory;
- a hosted runtime without a shared disk: use a persistent volume, or replace the File connector by SFTP/S3 connectors (same flows, different source operation).

Relative paths are resolved from the Mule process working directory — prefer absolute paths in production.
