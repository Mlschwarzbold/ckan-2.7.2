# CKAN 2.7.2 ETL Test Instance

Throwaway Dockerized CKAN 2.7.2 mimicking prod, for testing the Hop + Python ETL
(Action API + direct Postgres `COPY` into the DataStore).

## Quickstart

```bash
cp .env.example .env    # adjust ports/passwords if needed
docker compose up -d     # fresh blank instance (builds the Solr core image)
docker compose down -v   # full wipe (DBs, Solr index, filestore)
./scripts/mint-token.sh  # prints the sysadmin API token for ETL config
```

## Host prerequisites

- Docker + Compose.
- **ARM hosts only:** the CKAN app and datapusher images are `amd64`-only, so
  install binfmt/qemu once:
  `sudo apt-get install -y qemu-user-static binfmt-support`.
  Solr is rebuilt natively from `solr/Dockerfile` (see `plan.md`).
- No Redis needed (CKAN logs a benign "Redis is not available").

## API token

`scripts/mint-token.sh` prints the current `CKAN_SYSADMIN_*` user's API key.
The key lives in the DB and resets with `down -v`; the script is the stable
way to (re)read it after every boot. Use it as the CKAN auth token:

```bash
TOKEN=$(./scripts/mint-token.sh)
curl -H "Authorization: $TOKEN" http://localhost:5000/api/3/action/package_list
```

## Docs

- `plan.md` — decisions, scope, deferred items
- `requirements.md` — v1 requirements + non-goals
- `AGENTS.md` — structure, rules, git key usage

## Git

```bash
export GIT_SSH_COMMAND="ssh -i ~/.ssh/ckan_etl_deploy"
```
