# AGENTS.md — CKAN 2.7.2 ETL Test Instance

## What this is
Throwaway Dockerized CKAN 2.7.2 mimicking prod, for testing Hop+Python ETL (Action API + direct Postgres `COPY`).

## Structure
- `plan.md` — shared understanding from grilling: decisions, scope, deferred items, unresolved frontier. Read first.
- `requirements.md` — v1 functional/non-functional requirements + non-goals.
- `docker-compose.yml` + `.env` (when created) — entire instance definition. All host-specific values in `.env`, never hardcoded.
- `scripts/` (when created) — bootstrap (admin/token, datastore perms) and seed scripts only. No manual setup steps.

## Git
Remote: `git@github.com:Mlschwarzbold/ckan-2.7.2.git` (branch `main`). Auth is a repo deploy key, private part at `~/.ssh/ckan_etl_deploy` (never commit it). Prefix every git network op with:

```bash
export GIT_SSH_COMMAND="ssh -i ~/.ssh/ckan_etl_deploy"
```

Commit `plan.md`/`requirements.md`/`AGENTS.md` + compose/scripts together — a pushed commit must always be a working resettable instance.

## Rules for agents
1. `plan.md` + `requirements.md` are truth. Don't add plugins/services beyond the 4 approved without asking.
2. Keep it resettable: `docker compose down -v && docker compose up -d` must yield a fresh working instance. All state in named volumes.
3. Keep it portable: no VPS IPs/hostnames in compose files; use `.env`.
4. Don't reintroduce DataPusher into the ETL path; container exists for parity only.
5. Update `plan.md` when a decision changes; keep `requirements.md` in sync.
