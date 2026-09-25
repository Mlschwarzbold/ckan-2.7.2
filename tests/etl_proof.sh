#!/usr/bin/env bash
# ETL-path proof for the CKAN 2.7.2 test instance (mirrors Hop + ckanapi):
#   Action API: dataset + resource uploads -> datastore_create -> recline_view
#   Direct PG over published 5432: COPY rows into the datastore table (bypasses API)
# Leaves the instance UP. Logs one line per milestone to /tmp/etl-proof.log.
set -euo pipefail
cd "$(dirname "$0")/.."

LOG=/tmp/etl-proof.log
STAGE=start
log(){ echo "STAGE $STAGE: $*" >> "$LOG"; }
fail(){ echo "STAGE failed: stage=$STAGE err=$*" >> "$LOG"; exit 1; }
trap 'fail "$BASH_COMMAND"' ERR

# DB creds from local .env (never hardcode / never commit). Read only the
# scalar keys we need — .env has space-separated values (CKAN__PLUGINS) that
# are not shell-sourceable.
eval "$(grep -E '^(CKAN_PORT|POSTGRES_PORT|POSTGRES_USER|POSTGRES_PASSWORD|DATASTORE_DB)=' .env)"
API="http://localhost:${CKAN_PORT}"

STAGE=start
TOKEN=$(bash scripts/mint-token.sh)
log "token minted (len ${#TOKEN})"
AUTH=(-H "Authorization: $TOKEN")

DS="etl-proof-$(date +%s)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. dataset (needs an org on stock 2.7: unowned datasets require sysadmin)
STAGE=dataset
ORG_ID=$(curl -s -X POST "$API/api/3/action/organization_create" "${AUTH[@]}" \
  -H 'Content-Type: application/json' -d '{"name":"etl-proof","title":"ETL Proof"}' \
  | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["result"]["id"] if r.get("success") else "")')
[ -n "$ORG_ID" ] || ORG_ID=$(curl -s "$API/api/3/action/organization_show?id=etl-proof" "${AUTH[@]}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["id"])')
PACKAGE_ID=$(curl -s -X POST "$API/api/3/action/package_create" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"name\":\"$DS\",\"title\":\"ETL Proof\",\"owner_org\":\"$ORG_ID\"}" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["result"]["id"] if r.get("success") else (_ for _ in ()).throw(SystemExit(json.dumps(r))))')
log "created $DS id=$PACKAGE_ID"

# 2. small representative payload (~300 rows), CSV + zip
STAGE=upload
python3 - "$WORK" <<'PY'
import csv, random, sys, zipfile, os
work=sys.argv[1]; random.seed(42)
with open(os.path.join(work,'proof.csv'),'w',newline='') as f:
    w=csv.writer(f); w.writerow(['record_id','name','value','category'])
    for i in range(1,301):
        w.writerow([i,'item_%03d'%i,round(random.uniform(1,1000),2),random.choice(['alpha','beta','gamma','delta'])])
with zipfile.ZipFile(os.path.join(work,'proof.zip'),'w',zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(work,'proof.csv'),'proof.csv')
PY
upload(){ # name format file -> resource id
  curl -s -X POST "$API/api/3/action/resource_create" "${AUTH[@]}" \
    -F "package_id=$PACKAGE_ID" -F "name=$1" -F "format=$2" -F "upload=@$3" \
    | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["result"]["id"] if r.get("success") else (_ for _ in ()).throw(SystemExit(json.dumps(r))))'
}
CSV_RID=$(upload proof.csv CSV "$WORK/proof.csv")
ZIP_RID=$(upload proof.zip ZIP "$WORK/proof.zip")
log "uploaded csv=$CSV_RID zip=$ZIP_RID"

# 3. datastore_create with fields derived from the CSV header
STAGE=datastore
FIELDS=$(python3 - "$WORK/proof.csv" <<'PY'
import csv,json,sys
types={'record_id':'int4','value':'numeric'}
hdr=next(csv.reader(open(sys.argv[1])))
print(json.dumps([{'id':h,'type':types.get(h,'text')} for h in hdr]))
PY
)
curl -s -X POST "$API/api/3/action/datastore_create" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"resource_id\":\"$CSV_RID\",\"fields\":$FIELDS,\"force\":true}" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin);r.get("success") or (_ for _ in ()).throw(SystemExit(json.dumps(r)))'
log "datastore_create resource=$CSV_RID fields=$FIELDS"

# 4. direct COPY over published 5432 (Hop PG Bulk Loader equivalent), API bypassed
STAGE=copy
docker run --rm -i --network host -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:9.6.18 \
  psql -h 127.0.0.1 -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATASTORE_DB" -v ON_ERROR_STOP=1 \
  -c "\copy \"$CSV_RID\" (record_id,name,value,category) FROM STDIN WITH (FORMAT csv, HEADER true)" \
  < "$WORK/proof.csv"
log "direct COPY into $CSV_RID done"

# 5. recline_view via API
STAGE=view
VIEW_ID=$(curl -s -X POST "$API/api/3/action/resource_view_create" "${AUTH[@]}" \
  -H 'Content-Type: application/json' \
  -d "{\"resource_id\":\"$CSV_RID\",\"view_type\":\"recline_view\",\"title\":\"ETL Proof Recline\"}" \
  | python3 -c 'import sys,json;r=json.load(sys.stdin);print(r["result"]["id"] if r.get("success") else (_ for _ in ()).throw(SystemExit(json.dumps(r))))')
log "recline_view id=$VIEW_ID on $CSV_RID"

# 6. verify from the outside: row counts (API + direct SQL), uploads, view
STAGE=verify
API_TOTAL=$(curl -s -X POST "$API/api/3/action/datastore_search" "${AUTH[@]}" \
  -H 'Content-Type: application/json' -d "{\"resource_id\":\"$CSV_RID\",\"limit\":0}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["total"])')
DB_TOTAL=$(docker run --rm --network host -e PGPASSWORD="$POSTGRES_PASSWORD" postgres:9.6.18 \
  psql -h 127.0.0.1 -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$DATASTORE_DB" -tAc "SELECT count(*) FROM \"$CSV_RID\";")
[ "$API_TOTAL" = "300" ] || fail "datastore_search total=$API_TOTAL != 300"
[ "$DB_TOTAL" = "300" ] || fail "direct count=$DB_TOTAL != 300"
for rid in "$CSV_RID" "$ZIP_RID"; do
  url=$(curl -s "$API/api/3/action/resource_show?id=$rid" "${AUTH[@]}" \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["url"])')
  code=$(curl -s -o /dev/null -w '%{http_code}' "$url")
  [ "$code" = "200" ] || fail "download $rid HTTP $code"
done
curl -s "$API/api/3/action/resource_view_list?id=$CSV_RID" "${AUTH[@]}" \
  | python3 -c 'import sys,json;assert any(v["view_type"]=="recline_view" for v in json.load(sys.stdin)["result"]), "no recline_view"'

STAGE=done
log "PASS dataset=$DS package=$PACKAGE_ID csv=$CSV_RID zip=$ZIP_RID view=$VIEW_ID api_total=$API_TOTAL db_total=$DB_TOTAL"
echo "ETL proof PASS: dataset=$DS rows=$API_TOTAL view=$VIEW_ID"
