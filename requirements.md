# Requirements — CKAN 2.7.2 ETL Test Instance

Source of truth for decisions: `plan.md`.

## Functional (v1)
1. One command brings up blank CKAN 2.7.2: `docker compose up -d`.
2. One command wipes everything: `docker compose down -v` (DBs, Solr index, filestore).
3. Boot auto-creates 1 admin user + 1 fixed API token, no manual clicks.
4. ETL path must work: API create dataset/resource → upload PDF/.zip via `ckanapi` → API create datastore+views → `COPY` ~500k rows into datastore from remote Hop host.
5. Services: `ckan` + `db` (PG 9.6, `ckan` + `datastore` DBs) + `solr` + `datapusher` (present, unused).
6. Plugins: `datastore`, `datapusher`, `recline_view` (+ Keitaro-baked `image_view`, `text_view`). File uploads via core `CKAN_STORAGE_PATH`, NOT a `filestore` plugin (doesn't exist in 2.7.x — crashes boot).

## Non-functional
1. Portable: no hardcoded IPs/hostnames; LAN/host config in `.env` only. Must be movable off this VPS.
2. Reachable: CKAN API (`5000`) + Postgres (`5432`) reachable from Hop host on same network.
3. Isolated state: all state in named Docker volumes; nothing persistent on host except `plan.md`/`requirements.md`/compose files.
4. Reference payload: ~50MB files, ~500k rows/run. No perf testing.
5. No HTTPS, no auth beyond single API key, no custom plugins in v1.

## Explicit non-goals (v1)
- Update-in-place tests / seed data (v2), prod dumps, unknown prod plugins, HTTPS, Redis, high-volume tests.
