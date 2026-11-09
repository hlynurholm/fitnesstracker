#!/usr/bin/env bash
# Pulls everything Claude needs for an analysis straight from the deployed app, no copy and paste.
#
#   FITNESS_API_TOKEN=... scripts/fetch-data.sh [out-dir]
#
# Env:
#   FITNESS_API_TOKEN  the app's API token (the API_TOKEN Worker secret). Required.
#   FITNESS_APP_URL    base URL, default https://fitness-tracker.hlynurholm97.workers.dev
#   FITNESS_RAW        set to 0 to skip downloading the raw Garmin files (default 1)
#
# Writes into out-dir (default ./fitness-data):
#   summary.md      the same text as "Copy summary for Claude" on the Data page
#   export.json     every table: workouts, sets, notes, body weight, tests, activities with splits, nutrition, uploads
#   diet.json       the Diet feed (targets, weekly rows, implied maintenance)
#   uploads.json    list of uploaded files with the workout they belong to
#   garmin/<id>-<filename>   the original Garmin files (.fit, .tcx, .gpx, .csv) and MyFitnessPal CSVs
set -euo pipefail

BASE="${FITNESS_APP_URL:-https://fitness-tracker.hlynurholm97.workers.dev}"
BASE="${BASE%/}"
OUT="${1:-fitness-data}"
TOKEN="${FITNESS_API_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo "FITNESS_API_TOKEN is not set. It is the app's API token (Worker secret API_TOKEN)." >&2
  exit 2
fi

mkdir -p "$OUT/garmin"
auth=(-H "Authorization: Bearer $TOKEN")

get() { # path, outfile
  local code
  code=$(curl -sS --max-time 60 -o "$2" -w "%{http_code}" "${auth[@]}" "$BASE$1") || { echo "network error fetching $1 (is $BASE reachable from here?)" >&2; exit 3; }
  case "$code" in
    200) ;;
    401|403) echo "HTTP $code from $1: the token was rejected" >&2; exit 4 ;;
    *) echo "HTTP $code from $1" >&2; exit 5 ;;
  esac
}

get /api/summary.md "$OUT/summary.md"
get /api/export.json "$OUT/export.json"
get "/api/diet?days=120" "$OUT/diet.json"
get /api/uploads "$OUT/uploads.json"

if [ "${FITNESS_RAW:-1}" != "0" ]; then
  # id<TAB>filename for every upload; the raw endpoint answers 404 when no original was kept.
  python3 -c 'import json, sys
for u in json.load(open(sys.argv[1])):
    name = (u.get("filename") or "upload").replace("/", "_")
    print(str(u["id"]) + "\t" + name)' "$OUT/uploads.json" |
  while IFS=$'\t' read -r id name; do
    code=$(curl -sS --max-time 120 -o "$OUT/garmin/$id-$name" -w "%{http_code}" "${auth[@]}" "$BASE/api/uploads/$id/raw") || true
    if [ "$code" != "200" ]; then rm -f "$OUT/garmin/$id-$name"; echo "upload $id ($name): no raw file (HTTP $code)" >&2; fi
  done
fi

n_files=$(find "$OUT/garmin" -type f | wc -l | tr -d ' ')
echo "Fetched from $BASE into $OUT: summary.md, export.json, diet.json, uploads.json and $n_files raw files"
