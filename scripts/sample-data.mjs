#!/usr/bin/env node
// Prints SQL that fills the database with six weeks of made-up training history, or removes it again.
//
//   node scripts/sample-data.mjs add    > sample.sql
//   node scripts/sample-data.mjs remove > sample.sql
//   npx wrangler d1 execute fitness-tracker-db --remote --file sample.sql
//
// The sample weeks run from SAMPLE_START (a Monday) to the day before the real program start, so real
// data logged from the program start onwards is never touched. While the sample data is in, the
// program start date is moved back to SAMPLE_START so the history shows up as weeks 1 to 6; "remove"
// restores the previous start date and deletes every row inside the sample date range.
import { PROGRAM, buildPlan, scheduledTemplateKey, addDays, isDeloadWeek } from "../public/js/program.js";

const SAMPLE_WEEKS = 6;
const REAL_START = PROGRAM.startDateDefault; // 2026-10-26
const SAMPLE_START = addDays(REAL_START, -7 * SAMPLE_WEEKS); // 2026-09-14
const SAMPLE_END = addDays(REAL_START, -1); // 2026-10-25
const action = process.argv[2] || "add";

const q = (v) => (v === null || v === undefined ? "NULL" : typeof v === "number" ? String(v) : `'${String(v).replace(/'/g, "''")}'`);
const out = [];
const sql = (s) => out.push(s.trim() + (s.trim().endsWith(";") ? "" : ";"));

// Deterministic pseudo-random so every run produces the same data.
let seed = 20260914;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
const jitter = (amount) => (rnd() * 2 - 1) * amount;
const round = (v, step = 0.5) => Math.round(v / step) * step;

if (action === "remove") {
  sql(`DELETE FROM sets WHERE workout_id IN (SELECT id FROM workouts WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)})`);
  sql(`DELETE FROM activities WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM uploads WHERE filename LIKE 'sample_%'`);
  sql(`DELETE FROM workouts WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM body_metrics WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM nutrition_days WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM tests WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM schedule_overrides WHERE date BETWEEN ${q(SAMPLE_START)} AND ${q(SAMPLE_END)}`);
  sql(`DELETE FROM reports WHERE title LIKE '[Sample]%'`);
  // Put the program start back to what it was before the sample data went in.
  sql(`DELETE FROM settings WHERE key = 'program_start_date'`);
  sql(`INSERT INTO settings (key, value, updated_at) SELECT 'program_start_date', value, datetime('now') FROM settings WHERE key = 'sample_prev_start'`);
  sql(`DELETE FROM settings WHERE key IN ('sample_prev_start', 'sample_data')`);
  process.stdout.write(out.join("\n") + "\n");
  process.exit(0);
}

// ---------- add ----------
sql(`INSERT OR IGNORE INTO settings (key, value, updated_at) SELECT 'sample_prev_start', value, datetime('now') FROM settings WHERE key = 'program_start_date'`);
sql(`INSERT INTO settings (key, value, updated_at) VALUES ('program_start_date', ${q(SAMPLE_START)}, datetime('now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`);
sql(`INSERT INTO settings (key, value, updated_at) VALUES ('sample_data', '1', datetime('now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')`);

// Starting loads and weekly progression per exercise. kg is per hand for dumbbells.
const LOADS = {
  back_squat: { kg: 75, step: 2.5, reps: 5 },
  db_bench: { kg: 26, step: 1, reps: [6, 7, 7, 8, 8, 8] },
  db_single_leg_rdl: { kg: 16, step: 1, reps: 8 },
  pull_up: { reps: [7, 7, 8, 8, 9, 9], bodyweight: true },
  copenhagen_plank: { seconds: 20 },
  suitcase_carry: { kg: 24, step: 2, meters: 30 },
  deadlift: { kg: 120, step: 5, reps: 4 },
  db_ohp: { kg: 18, step: 1, reps: 8 },
  db_reverse_lunge: { kg: 16, step: 1, reps: 8 },
  chest_supported_row: { kg: 22, step: 1, reps: 10 },
  nordic_curl: { reps: [4, 4, 5, 5, 6, 6], bodyweight: true },
  side_plank: { seconds: 30 },
  bulgarian_split_squat: { kg: 16, step: 1, reps: 8 },
  incline_db_press: { kg: 22, step: 1, reps: [8, 9, 9, 10, 10, 10] },
  lat_pulldown: { kg: 55, step: 2.5, reps: [10, 11, 11, 12, 12, 12] },
  hip_thrust: { kg: 30, step: 2, reps: 10 },
  tib_calf: { reps: 15, bodyweight: true },
  pallof_press: { kg: 15, step: 2.5, reps: 10 },
};

const WARMUP_IDS = PROGRAM.warmup.items.map((i) => i.id);
let workoutId = 900001; // high explicit ids keep sample rows apart from real ones
let uploadId = 900001;
let activityId = 900001;
let setN = 0;

function insertWorkout(w) {
  const id = workoutId++;
  sql(`INSERT INTO workouts (id, date, template_key, kind, status, week_no, phase, plan_json, checklist_json, started_at, finished_at, duration_min, distance_km, time_sec, avg_hr, rpe, notes, created_at, updated_at)
       VALUES (${id}, ${q(w.date)}, ${q(w.template_key)}, ${q(w.kind)}, ${q(w.status)}, ${w.week}, ${w.phase}, ${q(w.plan_json)}, ${q(w.checklist_json)}, ${q(w.started_at)}, ${q(w.finished_at)}, ${q(w.duration_min)}, ${q(w.distance_km)}, ${q(w.time_sec)}, ${q(w.avg_hr)}, ${q(w.rpe)}, ${q(w.notes)}, ${q(w.date + "T20:00:00")}, ${q(w.date + "T20:00:00")})`);
  return id;
}

function phaseFor(week) { return PROGRAM.phases.find((p) => week >= p.weekFrom && week <= p.weekTo).id; }

function liftSets(wid, templateKey, week, date) {
  const plan = buildPlan(templateKey, week);
  for (const e of plan) {
    const L = LOADS[e.key];
    if (!L) continue;
    const prog = week - 1;
    for (let i = 0; i < e.sets; i++) {
      setN++;
      const row = { kg: null, reps: null, seconds: null, meters: null };
      if (L.kg != null) row.kg = round(L.kg + L.step * prog - (i === e.sets - 1 && rnd() < 0.25 ? L.step : 0), L.step >= 2.5 ? 2.5 : 1);
      if (L.reps != null) { const r = Array.isArray(L.reps) ? L.reps[prog] : L.reps; row.reps = Math.max(1, r - (i === e.sets - 1 && rnd() < 0.3 ? 1 : 0)); }
      if (L.seconds != null) row.seconds = L.seconds + Math.min(15, prog * 3) + (rnd() < 0.3 ? 5 : 0);
      if (L.meters != null) row.meters = L.meters;
      if (isDeloadWeek(week) && row.kg != null) row.kg = round(row.kg * 0.85, 2.5);
      sql(`INSERT INTO sets (client_id, workout_id, exercise_key, set_index, weight_kg, reps, seconds, distance_m, done, created_at, updated_at)
           VALUES (${q(`sample-${wid}-${e.key}-${i}`)}, ${wid}, ${q(e.key)}, ${i}, ${q(row.kg)}, ${q(row.reps)}, ${q(row.seconds)}, ${q(row.meters)}, 1, ${q(date + "T18:" + String(10 + i * 3).padStart(2, "0") + ":00")}, ${q(date + "T18:" + String(10 + i * 3).padStart(2, "0") + ":00")})`);
    }
  }
}

function checklist(templateKey, week) {
  const t = PROGRAM.templates[templateKey];
  const c = {};
  if (t.blocks.includes("warmup")) { c.warmup = {}; for (const id of WARMUP_IDS) c.warmup[id] = true; }
  if (t.blocks.includes("jumps")) { c.jumps = {}; for (const j of PROGRAM.jumps.byPhase[phaseFor(week)]) c.jumps[j.id] = rnd() > 0.1; }
  if (t.blocks.includes("finisher")) c.finisher = { done: true };
  return JSON.stringify(c);
}

// Garmin-like activity for a run: splits, HR zones and a downsampled track.
function runActivity(wid, date, startHour, km, paceSec, avgHr, kind) {
  const total = Math.round(km * paceSec);
  const splits = [];
  let acc = 0;
  for (let k = 1; k <= Math.ceil(km); k++) {
    const dist = k <= Math.floor(km) ? 1000 : Math.round((km - Math.floor(km)) * 1000);
    if (dist <= 0) break;
    let p = paceSec + jitter(12);
    if (kind === "intervals") p = paceSec + (k % 2 ? -45 : 40) + jitter(8);
    if (kind === "tt") p = paceSec + (k === Math.ceil(km) ? -12 : k === 1 ? -5 : 4) + jitter(5);
    const secs = Math.round(p * dist / 1000);
    acc += secs;
    splits.push({ km: k, distance_m: dist, seconds: secs, pace_s_per_km: Math.round(p), avg_hr: Math.round(avgHr + (k - 1) * 2 + jitter(3)), partial: dist < 1000 || undefined });
  }
  const track = [];
  const points = 120;
  for (let i = 0; i <= points; i++) {
    const frac = i / points;
    const t = Math.round(acc * frac);
    let hr = avgHr - 25 + 35 * Math.min(1, frac * 6) + jitter(3);
    if (kind === "intervals") hr += Math.sin(frac * Math.PI * 12) * 12;
    track.push({ t, d: Math.round(km * frac * 100) / 100, hr: Math.round(hr), pace: Math.round(paceSec + (kind === "intervals" ? Math.sin(frac * Math.PI * 12) * -42 : jitter(10))), alt: Math.round((20 + Math.sin(frac * 6) * 8) * 10) / 10 });
  }
  const maxHr = 190;
  const zones = kind === "easy" ? [0.05, 0.55, 0.35, 0.05, 0] : kind === "intervals" ? [0.05, 0.15, 0.25, 0.35, 0.2] : [0, 0.03, 0.12, 0.45, 0.4];
  const hrZones = { max_hr_used: maxHr, seconds: zones.map((z) => Math.round(z * acc)) };
  const uid = uploadId++;
  const start = `${date}T${String(startHour).padStart(2, "0")}:02:11Z`;
  const name = kind === "tt" ? "5 km time trial" : kind === "intervals" ? "Intervals" : "Easy run";
  sql(`INSERT INTO uploads (id, workout_id, source, format, filename, content_type, size_bytes, raw, raw_encoding, parsed_json, parse_status, uploaded_at)
       VALUES (${uid}, ${wid}, 'garmin', 'fit', ${q(`sample_${date}_${kind}.fit`)}, 'application/octet-stream', ${Math.round(acc * 9.5)}, NULL, NULL, NULL, 'parsed', ${q(date + "T20:05:00")})`);
  sql(`INSERT INTO activities (id, upload_id, workout_id, start_time, date, sport, name, distance_m, duration_s, elapsed_s, avg_hr, max_hr, calories, elevation_gain_m, avg_cadence, avg_pace_s_per_km, best_5k_s, best_1k_s, laps_json, splits_json, hr_zones_json, track_json, created_at)
       VALUES (${activityId++}, ${uid}, ${wid}, ${q(start)}, ${q(date)}, 'running', ${q(name)}, ${Math.round(km * 1000)}, ${acc}, ${acc + 40}, ${Math.round(avgHr)}, ${Math.round(avgHr + 18)}, ${Math.round(km * 68)}, ${Math.round(30 + km * 6)}, ${Math.round(166 + jitter(4))}, ${Math.round(acc / km)}, ${km >= 5 ? Math.round(5 * paceSec - (kind === "tt" ? 10 : 8)) : "NULL"}, ${Math.round(Math.min(...splits.filter((s) => s.distance_m === 1000).map((s) => s.seconds)))}, '[]', ${q(JSON.stringify(splits))}, ${q(JSON.stringify(hrZones))}, ${q(JSON.stringify(track))}, ${q(date + "T20:05:00")})`);
  return { total, acc };
}

const liftNotes = [
  null, "Knees felt good. Squat bar speed better on the last set.", null, "Short on sleep, kept the loads and cut the jumps short.",
  null, "Deload week. Everything light and fast.", "Best session so far, pull-ups felt easy.", null, "Grip was the limit on the carry.",
  null, "Left ankle a bit stiff in the hops, fine after warm-up.", null,
];
let noteIdx = 0;

const fiveKTrial = 1530; // 25:30 in week 1
let easyPace = 372; // 6:12 per km in week 1
let intervalBasePace = 345;

for (let week = 1; week <= SAMPLE_WEEKS; week++) {
  const monday = addDays(SAMPLE_START, (week - 1) * 7);
  const phase = phaseFor(week);
  for (let d = 0; d < 7; d++) {
    const date = addDays(monday, d);
    let key = scheduledTemplateKey(date, week);
    // Week 5: lift B and the easy run swapped (he lifted on Thursday that week).
    if (week === 5 && d === 2) key = "easy_run";
    if (week === 5 && d === 3) key = "lift_b";
    const t = PROGRAM.templates[key];
    if (t.kind === "rest") {
      if (week === 3 && d === 5) {
        insertWorkout({ date, template_key: "other", kind: "other", status: "done", week, phase, plan_json: null, checklist_json: null, started_at: `${date}T10:30:00`, finished_at: `${date}T13:10:00`, duration_min: 160, distance_km: 9.4, time_sec: null, avg_hr: 118, rpe: 4, notes: "Hike with the baby in the carrier, Esja lower trail." });
      }
      continue;
    }
    if (t.kind === "lift") {
      const skipped = week === 4 && d === 4; // one missed lift C
      const startedAt = `${date}T17:${String(5 + Math.round(rnd() * 40)).padStart(2, "0")}:00`;
      const dur = isDeloadWeek(week) ? 58 + Math.round(jitter(5)) : 78 + Math.round(jitter(9));
      const finishedAt = new Date(new Date(startedAt + "Z").getTime() + dur * 60000).toISOString().replace(/\.\d{3}Z$/, "");
      const wid = insertWorkout({
        date, template_key: key, kind: "lift", status: skipped ? "skipped" : "done", week, phase,
        plan_json: JSON.stringify(buildPlan(key, week)), checklist_json: skipped ? null : checklist(key, week),
        started_at: skipped ? null : startedAt, finished_at: skipped ? null : finishedAt, duration_min: skipped ? null : dur,
        distance_km: null, time_sec: null, avg_hr: null, rpe: skipped ? null : (isDeloadWeek(week) ? 5 : 7 + (rnd() < 0.4 ? 1 : 0)),
        notes: skipped ? "Kids sick, no gym." : liftNotes[noteIdx++ % liftNotes.length],
      });
      if (!skipped) liftSets(wid, key, week, date);
      continue;
    }
    // Runs
    if (key === "time_trial_5k") {
      const timeSec = fiveKTrial;
      const wid = insertWorkout({ date, template_key: key, kind: "run", status: "done", week, phase, plan_json: null, checklist_json: null, started_at: `${date}T18:00:00`, finished_at: `${date}T18:40:00`, duration_min: 40, distance_km: 5.0, time_sec: timeSec, avg_hr: 176, rpe: 9, notes: "Flat loop by the sea. Went out a bit hard." });
      runActivity(wid, date, 18, 5.0, timeSec / 5, 176, "tt");
      sql(`INSERT INTO tests (date, week_no, test_key, value, notes, created_at) VALUES (${q(date)}, ${week}, 'five_k_sec', ${timeSec}, 'Baseline', ${q(date + "T19:00:00")})`);
      const tests = { broad_jump_cm: 226, slh_left_cm: 171, slh_right_cm: 179, shuttle_sec: 5.24, squat_3rm_kg: 95, bench_3rm_kg: 80, deadlift_3rm_kg: 142.5 };
      for (const [k, v] of Object.entries(tests)) sql(`INSERT INTO tests (date, week_no, test_key, value, notes, created_at) VALUES (${q(addDays(date, k.endsWith("3rm_kg") ? 3 : 0))}, ${week}, ${q(k)}, ${v}, 'Baseline', ${q(date + "T19:00:00")})`);
      continue;
    }
    if (key === "easy_run") {
      if (week === 4) { insertWorkout({ date, template_key: key, kind: "run", status: "skipped", week, phase, plan_json: null, checklist_json: null, started_at: null, finished_at: null, duration_min: null, distance_km: null, time_sec: null, avg_hr: null, rpe: null, notes: "Cold, skipped." }); continue; }
      const km = round(5.4 + week * 0.3 + jitter(0.3), 0.1);
      const pace = easyPace - (week - 1) * 4 + jitter(5);
      const timeSec = Math.round(km * pace);
      const wid = insertWorkout({ date, template_key: key, kind: "run", status: "done", week, phase, plan_json: null, checklist_json: null, started_at: `${date}T07:10:00`, finished_at: `${date}T07:${String(10 + Math.round(timeSec / 60) + 4).padStart(2, "0")}:00`, duration_min: Math.round(timeSec / 60) + 4, distance_km: km, time_sec: timeSec, avg_hr: 146 - week, rpe: 4, notes: week === 2 ? "Kept it honest, could talk the whole way." : null });
      runActivity(wid, date, 7, km, pace, 146 - week, "easy");
      continue;
    }
    // Interval sessions
    const km = round(6.2 + week * 0.2 + jitter(0.3), 0.1);
    const pace = intervalBasePace - (week - 1) * 3;
    const timeSec = Math.round(km * pace);
    const wid = insertWorkout({ date, template_key: key, kind: "run", status: "done", week, phase, plan_json: null, checklist_json: null, started_at: `${date}T18:05:00`, finished_at: `${date}T18:${String(5 + Math.round(timeSec / 60) + 6).padStart(2, "0")}:00`, duration_min: Math.round(timeSec / 60) + 6, distance_km: km, time_sec: timeSec, avg_hr: 164 + Math.round(jitter(2)), rpe: 8, notes: week === 6 ? "Deload, only 4 reps." : null });
    runActivity(wid, date, 18, km, pace, 164, "intervals");
  }
}

// Schedule overrides for the week 5 swap so the calendar shows them as moved.
const w5 = addDays(SAMPLE_START, 28);
sql(`INSERT OR REPLACE INTO schedule_overrides (date, template_key, created_at) VALUES (${q(addDays(w5, 2))}, 'easy_run', ${q(addDays(w5, 1) + "T21:00:00")})`);
sql(`INSERT OR REPLACE INTO schedule_overrides (date, template_key, created_at) VALUES (${q(addDays(w5, 3))}, 'lift_b', ${q(addDays(w5, 1) + "T21:00:00")})`);

// Morning weight, three or four mornings a week, drifting from 94.4 towards 92.6 with normal noise.
for (let i = 0; i <= 7 * SAMPLE_WEEKS - 1; i++) {
  const date = addDays(SAMPLE_START, i);
  const wd = i % 7;
  if (![0, 2, 4, 5].includes(wd)) continue;
  if (rnd() < 0.12) continue;
  const trend = 94.4 - (i / (7 * SAMPLE_WEEKS)) * 1.8;
  const kg = Math.round((trend + jitter(0.5) + (wd === 0 ? 0.3 : 0)) * 10) / 10; // Mondays after the weekend run a bit higher
  sql(`INSERT OR REPLACE INTO body_metrics (date, weight_kg, notes, source, created_at, updated_at) VALUES (${q(date)}, ${kg}, NULL, 'manual', ${q(date + "T07:15:00")}, ${q(date + "T07:15:00")})`);
}

// Nutrition, every day, as MyFitnessPal would export it. Weekends run higher (beer, dessert).
const MEALS = ["Breakfast", "Lunch", "Dinner", "Snacks"];
for (let i = 0; i <= 7 * SAMPLE_WEEKS - 1; i++) {
  const date = addDays(SAMPLE_START, i);
  const wd = i % 7;
  const weekend = wd >= 5;
  const cal = Math.round(weekend ? 2750 + jitter(300) : 2250 + jitter(200));
  const protein = Math.round(weekend ? 150 + jitter(20) : 172 + jitter(18));
  const fat = Math.round(cal * (weekend ? 0.33 : 0.28) / 9);
  const carbs = Math.round((cal - protein * 4 - fat * 9) / 4);
  const share = [0.22, 0.3, 0.36, 0.12];
  const meals = MEALS.map((m, k) => ({ meal: m, calories: Math.round(cal * share[k]), protein_g: Math.round(protein * share[k]), carbs_g: Math.round(carbs * share[k]), fat_g: Math.round(fat * share[k]), fiber_g: Math.round(8 * share[k] * 4) / 4, sugar_g: Math.round(60 * share[k]), sodium_mg: Math.round(2600 * share[k]), note: weekend && m === "Snacks" ? "2 beers, ice cream" : null }));
  sql(`INSERT OR REPLACE INTO nutrition_days (date, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, meals_json, source, upload_id, updated_at)
       VALUES (${q(date)}, ${cal}, ${protein}, ${carbs}, ${fat}, ${Math.round(26 + jitter(6))}, ${Math.round(weekend ? 95 : 58)}, ${Math.round(2600 + jitter(400))}, ${q(JSON.stringify(meals))}, 'myfitnesspal', NULL, ${q(date + "T22:00:00")})`);
}

// A report, as Claude would post one after reading the export.
const report = `## Weeks 1 to 6

**Weight.** 7-day average down from 94.3 kg to 92.7 kg, about 0.27 kg a week. That is the slow end of the target range and fine for keeping strength. Mondays run 0.3 to 0.5 kg higher than Fridays, which is the weekend food and beer, not fat.

**Lifting.** Back squat 75 kg to 87.5 kg for 5s, deadlift 120 kg to 145 kg for 4s, both with reps in reserve. Pull-ups went from 7 to 9 reps. Dumbbell bench stalled at 30 kg per hand in week 4 and 5; drop to 28 kg for 8s next block and build back up.

**Running.** 5 km baseline 25:30. Easy run pace drifted from 6:12 to 5:55 per km at the same heart rate, which is the aerobic gain showing. Intervals are on schedule. Expect 24:00 to 24:30 in the week 8 time trial.

**Adherence.** 27 of 29 planned sessions. One lift and one easy run missed in week 4 (sick kids). No change needed.

**Next block.** Phase 3 jumps start now: keep contacts to 80 per session and stop jumping the moment the landings get noisy. Protein averaged 168 g on weekdays and 148 g at weekends; a weekend target of 160 g would help keep the deficit while the beer stays.`;
sql(`INSERT INTO reports (title, date, body_md, author, created_at) VALUES ('[Sample] Weeks 1 to 6 review', ${q(SAMPLE_END)}, ${q(report)}, 'claude', ${q(SAMPLE_END + "T21:30:00")})`);

process.stdout.write(out.join("\n") + "\n");
