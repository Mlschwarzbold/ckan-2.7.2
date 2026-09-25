# CKAN 2.7.2 ETL Test Instance

Throwaway Dockerized CKAN 2.7.2 mimicking prod, for testing the Hop + Python ETL
(Action API + direct Postgres `COPY` into the DataStore).

## Quickstart

```bash
docker compose up -d     # fresh blank instance
docker compose down -v   # full wipe (DBs, Solr index, filestore)
```

## Docs

- `plan.md` — decisions, scope, deferred items
- `requirements.md` — v1 requirements + non-goals
- `AGENTS.md` — structure, rules, git key usage

## Git

```bash
export GIT_SSH_COMMAND="ssh -i ~/.ssh/ckan_etl_deploy"
```
