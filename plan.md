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

## Temporary public edge (added 2026-09-25, TEAR DOWN after viewing)
- `docker-compose.edge.yml` routes only `ckan` via Traefik (`core-proxy` net) → `https://ckan-test.mls.cloud-ip.cc`, LE cert valid to 2026-12-24. db/solr/datapusher never exposed.
- Local `.env` currently sets `CKAN_SITE_URL=https://ckan-test.mls.cloud-ip.cc` — flip back to `http://localhost:5000` + recreate when Hop testing starts.
- Teardown: `docker compose -f docker-compose.yml -f docker-compose.edge.yml down` then `up -d` without the overlay (or just `down` the edge). Delete overlay + hostname when done.

## Explicitly deferred / out of scope for v1
- Unknown prod plugins, prod `pg_dump`, update-in-place seed data, HTTPS/domain, Redis, high-volume/perf tests.

## Host reality (discovered 2026-09-25, arm64 VPS)
- Host is **aarch64** (Ubuntu 24.04, Oracle ARM). `postgres:9.6.18` is multi-arch (native arm64); the three CKAN-side images are **amd64-only** (single-arch manifests, no arm64 tag).
- Boot fix (applied, portable):
  - Host prerequisite: `qemu-user-static` + `binfmt-support` installed and registered (runs amd64 binaries; only the JVM misbehaves). Documented in README. Required on any ARM host; a no-op dependency on x86.
  - `solr` service now **builds** `solr/Dockerfile` = official `solr:6.6.5` (arm64) + CKAN 2.7 core config extracted verbatim from `ckan/ckan-solr:2.7`. JVM under qemu hangs, so emulating the stock solr image is not viable. Same Solr 6 line; CKAN schema unchanged.
  - uWSGI on qemu dies on `pthread robust mutexes` (`unable to make the mutex 'robust'`). Fixed with `--lock-engine ipcsem`: CKAN via a `[uwsgi]` section injected into `production.ini` at container start, datapusher via a `command:` override. Both stock entrypoint logic otherwise unchanged.
  - `keitaro/ckan:2.7` and `keitaro/ckan-datapusher` still run amd64-under-qemu (Python 2.7 works fine, just slower; CKAN HTTP ready ~80s).

## Unresolved (next frontier)
1. ~~Exact images~~ RESOLVED by scout 2026-09-25 (manifests verified, nothing pulled):
   - `postgres:9.6.18` ✅ exact prod match (~200MB on disk).
   - `ckan/ckan-solr:2.7` ✅ (Solr 6, schema baked in — CKAN 2.7 requires Solr 6). **Superseded on ARM**: rebuilt as native `solr:6.6.5` + CKAN config (see Host reality).
   - `keitaro/ckan-datapusher:0.0.14` ✅ era-correct, presence-only.
   - CKAN app: NO stock 2.7.2 image exists (`ckan/ckan` repo doesn't exist; `keitaro/ckan:2.7` = 2.7.9, verified from image). Exact 2.7.2 = custom build from `ckan/ckan@ckan-2.7.2` + Keitaro 2.7 Dockerfile. Combined pull ~0.5GB, no disk concern.
   - DECIDED 2026-09-25: option A — stock `keitaro/ckan:2.7` (=2.7.9) for v1 (patch drift accepted; rebuild as exact 2.7.2 in v2 only if a version quirk appears).
   - CORRECTION 2026-09-25 (worker, from image): `filestore` is NOT a plugin in 2.7.x — uploads via core `CKAN_STORAGE_PATH`. Never list it in `ckan.plugins` (crashes boot).
2. Network: Hop host IP, firewall for `5000` (API) + `5432` (PG), `pg_hba.conf` + datastore writer user.
3. Bootstrap: `datastore` DB + readonly role created compose-only (inline SQL); CKAN prerun runs `set-permissions` + sysadmin autocreate. DONE: API token — `scripts/mint-token.sh` prints the current `CKAN_SYSADMIN_NAME` apikey (CKAN 2.7 has no `user token add`; the keitaro prerun auto-generates the key). NOTE: CKAN also auto-creates a `default` site user that is a sysadmin — script filters by name. REMAINS: `CKAN_SITE_URL` + firewall for Hop.
4. Disk: 12GB free — prune strategy, volume sizing check.
5. Reset-proofing DONE 2026-09-25: `down -v` (11s) removes all 4 containers + 3 volumes + network, zero project residue; `up -d` → healthy in ~143s total (CKAN ~131s under qemu, slower than the 90s first-boot guess — use 3-min timeouts). Freshness verified (old id → 404, `package_list` == `[]`, new token minted), `tests/etl_proof.sh` reruns PASS in 9s. Stray ad-hoc `docker run` containers from early experiments removed; they were stateless and never project state.
6. ETL-path PROVEN 2026-09-25 (`tests/etl_proof.sh`, 300 rows): dataset → CSV+.zip upload → `datastore_create` → direct `\copy` over 5432 → `recline_view`, API total == DB total. Notes: stock 2.7 requires `owner_org` (script creates org); direct COPY leaves CKAN-managed `_id`/`_full_text` alone (`_full_text` stays empty, filters/counts fine); CKAN auto-adds a "Data Explorer" recline_view.
