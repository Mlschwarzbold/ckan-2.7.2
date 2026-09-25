# CKAN 2.7.2 ETL Test Instance — Shared Understanding (v1)

Date: 2026-09-25. Host: this VPS (`/home/ubuntu/proj/ckan-2.7.2`).

## Goal
Dockerized CKAN 2.7.2 for ETL testing, mimicking prod. v1 = blank stock instance. Adapt toward prod parity later.

## ETL (decided)
- Runs on separate host, same network (Apache Hop + Python).
- Uses Action API: create datasets/resources, upload files (PDF, .zip CSVs via `ckanapi`), create datastore + views.
- Loads rows direct to Postgres datastore via `COPY` (Hop PG Bulk Loader step). `STDIN`-style over network preferred; no server-side file dependency.
- Auth: single normal API key (token) for everything.
- DataPusher exists in prod but ETL intentionally avoids it.

## Real instance (facts)
- CKAN 2.7.2, Postgres 9.6.18.
- Relevant plugins: `datastore`, `datapusher`, `filestore`, `recline_view`. Other plugins unknown but out of ETL scope.
- Auth: single API key.

## v1 scope (decided)
- Minimal slice: blank stock 2.7.2 + `datastore + filestore + recline_view` (+ `datapusher` container present but unused).
- 1 admin user + 1 fixed API token, auto-created on boot (zero manual clicks, stable across resets).
- No custom plugins, no prod data, no HTTPS.
- Success = ETL can: create dataset → upload file → create datastore → `COPY` rows → create view.

## Topology (decided)
- 4 services: `ckan` (2.7.2) + `db` (PG 9.6, hosts both `ckan` + `datastore` DBs) + `solr` (required for indexing) + `datapusher`.
- No Redis, no Nginx/HTTPS.
- All state in named Docker volumes (DB, filestore, solr). Nothing on host → portable for later move.

## Test modes (decided)
- v1: fresh-instance uploads only (`down -v && up -d` = full wipe).
- v2 (deferred): seed scripts / pre-existing datasets for update-in-place tests.

## Payload + cleanup (decided)
- Reference size: ~50MB files, ~500k rows per run. No high-volume testing for now.
- `down -v` must leave zero residue. Anything surviving outside volumes = bug.

## Hosting + lifecycle (decided)
- Lives on this VPS for now, portable elsewhere later (no hardcoded IPs, use `.env`).
- Must come up/down with one command. HTTPS deferred.

## Explicitly deferred / out of scope for v1
- Unknown prod plugins, prod `pg_dump`, update-in-place seed data, HTTPS/domain, Redis, high-volume/perf tests.

## Unresolved (next frontier)
1. ~~Exact images~~ RESOLVED by scout 2026-09-25 (manifests verified, nothing pulled):
   - `postgres:9.6.18` ✅ exact prod match (~200MB on disk).
   - `ckan/ckan-solr:2.7` ✅ (Solr 6, schema baked in — CKAN 2.7 requires Solr 6).
   - `keitaro/ckan-datapusher:0.0.14` ✅ era-correct, presence-only.
   - CKAN app: NO stock 2.7.2 image exists (`ckan/ckan` repo doesn't exist; `keitaro/ckan:2.7` = 2.7.9, verified from image). Exact 2.7.2 = custom build from `ckan/ckan@ckan-2.7.2` + Keitaro 2.7 Dockerfile. Combined pull ~0.5GB, no disk concern.
   - DECIDED 2026-09-25: option A — stock `keitaro/ckan:2.7` (=2.7.9) for v1 (patch drift accepted; rebuild as exact 2.7.2 in v2 only if a version quirk appears).
   - CORRECTION 2026-09-25 (worker, from image): `filestore` is NOT a plugin in 2.7.x — uploads via core `CKAN_STORAGE_PATH`. Never list it in `ckan.plugins` (crashes boot).
2. Network: Hop host IP, firewall for `5000` (API) + `5432` (PG), `pg_hba.conf` + datastore writer user.
3. Bootstrap: `datastore` DB + readonly role created compose-only (inline SQL); CKAN prerun runs `set-permissions` + sysadmin autocreate. REMAINS: fixed API token (`ckan user token add`) + `CKAN_SITE_URL` + firewall for Hop.
4. Disk: 12GB free — prune strategy, volume sizing check.
