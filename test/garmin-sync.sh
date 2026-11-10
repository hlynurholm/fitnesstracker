#!/usr/bin/env bash
# Checks the Garmin sync end to end against test/garmin-stub.mjs. Needs both running, on a fresh local database:
#   node test/garmin-stub.mjs
#   npx wrangler dev --var GARMIN_API_KEY:stub-key --var GARMIN_API_BASE:http://127.0.0.1:8799
set -u
BASE="${BASE:-http://127.0.0.1:8787}"
TOKEN="${API_TOKEN:-dev-token-change-me}"
pass=0; fail=0
check() { if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi; }
api() { curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" "$@"; }

out=$(api "$BASE/api/garmin"); check "status says configured" '[[ "$out" == *"\"configured\":true"* ]]'
out=$(api -X POST -d '{}' "$BASE/api/garmin/sync"); FIRST=$(mktemp); echo "$out" > "$FIRST"
check "first sync finds 3 activities" '[[ "$out" == *"\"found\":3"* ]]'
check "zipped activity 111 imported" '[[ "$out" == *"\"id\":\"111\",\"name\":\"Zipped run\",\"date\":\"2026-10-27\""* ]]'
check "bare FIT activity 222 imported" '[[ "$out" == *"\"id\":\"222\",\"name\":\"Bare FIT run\",\"date\":\"2026-10-27\""* ]]'
check "failed download 333 is reported, not fatal" '[[ "$out" == *"\"id\":\"333\""*"Garmin answered 500"* && "$out" == *"\"ok\":false"* ]]'
out=$(api "$BASE/api/uploads"); check "uploads hold both files under Garmin's own names" '[[ "$out" == *"111_ACTIVITY.fit"* && "$out" == *"222_ACTIVITY.fit"* ]]'
out=$(api "$BASE/api/activities"); n=$(grep -o '"distance_m":5000' <<<"$out" | wc -l | tr -d ' '); check "two parsed activities of 5000 m (got $n)" '[ "$n" = "2" ]'
out=$(api "$BASE/api/day/2026-10-27"); check "the run landed on the planned run of 27 Oct, marked done" '[[ "$out" == *"\"kind\":\"run\""*"\"status\":\"done\""* ]]'
out=$(api -X POST -d '{}' "$BASE/api/garmin/sync"); check "second sync imports nothing new" '[[ "$out" == *"\"imported\":[]"* && "$out" == *"\"already\":2"* ]]'
out=$(api "$BASE/api/uploads"); n=$(grep -o '_ACTIVITY.fit' <<<"$out" | wc -l | tr -d ' '); check "still two uploads after the second sync (got $n)" '[ "$n" = "2" ]'
out=$(api "$BASE/api/garmin"); check "last run is recorded" '[[ "$out" == *"\"last\":{\"at\":"* ]]'
calls=$(curl -s http://127.0.0.1:8799/__calls); check "only running activities were asked for" '[[ "$calls" == *"activityType=running"* ]]'
# daily health metrics: the first sync fetched about four months, later ones only the last days
first=$(cat "$FIRST")
check "first sync imported about 120 days of daily metrics" '[[ "$first" =~ \"daily\":\{\"days\":12[0-9] ]]'
check "the failing weight source is reported, the rest still imported" '[[ "$first" == *"Weight: Garmin answered 403"* ]]'
out=$(api "$BASE/api/metrics?days=200"); n=$(grep -o '"date":"' <<<"$out" | wc -l | tr -d ' '); check "metrics endpoint returns those days (got $n)" '[ "$n" -ge 120 ] && [ "$n" -le 123 ]'
check "steps, resting heart rate, sleep and HRV are stored under Garmin's names" '[[ "$out" == *"\"movement.steps.value\":"* && "$out" == *"\"heartRate.restingValue\":"* && "$out" == *"\"sleep.sleepTimeSeconds\":"* && "$out" == *"\"sleep.sleepScores.overall.value\":"* && "$out" == *"\"hrv.lastNightAvg\":"* && "$out" == *"\"hrv.status\":\"BALANCED\""* ]]'
check "identifiers, timestamps and event lists are left out" '[[ "$out" != *"userProfilePk"* && "$out" != *"uuid"* && "$out" != *"Timestamp"* && "$out" != *"activityEvents"* ]]'
calls=$(curl -s http://127.0.0.1:8799/__calls); sleeps=$(grep -o 'dailySleepSummariesByDate' <<<"$calls" | wc -l | tr -d ' ')
check "sleep history was fetched in four 31 day pieces, then one piece on the second sync (got $sleeps requests)" '[ "$sleeps" = "5" ]'
out=$(api "$BASE/api/export.json"); check "export includes daily metrics" '[[ "$out" == *"\"daily_metrics\":[{\"date\":"* ]]'
echo "passed: $pass, failed: $fail"
[ "$fail" = "0" ]
