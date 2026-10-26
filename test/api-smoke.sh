#!/usr/bin/env bash
# End-to-end smoke test against a running `wrangler dev` (default http://127.0.0.1:8787).
set -u
BASE="${BASE:-http://127.0.0.1:8787}"
PW="${APP_PASSWORD:-changeme}"
TOKEN="${API_TOKEN:-dev-token-change-me}"
JAR=$(mktemp)
pass=0; fail=0
check() { # name, condition
  if eval "$2"; then echo "ok   $1"; pass=$((pass+1)); else echo "FAIL $1"; fail=$((fail+1)); fi
}
j() { curl -s -b "$JAR" -c "$JAR" -H "Content-Type: application/json" "$@"; }

# unauthenticated
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/api/day/2026-10-26"); check "api requires login (401)" '[ "$code" = "401" ]'
code=$(curl -s -o /dev/null -w "%{http_code}" "$BASE/"); check "root redirects to /login (302)" '[ "$code" = "302" ]'
code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{"password":"wrong"}' "$BASE/api/login"); check "wrong password rejected (401)" '[ "$code" = "401" ]'
# login
out=$(j -X POST -d "{\"password\":\"$PW\"}" "$BASE/api/login"); check "login ok" '[[ "$out" == *"\"ok\":true"* ]]'
code=$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" "$BASE/"); check "root serves app when logged in (200)" '[ "$code" = "200" ]'
# bearer token
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$BASE/api/settings"); check "bearer token works (200)" '[ "$code" = "200" ]'
code=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer nope" "$BASE/api/settings"); check "bad bearer rejected (401)" '[ "$code" = "401" ]'
# program and day
out=$(j "$BASE/api/day/2026-10-26"); check "day: Monday 26 Oct is Lift A" '[[ "$out" == *"\"templateKey\":\"lift_a\""* ]]'
check "day: plan has back squat" '[[ "$out" == *"back_squat"* ]]'
out=$(j "$BASE/api/day/2026-10-27"); check "day: Tuesday week 1 is the 5k time trial" '[[ "$out" == *"time_trial_5k"* ]]'
# log sets
out=$(j -X PUT -d '{"date":"2026-10-26","template_key":"lift_a","exercise_key":"back_squat","set_index":0,"weight_kg":75,"reps":5}' "$BASE/api/sets/testset0001"); check "set upsert creates workout" '[[ "$out" == *"workout_id"* ]]'
out=$(j -X PUT -d '{"date":"2026-10-26","template_key":"lift_a","exercise_key":"back_squat","set_index":0,"weight_kg":77.5,"reps":5}' "$BASE/api/sets/testset0001"); check "set upsert updates in place" '[[ "$out" == *"77.5"* ]]'
j -X PUT -d '{"date":"2026-10-26","template_key":"lift_a","exercise_key":"back_squat","set_index":1,"weight_kg":77.5,"reps":5}' "$BASE/api/sets/testset0002" >/dev/null
j -X PUT -d '{"date":"2026-10-26","template_key":"lift_a","exercise_key":"pull_up","set_index":0,"reps":8}' "$BASE/api/sets/testset0003" >/dev/null
j -X PUT -d '{"date":"2026-10-26","template_key":"lift_a","exercise_key":"copenhagen_plank","set_index":0,"seconds":20}' "$BASE/api/sets/testset0004" >/dev/null
out=$(j "$BASE/api/day/2026-10-26"); check "day returns the 4 logged sets" '[[ "$out" == *testset0001* && "$out" == *testset0002* && "$out" == *testset0003* && "$out" == *testset0004* ]]'
# finish workout with rpe and notes and checklist
out=$(j -X PUT -d '{"template_key":"lift_a","status":"done","rpe":7,"notes":"knees fine","checklist":{"warmup":{"bike":true}}}' "$BASE/api/day/2026-10-26/workout"); check "workout done with rpe" '[[ "$out" == *"\"rpe\":7"* && "$out" == *"\"status\":\"done\""* ]]'
# last values show up on the next Lift A (2 Nov)
out=$(j "$BASE/api/day/2026-11-02"); check "next Lift A shows last values" '[[ "$out" == *"\"last\":{"* && "$out" == *"back_squat"* && "$out" == *"77.5"* ]]'
# body weight and tests
out=$(j -X PUT -d '{"date":"2026-10-26","weight_kg":93.0}' "$BASE/api/body"); check "body weight saved" '[[ "$out" == *"93"* ]]'
out=$(j -X PUT -d '{"date":"2026-10-27","test_key":"five_k_sec","value":1560}' "$BASE/api/tests"); check "test saved with week 1" '[[ "$out" == *"\"week_no\":1"* ]]'
# run day logging
out=$(j -X PUT -d '{"template_key":"time_trial_5k","distance_km":5.0,"time_sec":1560,"avg_hr":168,"status":"done"}' "$BASE/api/day/2026-10-27/workout"); check "run workout saved" '[[ "$out" == *"\"time_sec\":1560"* ]]'
WID=$(echo "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')
out=$(curl -s -b "$JAR" -F "file=@test/out/run.fit" -F "workout_id=999999" "$BASE/api/uploads"); check "upload with unknown workout_id is a clean 400" '[[ "$out" == *"Unknown workout_id"* ]]'
# uploads: FIT attached to the run
out=$(curl -s -b "$JAR" -F "file=@test/out/run.fit" -F "workout_id=$WID" -F "tz_offset_min=0" "$BASE/api/uploads"); check "FIT upload parsed" '[[ "$out" == *"\"status\":\"parsed\""* && "$out" == *"\"distance_m\":5000"* ]]'
out=$(j "$BASE/api/day/2026-10-27"); check "activity attached to the run" '[[ "$out" == *"\"activities\":[{"* ]]'
# FIT without workout id on a date with no workout -> auto-creates (date 2026-10-27 already has one, so it attaches)
out=$(curl -s -b "$JAR" -F "file=@test/out/run.fit" -F "tz_offset_min=0" "$BASE/api/uploads"); check "FIT auto-match by date" '[[ "$out" == *"\"workout_id\":'"$WID"'"* ]]'
# MFP
out=$(curl -s -b "$JAR" -F "file=@test/out/mfp.csv" -F "source=myfitnesspal" "$BASE/api/uploads"); check "MFP nutrition parsed (2 days)" '[[ "$out" == *"\"nutrition_days\":2"* ]]'
out=$(curl -s -b "$JAR" -F "file=@test/out/weights.csv" -F "source=myfitnesspal" "$BASE/api/uploads"); check "MFP weights parsed (2)" '[[ "$out" == *"\"body_metrics\":2"* ]]'
out=$(j "$BASE/api/nutrition"); check "nutrition day totals" '[[ "$out" == *"\"calories\":1900"* ]]'
# activity detail
AID=$(j "$BASE/api/activities" | sed -n 's/^\[{"id":\([0-9]*\).*/\1/p'); out=$(j "$BASE/api/activities/$AID"); check "activity detail has splits and track" '[[ "$out" == *"\"splits\":[{"* && "$out" == *"\"track\":[{"* ]]'
# raw download round trip
curl -s -b "$JAR" -o test/out/roundtrip.fit "$BASE/api/uploads/1/raw"; check "raw FIT round trip identical" 'cmp -s test/out/run.fit test/out/roundtrip.fit'
# dashboard, export, summary
out=$(j "$BASE/api/dashboard"); check "dashboard has sets, body, nutrition, activities" '[[ "$out" == *"\"sets\":[{"* && "$out" == *"\"body\":[{"* && "$out" == *"\"nutrition\":[{"* && "$out" == *"\"activities\":[{"* ]]'
out=$(j "$BASE/api/export.json"); check "export has all tables" '[[ "$out" == *"\"workouts\":[{"* && "$out" == *"\"uploads\":[{"* && "$out" == *"\"tests\":[{"* ]]'
out=$(j "$BASE/api/export.json?include=raw"); check "export with raw base64" '[[ "$out" == *"raw_base64"* ]]'
out=$(j "$BASE/api/summary.md"); check "summary markdown" '[[ "$out" == *"# Fitness data summary"* && "$out" == *"Back squat"* ]]'
echo "--- summary preview ---"; echo "$out" | head -40; echo "--- end ---"
# reports
out=$(curl -s -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X POST -d '{"title":"Test report","body_md":"# Hello\n\nAll good."}' "$BASE/api/reports"); check "report created via token" '[[ "$out" == *"\"title\":\"Test report\""* ]]'
out=$(j "$BASE/api/reports"); check "reports listed" '[[ "$out" == *"Test report"* ]]'
# history list
out=$(j "$BASE/api/workouts"); check "workouts list has volume" '[[ "$out" == *"volume_kg"* ]]'
# settings
out=$(j -X PUT -d '{"max_hr":"188"}' "$BASE/api/settings"); check "settings saved" '[[ "$out" == *"\"max_hr\":\"188\""* ]]'
out=$(j -X PUT -d '{"bogus":"1"}' "$BASE/api/settings"); check "unknown setting rejected" '[[ "$out" == *"Unknown setting"* ]]'
# delete set
out=$(j -X DELETE "$BASE/api/sets/testset0004"); check "set deleted" '[[ "$out" == *"ok"* ]]'
# logout
j -X POST "$BASE/api/logout" >/dev/null; code=$(curl -s -o /dev/null -w "%{http_code}" -b "$JAR" "$BASE/api/settings"); check "logout clears session (401)" '[ "$code" = "401" ]'
echo; echo "passed: $pass, failed: $fail"
rm -f "$JAR"
[ "$fail" = "0" ]
