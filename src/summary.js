// Builds a compact Markdown summary of all data, meant to be pasted into the Claude project for analysis.
import { PROGRAM, resolveDay, exerciseFor, templateFor, e1rm, fmtTime, fmtPace, mondayOf, addDays, weekNumber } from "../public/js/program.js";

function avg(arr) { const v = arr.filter((x) => typeof x === "number" && !isNaN(x)); return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null; }
function r1(x) { return x == null ? "" : (Math.round(x * 10) / 10).toString(); }
function r0(x) { return x == null ? "" : Math.round(x).toString(); }

export async function buildSummaryMarkdown(env, settings, date) {
  const q = async (sql, ...binds) => (await env.DB.prepare(sql).bind(...binds).all()).results;
  const today = resolveDay(date, settings);
  const start = settings.program_start_date;
  const workouts = await q("SELECT * FROM workouts ORDER BY date, id");
  const sets = await q("SELECT s.*, w.date FROM sets s JOIN workouts w ON w.id = s.workout_id WHERE s.done = 1 ORDER BY w.date, s.workout_id, s.exercise_key, s.set_index");
  const body = await q("SELECT * FROM body_metrics ORDER BY date");
  const tests = await q("SELECT * FROM tests ORDER BY date");
  const activities = await q("SELECT * FROM activities ORDER BY COALESCE(date, start_time)");
  const nutrition = await q("SELECT * FROM nutrition_days ORDER BY date");
  const blockNotes = await q("SELECT n.workout_id, n.block, n.note, w.date, w.template_key FROM workout_notes n JOIN workouts w ON w.id = n.workout_id ORDER BY w.date, n.id");

  const lines = [];
  lines.push(`# Fitness data summary`);
  lines.push(``);
  lines.push(`Generated ${date}. Program "${PROGRAM.name}" started ${start}. Today is week ${today.week}, phase ${today.phase} (${today.phaseName}).`);
  lines.push(`Goal: ${PROGRAM.body.startWeightKg} kg to ${settings.goal_weight_kg || PROGRAM.body.goalWeightKg} kg. Targets: ${settings.calorie_target || PROGRAM.nutrition.calories} kcal, ${settings.protein_target || PROGRAM.nutrition.proteinG} g protein a day, 5 km under ${fmtTime(settings.five_k_target_sec || PROGRAM.running.fiveKTargetSec)}.`);
  lines.push(``);

  // Body weight by week
  lines.push(`## Body weight`);
  const manual = body.filter((b) => b.weight_kg != null);
  if (!manual.length) lines.push(`No weigh-ins logged yet.`);
  else {
    const byWeek = new Map();
    for (const b of manual) { const wk = weekNumber(b.date, start); const arr = byWeek.get(wk) || []; arr.push(b.weight_kg); byWeek.set(wk, arr); }
    lines.push(`| Week | Avg kg | Weigh-ins |`); lines.push(`| --- | --- | --- |`);
    for (const [wk, arr] of [...byWeek.entries()].sort((a, b) => a[0] - b[0])) lines.push(`| ${wk} | ${r1(avg(arr))} | ${arr.length} |`);
    const last = manual[manual.length - 1];
    lines.push(``);
    lines.push(`Latest: ${last.weight_kg} kg on ${last.date}. First logged: ${manual[0].weight_kg} kg on ${manual[0].date}.`);
  }
  lines.push(``);

  // Adherence by week
  lines.push(`## Sessions by week`);
  const done = workouts.filter((w) => w.status === "done" && w.kind !== "rest");
  if (!done.length) lines.push(`No sessions finished yet.`);
  else {
    const weeks = new Map();
    for (const w of done) { const wk = weekNumber(w.date, start); const arr = weeks.get(wk) || []; arr.push(w); weeks.set(wk, arr); }
    lines.push(`| Week | Done | Sessions |`); lines.push(`| --- | --- | --- |`);
    for (const [wk, arr] of [...weeks.entries()].sort((a, b) => a[0] - b[0])) {
      lines.push(`| ${wk} | ${arr.length} of 5 | ${arr.map((w) => `${w.date.slice(5)} ${templateFor(w.template_key).name}${w.rpe ? ` (RPE ${w.rpe})` : ""}`).join(", ")} |`);
    }
  }
  lines.push(``);

  // Lifts
  lines.push(`## Lifts`);
  const byEx = new Map();
  for (const s of sets) { const arr = byEx.get(s.exercise_key) || []; arr.push(s); byEx.set(s.exercise_key, arr); }
  if (!byEx.size) lines.push(`No sets logged yet.`);
  else {
    lines.push(`| Exercise | Sessions | First | Latest | Best est. 1RM |`); lines.push(`| --- | --- | --- | --- | --- |`);
    for (const [key, arr] of byEx.entries()) {
      const ex = exerciseFor(key);
      const sessions = new Map();
      for (const s of arr) { const list = sessions.get(s.date) || []; list.push(s); sessions.set(s.date, list); }
      const dates = [...sessions.keys()].sort();
      const describe = (list) => {
        if (ex.fields[0] === "reps") return list.map((s) => `${s.reps ?? 0}${s.weight_kg ? `(+${s.weight_kg})` : ""}`).join(", ");
        if (ex.fields.includes("kg") && ex.fields.includes("reps")) return list.map((s) => `${s.weight_kg ?? 0}×${s.reps ?? 0}`).join(", ");
        if (ex.fields.includes("seconds")) return list.map((s) => `${s.seconds ?? 0}s`).join(", ");
        if (ex.fields.includes("meters")) return list.map((s) => `${s.weight_kg ?? 0}kg×${s.distance_m ?? 0}m`).join(", ");
        return list.map((s) => `${s.reps ?? 0}${s.weight_kg ? `(+${s.weight_kg})` : ""}`).join(", ");
      };
      let best = null;
      if (ex.e1rm) for (const s of arr) { const v = e1rm(s.weight_kg, s.reps); if (v && (best == null || v > best)) best = v; }
      lines.push(`| ${ex.short || ex.name} | ${dates.length} | ${dates[0].slice(5)}: ${describe(sessions.get(dates[0]))} | ${dates[dates.length - 1].slice(5)}: ${describe(sessions.get(dates[dates.length - 1]))} | ${best ? r1(best) + " kg" : ""} |`);
    }
  }
  lines.push(``);

  // Runs
  lines.push(`## Runs`);
  const runs = workouts.filter((w) => w.kind === "run" && w.status !== "skipped" && (w.distance_km || w.time_sec));
  if (!runs.length && !activities.length) lines.push(`No runs logged yet.`);
  else {
    lines.push(`| Date | Session | km | Time | Pace | Avg HR | Garmin best 5k |`); lines.push(`| --- | --- | --- | --- | --- | --- | --- |`);
    for (const w of runs.slice(-20)) {
      const act = activities.filter((a) => a.workout_id === w.id).pop();
      const pace = w.distance_km && w.time_sec ? fmtPace(w.time_sec / w.distance_km) : "";
      lines.push(`| ${w.date} | ${templateFor(w.template_key).name}${w.template_key.startsWith("intervals") ? " " + templateFor(w.template_key).subtitle : ""} | ${r1(w.distance_km)} | ${fmtTime(w.time_sec)} | ${pace} | ${w.avg_hr || (act && act.avg_hr) || ""} | ${act && act.best_5k_s ? fmtTime(act.best_5k_s) : ""} |`);
    }
    const orphan = activities.filter((a) => !a.workout_id);
    if (orphan.length) lines.push(`\n${orphan.length} Garmin activities are not attached to a session.`);
  }
  lines.push(``);

  // Tests
  lines.push(`## Performance tests`);
  if (!tests.length) lines.push(`No tests logged yet (planned for weeks 1, 8 and 16).`);
  else {
    lines.push(`| Date | Week | Test | Value |`); lines.push(`| --- | --- | --- | --- |`);
    for (const t of tests) {
      const def = PROGRAM.tests.find((x) => x.key === t.test_key) || { name: t.test_key, unit: "" };
      lines.push(`| ${t.date} | ${t.week_no ?? ""} | ${def.name} | ${def.input === "time" ? fmtTime(t.value) : `${t.value} ${def.unit}`} |`);
    }
  }
  lines.push(``);

  // Notes on exercises and blocks
  if (blockNotes.length) {
    lines.push(`## Exercise notes`);
    const recent = blockNotes.slice(-60);
    for (const n of recent) {
      const label = ["warmup", "jumps", "finisher"].includes(n.block) ? (n.block === "warmup" ? "Warm-up" : n.block === "jumps" ? "Jumps" : "Finisher") : exerciseFor(n.block).name;
      lines.push(`- ${n.date} ${templateFor(n.template_key).name}, ${label}: ${n.note.replace(/\s+/g, " ")}`);
    }
    lines.push(``);
  }

  // Nutrition
  lines.push(`## Nutrition (MyFitnessPal)`);
  if (!nutrition.length) lines.push(`No nutrition data uploaded yet.`);
  else {
    const byWeek = new Map();
    for (const n of nutrition) { const wk = weekNumber(n.date, start); const arr = byWeek.get(wk) || []; arr.push(n); byWeek.set(wk, arr); }
    lines.push(`| Week | Days | Avg kcal | Avg protein g | Avg carbs g | Avg fat g | Avg sugar g |`); lines.push(`| --- | --- | --- | --- | --- | --- | --- |`);
    for (const [wk, arr] of [...byWeek.entries()].sort((a, b) => a[0] - b[0])) {
      lines.push(`| ${wk} | ${arr.length} | ${r0(avg(arr.map((n) => n.calories)))} | ${r0(avg(arr.map((n) => n.protein_g)))} | ${r0(avg(arr.map((n) => n.carbs_g)))} | ${r0(avg(arr.map((n) => n.fat_g)))} | ${r0(avg(arr.map((n) => n.sugar_g)))} |`);
    }
  }
  lines.push(``);

  // Notes
  const noted = workouts.filter((w) => w.notes).slice(-15);
  if (noted.length) {
    lines.push(`## Recent session notes`);
    for (const w of noted) lines.push(`- ${w.date} ${templateFor(w.template_key).name}: ${w.notes.replace(/\s+/g, " ").slice(0, 300)}`);
    lines.push(``);
  }
  return lines.join("\n");
}
