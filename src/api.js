// JSON API. All routes here require auth (checked in index.js).
import { PROGRAM, resolveDay, templateFor, buildPlan, mondayOf, addDays, daysBetween, todayLocal, weekNumber, phaseForWeek, scheduledTemplateKey } from "../public/js/program.js";
import { getSettings, setSettings, getOverrides, ensureWorkout, rowWithJson, WORKOUT_FIELDS, num, gzip, gunzip, blobToBytes, toArrayBuffer, b64encode } from "./db.js";
import { parseUpload } from "./parsers/index.js";
import { buildSummaryMarkdown } from "./summary.js";

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const CLIENT_ID_RE = /^[A-Za-z0-9_-]{6,80}$/;
const MAX_RAW_GZ = 1_800_000; // D1 row limit is 2 MB
const SETTING_KEYS = new Set(["program_start_date", "phase_override", "goal_weight_kg", "calorie_target", "protein_target", "max_hr", "five_k_target_sec", "fun_budget_kcal", "display_name"]);

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers } });
}
class HttpError extends Error { constructor(status, message) { super(message); this.status = status; } }
function bad(msg) { throw new HttpError(400, msg); }
function assertDate(d) { if (!DATE_RE.test(d || "")) bad("Bad date, expected YYYY-MM-DD"); return d; }
async function readJson(request) { try { return (await request.json()) || {}; } catch { bad("Invalid JSON body"); } }
function placeholders(n) { return Array(n).fill("?").join(","); }

export async function handleApi(request, env, ctx, url) {
  const method = request.method;
  const parts = url.pathname.replace(/^\/api\/?/, "").split("/").filter(Boolean);
  const p = parts.map(decodeURIComponent);
  try {
    const settings = await getSettings(env);
    const r = await route(method, p, request, env, url, settings);
    if (r instanceof Response) return r;
    return json(r);
  } catch (e) {
    if (e instanceof HttpError) return json({ error: e.message }, e.status);
    console.error("API error", e);
    return json({ error: e.message || String(e) }, 500);
  }
}

async function route(method, p, request, env, url, settings) {
  const [a, b, c] = p;

  if (a === "program" && method === "GET") return { program: PROGRAM, settings, today: resolveDay(url.searchParams.get("date") || todayLocal(), settings) };

  if (a === "settings") {
    if (method === "GET") return settings;
    if (method === "PUT" || method === "PATCH") {
      const body = await readJson(request);
      const clean = {};
      for (const [k, v] of Object.entries(body)) {
        if (!SETTING_KEYS.has(k)) bad(`Unknown setting ${k}`);
        if (k === "program_start_date" && v) assertDate(v);
        clean[k] = v;
      }
      await setSettings(env, clean);
      return getSettings(env);
    }
  }

  if (a === "schedule") {
    // Planned sessions per day, with overrides. Lets the calendar show a date range and lets sessions move.
    if (!b && method === "GET") {
      const from = assertDate(url.searchParams.get("from")), to = assertDate(url.searchParams.get("to"));
      if (daysBetween(from, to) < 0 || daysBetween(from, to) > 120) bad("Range must be 0 to 120 days");
      return getSchedule(env, settings, from, to);
    }
    if (b === "swap" && method === "POST") {
      const body = await readJson(request);
      const da = assertDate(body.a), db = assertDate(body.b);
      if (da === db) bad("Pick two different days");
      const ka = resolveDay(da, settings).templateKey, kb = resolveDay(db, settings).templateKey;
      await setOverride(env, da, kb, settings);
      await setOverride(env, db, ka, settings);
      await pruneEmptyWorkout(env, da, ka);
      await pruneEmptyWorkout(env, db, kb);
      settings.overrides = await getOverrides(env);
      return { a: resolveDay(da, settings), b: resolveDay(db, settings) };
    }
    if (b && b !== "swap" && (method === "PUT" || method === "DELETE")) {
      const date = assertDate(b);
      const body = method === "DELETE" ? {} : await readJson(request);
      const key = body.template_key || null;
      if (key && !PROGRAM.templates[key]) bad("Unknown template");
      const before = resolveDay(date, settings).templateKey;
      await setOverride(env, date, key, settings);
      settings.overrides = await getOverrides(env);
      const after = resolveDay(date, settings);
      if (after.templateKey !== before) await pruneEmptyWorkout(env, date, before);
      return after;
    }
  }

  if (a === "day" && b) {
    const date = assertDate(b);
    if (!c && method === "GET") return getDay(env, date, settings);
    if (c === "workout" && (method === "PUT" || method === "POST")) return upsertDayWorkout(env, date, await readJson(request), settings);
  }

  if (a === "sets" && b) {
    if (!CLIENT_ID_RE.test(b)) bad("Bad set id");
    if (method === "PUT" || method === "POST") return upsertSet(env, b, await readJson(request), settings);
    if (method === "DELETE") {
      const row = await env.DB.prepare("SELECT workout_id FROM sets WHERE client_id = ?").bind(b).first();
      await env.DB.prepare("DELETE FROM sets WHERE client_id = ?").bind(b).run();
      if (row) await env.DB.prepare("UPDATE workouts SET updated_at = datetime('now') WHERE id = ?").bind(row.workout_id).run();
      return { ok: true };
    }
  }

  if (a === "workouts") {
    if (!b && method === "GET") return listWorkouts(env, url);
    if (b && method === "GET") return getWorkout(env, Number(b));
    if (b && (method === "PATCH" || method === "PUT")) return patchWorkout(env, Number(b), await readJson(request));
    if (b && method === "DELETE") {
      await env.DB.prepare("DELETE FROM sets WHERE workout_id = ?").bind(Number(b)).run();
      await env.DB.prepare("UPDATE activities SET workout_id = NULL WHERE workout_id = ?").bind(Number(b)).run();
      await env.DB.prepare("UPDATE uploads SET workout_id = NULL WHERE workout_id = ?").bind(Number(b)).run();
      await env.DB.prepare("DELETE FROM workouts WHERE id = ?").bind(Number(b)).run();
      return { ok: true };
    }
  }

  if (a === "body") {
    if (!b && method === "GET") {
      const { results } = await env.DB.prepare("SELECT * FROM body_metrics ORDER BY date DESC LIMIT 1000").all();
      return results;
    }
    if (!b && (method === "PUT" || method === "POST")) {
      const body = await readJson(request);
      const date = assertDate(body.date);
      const w = num(body.weight_kg);
      if (w == null && !body.notes) {
        await env.DB.prepare("DELETE FROM body_metrics WHERE date = ? AND source = 'manual'").bind(date).run();
        return { ok: true, deleted: true };
      }
      if (w != null && (w < 30 || w > 300)) bad("Weight out of range");
      await env.DB.prepare(
        `INSERT INTO body_metrics (date, weight_kg, notes, source) VALUES (?, ?, ?, 'manual')
         ON CONFLICT(date, source) DO UPDATE SET weight_kg = excluded.weight_kg, notes = excluded.notes, updated_at = datetime('now')`
      ).bind(date, w, body.notes || null).run();
      return env.DB.prepare("SELECT * FROM body_metrics WHERE date = ? AND source = 'manual'").bind(date).first();
    }
    if (b && method === "DELETE") { await env.DB.prepare("DELETE FROM body_metrics WHERE id = ?").bind(Number(b)).run(); return { ok: true }; }
  }

  if (a === "tests") {
    if (!b && method === "GET") { const { results } = await env.DB.prepare("SELECT * FROM tests ORDER BY date").all(); return results; }
    if (!b && (method === "PUT" || method === "POST")) {
      const body = await readJson(request);
      const date = assertDate(body.date);
      if (!PROGRAM.tests.some((t) => t.key === body.test_key)) bad("Unknown test");
      const v = num(body.value);
      if (v == null) { await env.DB.prepare("DELETE FROM tests WHERE date = ? AND test_key = ?").bind(date, body.test_key).run(); return { ok: true, deleted: true }; }
      const week = weekNumber(date, settings.program_start_date);
      await env.DB.prepare(
        `INSERT INTO tests (date, week_no, test_key, value, notes) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(date, test_key) DO UPDATE SET value = excluded.value, notes = excluded.notes, week_no = excluded.week_no`
      ).bind(date, week, body.test_key, v, body.notes || null).run();
      return env.DB.prepare("SELECT * FROM tests WHERE date = ? AND test_key = ?").bind(date, body.test_key).first();
    }
    if (b && method === "DELETE") { await env.DB.prepare("DELETE FROM tests WHERE id = ?").bind(Number(b)).run(); return { ok: true }; }
  }

  if (a === "uploads") {
    if (!b && method === "POST") return handleUpload(request, env, settings);
    if (!b && method === "GET") {
      const { results } = await env.DB.prepare(
        `SELECT u.id, u.workout_id, u.source, u.format, u.filename, u.size_bytes, u.parse_status, u.parse_error, u.uploaded_at, w.date AS workout_date, w.template_key,
                (SELECT COUNT(*) FROM activities a WHERE a.upload_id = u.id) AS activity_count
         FROM uploads u LEFT JOIN workouts w ON w.id = u.workout_id ORDER BY u.uploaded_at DESC, u.id DESC LIMIT 500`
      ).all();
      return results;
    }
    if (b && c === "raw" && method === "GET") {
      const row = await env.DB.prepare("SELECT filename, content_type, raw, raw_encoding FROM uploads WHERE id = ?").bind(Number(b)).first();
      if (!row || !row.raw) throw new HttpError(404, "No raw file stored");
      let bytes = blobToBytes(row.raw);
      if (row.raw_encoding === "gzip") bytes = await gunzip(bytes);
      return new Response(bytes, { headers: { "Content-Type": row.content_type || "application/octet-stream", "Content-Disposition": `attachment; filename="${(row.filename || "upload").replace(/"/g, "")}"` } });
    }
    if (b && method === "GET") {
      const row = await env.DB.prepare("SELECT id, workout_id, source, format, filename, content_type, size_bytes, parsed_json, parse_status, parse_error, uploaded_at FROM uploads WHERE id = ?").bind(Number(b)).first();
      if (!row) throw new HttpError(404, "Not found");
      return rowWithJson(row, ["parsed_json"]);
    }
    if (b && (method === "PATCH" || method === "PUT")) {
      const body = await readJson(request);
      const wid = body.workout_id == null ? null : Number(body.workout_id);
      if (wid != null && !(await env.DB.prepare("SELECT id FROM workouts WHERE id = ?").bind(wid).first())) bad(`Unknown workout_id ${wid}`);
      await env.DB.prepare("UPDATE uploads SET workout_id = ? WHERE id = ?").bind(wid, Number(b)).run();
      await env.DB.prepare("UPDATE activities SET workout_id = ? WHERE upload_id = ?").bind(wid, Number(b)).run();
      if (wid) await fillWorkoutFromActivities(env, wid);
      return { ok: true };
    }
    if (b && method === "DELETE") {
      await env.DB.prepare("DELETE FROM activities WHERE upload_id = ?").bind(Number(b)).run();
      await env.DB.prepare("UPDATE nutrition_days SET upload_id = NULL WHERE upload_id = ?").bind(Number(b)).run();
      await env.DB.prepare("DELETE FROM uploads WHERE id = ?").bind(Number(b)).run();
      return { ok: true };
    }
  }

  if (a === "activities") {
    if (!b && method === "GET") {
      const { results } = await env.DB.prepare("SELECT id, upload_id, workout_id, start_time, date, sport, name, distance_m, duration_s, elapsed_s, avg_hr, max_hr, calories, elevation_gain_m, avg_cadence, avg_pace_s_per_km, best_5k_s, best_1k_s FROM activities ORDER BY COALESCE(date, start_time) DESC LIMIT 1000").all();
      return results;
    }
    if (b && method === "GET") {
      const row = await env.DB.prepare("SELECT * FROM activities WHERE id = ?").bind(Number(b)).first();
      if (!row) throw new HttpError(404, "Not found");
      return rowWithJson(row, ["laps_json", "splits_json", "hr_zones_json", "track_json"]);
    }
    if (b && (method === "PATCH" || method === "PUT")) {
      const body = await readJson(request);
      const wid = body.workout_id == null ? null : Number(body.workout_id);
      if (wid != null && !(await env.DB.prepare("SELECT id FROM workouts WHERE id = ?").bind(wid).first())) bad(`Unknown workout_id ${wid}`);
      await env.DB.prepare("UPDATE activities SET workout_id = ? WHERE id = ?").bind(wid, Number(b)).run();
      if (wid) await fillWorkoutFromActivities(env, wid);
      return { ok: true };
    }
    if (b && method === "DELETE") { await env.DB.prepare("DELETE FROM activities WHERE id = ?").bind(Number(b)).run(); return { ok: true }; }
  }

  if (a === "nutrition") {
    if (!b && method === "GET") { const { results } = await env.DB.prepare("SELECT * FROM nutrition_days ORDER BY date DESC LIMIT 1000").all(); return results.map((r) => rowWithJson(r, ["meals_json"])); }
    if (!b && (method === "PUT" || method === "POST")) {
      const body = await readJson(request);
      const date = assertDate(body.date);
      await upsertNutritionDay(env, { ...body, date, source: "manual" }, null);
      return env.DB.prepare("SELECT * FROM nutrition_days WHERE date = ?").bind(date).first();
    }
    if (b && method === "DELETE") { await env.DB.prepare("DELETE FROM nutrition_days WHERE id = ?").bind(Number(b)).run(); return { ok: true }; }
  }

  if (a === "reports") {
    if (!b && method === "GET") { const { results } = await env.DB.prepare("SELECT id, title, date, author, created_at, substr(body_md, 1, 240) AS preview FROM reports ORDER BY COALESCE(date, created_at) DESC, id DESC").all(); return results; }
    if (!b && method === "POST") {
      const body = await readJson(request);
      if (!body.title || !body.body_md) bad("title and body_md are required");
      const res = await env.DB.prepare("INSERT INTO reports (title, date, body_md, author) VALUES (?, ?, ?, ?)").bind(String(body.title).slice(0, 200), body.date || todayLocal(), String(body.body_md), body.author || "claude").run();
      return env.DB.prepare("SELECT * FROM reports WHERE id = ?").bind(res.meta.last_row_id).first();
    }
    if (b && method === "GET") { const row = await env.DB.prepare("SELECT * FROM reports WHERE id = ?").bind(Number(b)).first(); if (!row) throw new HttpError(404, "Not found"); return row; }
    if (b && method === "DELETE") { await env.DB.prepare("DELETE FROM reports WHERE id = ?").bind(Number(b)).run(); return { ok: true }; }
  }

  if (a === "dashboard" && method === "GET") return getDashboard(env, settings, url.searchParams.get("date") || todayLocal());
  if (a === "export.json" && method === "GET") return exportAll(env, settings, url.searchParams.get("include") === "raw");
  if (a === "summary.md" && method === "GET") {
    const md = await buildSummaryMarkdown(env, settings, url.searchParams.get("date") || todayLocal());
    return new Response(md, { headers: { "Content-Type": "text/markdown; charset=utf-8", "Cache-Control": "no-store" } });
  }
  if (a === "whoami" && method === "GET") return { ok: true };

  throw new HttpError(404, `No route for ${method} /api/${p.join("/")}`);
}

// ---------- day ----------
async function lastSetsFor(env, keys, beforeDate) {
  const out = {};
  if (!keys.length) return out;
  const stmts = keys.map((k) =>
    env.DB.prepare(
      `SELECT s.exercise_key, s.set_index, s.weight_kg, s.reps, s.seconds, s.distance_m, s.rpe, w.date, w.id AS workout_id
       FROM sets s JOIN workouts w ON w.id = s.workout_id
       WHERE s.exercise_key = ? AND w.date < ? AND w.id = (
         SELECT w2.id FROM workouts w2 JOIN sets s2 ON s2.workout_id = w2.id
         WHERE s2.exercise_key = ? AND w2.date < ? ORDER BY w2.date DESC, w2.id DESC LIMIT 1)
       ORDER BY s.set_index, s.id`
    ).bind(k, beforeDate, k, beforeDate)
  );
  const results = await env.DB.batch(stmts);
  results.forEach((r, i) => {
    const rows = r.results || [];
    if (rows.length) out[keys[i]] = { date: rows[0].date, workout_id: rows[0].workout_id, sets: rows.map(({ set_index, weight_kg, reps, seconds, distance_m, rpe }) => ({ set_index, weight_kg, reps, seconds, distance_m, rpe })) };
  });
  return out;
}

async function getDay(env, date, settings) {
  const day = resolveDay(date, settings);
  const { results: wrows } = await env.DB.prepare("SELECT * FROM workouts WHERE date = ? ORDER BY id").bind(date).all();
  const ids = wrows.map((w) => w.id);
  let sets = [], activities = [];
  if (ids.length) {
    sets = (await env.DB.prepare(`SELECT * FROM sets WHERE workout_id IN (${placeholders(ids.length)}) ORDER BY exercise_key, set_index, id`).bind(...ids).all()).results;
    activities = (await env.DB.prepare(`SELECT id, upload_id, workout_id, start_time, sport, name, distance_m, duration_s, avg_hr, max_hr, avg_pace_s_per_km, best_5k_s, calories, elevation_gain_m FROM activities WHERE workout_id IN (${placeholders(ids.length)})`).bind(...ids).all()).results;
  }
  const workouts = wrows.map((w) => ({ ...rowWithJson(w, ["plan_json", "checklist_json"]), sets: sets.filter((s) => s.workout_id === w.id), activities: activities.filter((x) => x.workout_id === w.id) }));
  const active = workouts.find((w) => w.template_key === day.templateKey) || workouts.find((w) => w.status !== "skipped") || null;
  const keys = new Set(day.plan.map((e) => e.key));
  for (const w of workouts) for (const e of w.plan || []) keys.add(e.key);
  const last = await lastSetsFor(env, [...keys], date);
  const body = await env.DB.prepare("SELECT * FROM body_metrics WHERE date = ? AND source = 'manual'").bind(date).first();
  const monday = mondayOf(date), sunday = addDays(monday, 6);
  const tests = day.testWeek ? (await env.DB.prepare("SELECT * FROM tests WHERE date BETWEEN ? AND ?").bind(monday, sunday).all()).results : [];
  const weekRows = (await env.DB.prepare("SELECT id, date, template_key, kind, status FROM workouts WHERE date BETWEEN ? AND ?").bind(monday, sunday).all()).results;
  const week = [];
  for (let i = 0; i < 7; i++) {
    const d = addDays(monday, i);
    const r = resolveDay(d, settings);
    week.push({ date: d, templateKey: r.templateKey, kind: r.template.kind, name: r.template.name, moved: r.moved, workouts: weekRows.filter((w) => w.date === d) });
  }
  return { day, workouts, active, last, body, tests, week, today: todayLocal() };
}

// ---------- schedule ----------
async function setOverride(env, date, key, settings) {
  const def = scheduledTemplateKey(date, Math.max(weekNumber(date, settings.program_start_date), 1));
  if (!key || key === def) await env.DB.prepare("DELETE FROM schedule_overrides WHERE date = ?").bind(date).run();
  else await env.DB.prepare("INSERT INTO schedule_overrides (date, template_key) VALUES (?, ?) ON CONFLICT(date) DO UPDATE SET template_key = excluded.template_key, created_at = datetime('now')").bind(date, key).run();
}

// A workout row that was created by opening the day but never used is removed when the session moves away.
async function pruneEmptyWorkout(env, date, templateKey) {
  const w = await env.DB.prepare("SELECT id FROM workouts WHERE date = ? AND template_key = ? AND status = 'in_progress' AND notes IS NULL AND time_sec IS NULL AND distance_km IS NULL AND rpe IS NULL AND checklist_json IS NULL AND NOT EXISTS (SELECT 1 FROM sets s WHERE s.workout_id = workouts.id) AND NOT EXISTS (SELECT 1 FROM activities a WHERE a.workout_id = workouts.id) AND NOT EXISTS (SELECT 1 FROM uploads u WHERE u.workout_id = workouts.id)").bind(date, templateKey).first();
  if (w) await env.DB.prepare("DELETE FROM workouts WHERE id = ?").bind(w.id).run();
}

async function getSchedule(env, settings, from, to) {
  const { results: rows } = await env.DB.prepare(
    `SELECT w.id, w.date, w.template_key, w.kind, w.status, w.distance_km, w.time_sec, w.rpe,
            (SELECT COUNT(*) FROM sets s WHERE s.workout_id = w.id AND s.done = 1) AS set_count
     FROM workouts w WHERE w.date BETWEEN ? AND ? ORDER BY w.date, w.id`).bind(from, to).all();
  const days = [];
  for (let d = from; d <= to; d = addDays(d, 1)) {
    const r = resolveDay(d, settings);
    days.push({ date: d, week: r.week, templateKey: r.templateKey, defaultTemplateKey: r.defaultTemplateKey, moved: r.moved, kind: r.template.kind, name: r.template.name, subtitle: r.template.subtitle, deload: r.deload, testWeek: r.testWeek, workouts: rows.filter((w) => w.date === d) });
  }
  return { from, to, today: todayLocal(), days };
}

async function upsertDayWorkout(env, date, body, settings) {
  const day = resolveDay(date, settings);
  const templateKey = body.template_key || day.templateKey;
  if (!PROGRAM.templates[templateKey]) bad("Unknown template");
  const w = await ensureWorkout(env, date, templateKey, settings);
  const sets = [], vals = [];
  for (const f of WORKOUT_FIELDS) {
    if (f in body) {
      let v = body[f];
      if (["distance_km", "time_sec", "avg_hr", "rpe", "duration_min"].includes(f)) v = num(v);
      if (f === "status" && !["in_progress", "done", "skipped"].includes(v)) bad("Bad status");
      sets.push(`${f} = ?`); vals.push(v);
    }
  }
  if ("checklist" in body) { sets.push("checklist_json = ?"); vals.push(body.checklist ? JSON.stringify(body.checklist) : null); }
  if ("plan" in body) { sets.push("plan_json = ?"); vals.push(Array.isArray(body.plan) ? JSON.stringify(body.plan) : null); }
  if (body.status === "done" && !body.finished_at && !w.finished_at) { sets.push("finished_at = datetime('now')"); }
  if (body.status === "in_progress") { sets.push("finished_at = NULL"); }
  if (sets.length) {
    sets.push("updated_at = datetime('now')");
    await env.DB.prepare(`UPDATE workouts SET ${sets.join(", ")} WHERE id = ?`).bind(...vals, w.id).run();
  }
  return getWorkout(env, w.id);
}

async function upsertSet(env, clientId, body, settings) {
  const date = assertDate(body.date);
  const templateKey = body.template_key || resolveDay(date, settings).templateKey;
  if (!PROGRAM.templates[templateKey]) bad("Unknown template");
  if (!body.exercise_key || typeof body.exercise_key !== "string" || body.exercise_key.length > 80) bad("exercise_key required");
  const w = await ensureWorkout(env, date, templateKey, settings);
  const weight = num(body.weight_kg), reps = num(body.reps), seconds = num(body.seconds), dist = num(body.distance_m), rpe = num(body.rpe);
  if (weight != null && (weight < 0 || weight > 600)) bad("Weight out of range");
  if (reps != null && (reps < 0 || reps > 500)) bad("Reps out of range");
  await env.DB.prepare(
    `INSERT INTO sets (client_id, workout_id, exercise_key, set_index, weight_kg, reps, seconds, distance_m, rpe, done)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(client_id) DO UPDATE SET exercise_key = excluded.exercise_key, set_index = excluded.set_index, weight_kg = excluded.weight_kg, reps = excluded.reps,
       seconds = excluded.seconds, distance_m = excluded.distance_m, rpe = excluded.rpe, done = excluded.done, updated_at = datetime('now')`
  ).bind(clientId, w.id, body.exercise_key, Number(body.set_index) || 0, weight, reps != null ? Math.round(reps) : null, seconds != null ? Math.round(seconds) : null, dist, rpe, body.done === false || body.done === 0 ? 0 : 1).run();
  await env.DB.prepare("UPDATE workouts SET updated_at = datetime('now'), status = CASE WHEN status = 'skipped' THEN 'in_progress' ELSE status END WHERE id = ?").bind(w.id).run();
  const row = await env.DB.prepare("SELECT * FROM sets WHERE client_id = ?").bind(clientId).first();
  return { set: row, workout_id: w.id };
}

// ---------- workouts ----------
async function getWorkout(env, id) {
  const w = await env.DB.prepare("SELECT * FROM workouts WHERE id = ?").bind(id).first();
  if (!w) throw new HttpError(404, "Workout not found");
  const { results: sets } = await env.DB.prepare("SELECT * FROM sets WHERE workout_id = ? ORDER BY exercise_key, set_index, id").bind(id).all();
  const { results: activities } = await env.DB.prepare("SELECT id, upload_id, start_time, sport, name, distance_m, duration_s, avg_hr, max_hr, avg_pace_s_per_km, best_5k_s, calories, elevation_gain_m FROM activities WHERE workout_id = ?").bind(id).all();
  return { ...rowWithJson(w, ["plan_json", "checklist_json"]), sets, activities };
}

async function patchWorkout(env, id, body) {
  const w = await env.DB.prepare("SELECT * FROM workouts WHERE id = ?").bind(id).first();
  if (!w) throw new HttpError(404, "Workout not found");
  const sets = [], vals = [];
  for (const f of WORKOUT_FIELDS) if (f in body) { let v = body[f]; if (["distance_km", "time_sec", "avg_hr", "rpe", "duration_min"].includes(f)) v = num(v); sets.push(`${f} = ?`); vals.push(v); }
  if ("checklist" in body) { sets.push("checklist_json = ?"); vals.push(body.checklist ? JSON.stringify(body.checklist) : null); }
  if ("plan" in body) { sets.push("plan_json = ?"); vals.push(Array.isArray(body.plan) ? JSON.stringify(body.plan) : null); }
  if ("date" in body) { sets.push("date = ?"); vals.push(assertDate(body.date)); }
  if (body.status === "done" && !w.finished_at) sets.push("finished_at = datetime('now')");
  if (sets.length) { sets.push("updated_at = datetime('now')"); await env.DB.prepare(`UPDATE workouts SET ${sets.join(", ")} WHERE id = ?`).bind(...vals, id).run(); }
  return getWorkout(env, id);
}

async function listWorkouts(env, url) {
  const from = url.searchParams.get("from"), to = url.searchParams.get("to");
  const limit = Math.min(Number(url.searchParams.get("limit") || 200), 2000);
  const where = [], vals = [];
  if (from) { assertDate(from); where.push("w.date >= ?"); vals.push(from); }
  if (to) { assertDate(to); where.push("w.date <= ?"); vals.push(to); }
  const sql = `SELECT w.id, w.date, w.template_key, w.kind, w.status, w.week_no, w.phase, w.duration_min, w.distance_km, w.time_sec, w.avg_hr, w.rpe, w.notes, w.started_at, w.finished_at,
      (SELECT COUNT(*) FROM sets s WHERE s.workout_id = w.id) AS set_count,
      (SELECT COUNT(DISTINCT s.exercise_key) FROM sets s WHERE s.workout_id = w.id) AS exercise_count,
      (SELECT ROUND(SUM(COALESCE(s.weight_kg,0) * COALESCE(s.reps,0))) FROM sets s WHERE s.workout_id = w.id) AS volume_kg,
      (SELECT COUNT(*) FROM activities a WHERE a.workout_id = w.id) AS activity_count
    FROM workouts w ${where.length ? "WHERE " + where.join(" AND ") : ""} ORDER BY w.date DESC, w.id DESC LIMIT ?`;
  const { results } = await env.DB.prepare(sql).bind(...vals, limit).all();
  return results;
}

// ---------- uploads ----------
function localDateFromActivity(act, tzOffsetMin, dateHint) {
  if (act.start_time) {
    if (act.local_time) return act.start_time.slice(0, 10);
    const utc = Date.parse(act.start_time);
    if (!isNaN(utc)) {
      const offset = act.local_offset_min != null ? act.local_offset_min : tzOffsetMin != null ? -tzOffsetMin : 0;
      return new Date(utc + offset * 60000).toISOString().slice(0, 10);
    }
  }
  return dateHint || todayLocal();
}

async function matchOrCreateWorkout(env, date, act, settings, allowCreate) {
  const { results } = await env.DB.prepare("SELECT * FROM workouts WHERE date = ? ORDER BY CASE kind WHEN 'run' THEN 0 WHEN 'other' THEN 1 ELSE 2 END, id").bind(date).all();
  const run = results.find((w) => w.kind === "run" || w.kind === "other");
  if (run) return run.id;
  if (!allowCreate) return null;
  const day = resolveDay(date, settings);
  const sport = (act.sport || "").toLowerCase();
  const isRun = /run|jog|treadmill/.test(sport);
  const templateKey = day.template.kind === "run" && isRun ? day.templateKey : "other";
  const w = await ensureWorkout(env, date, templateKey, settings);
  await env.DB.prepare("UPDATE workouts SET status = 'done', finished_at = COALESCE(finished_at, datetime('now')), notes = COALESCE(notes, ?) WHERE id = ?").bind(act.name ? `Garmin: ${act.name}` : null, w.id).run();
  return w.id;
}

async function fillWorkoutFromActivities(env, workoutId) {
  const act = await env.DB.prepare("SELECT * FROM activities WHERE workout_id = ? ORDER BY id DESC LIMIT 1").bind(workoutId).first();
  if (!act) return;
  await env.DB.prepare(
    `UPDATE workouts SET
       distance_km = COALESCE(distance_km, ?), time_sec = COALESCE(time_sec, ?), avg_hr = COALESCE(avg_hr, ?), duration_min = COALESCE(duration_min, ?),
       status = CASE WHEN status = 'in_progress' THEN 'done' ELSE status END, finished_at = COALESCE(finished_at, datetime('now')), updated_at = datetime('now')
     WHERE id = ?`
  ).bind(act.distance_m != null ? Math.round(act.distance_m / 10) / 100 : null, act.duration_s != null ? Math.round(act.duration_s) : null, act.avg_hr ?? null, act.duration_s != null ? Math.round(act.duration_s / 60) : null, workoutId).run();
}

async function insertActivity(env, uploadId, workoutId, act, date) {
  const res = await env.DB.prepare(
    `INSERT INTO activities (upload_id, workout_id, start_time, date, sport, name, distance_m, duration_s, elapsed_s, avg_hr, max_hr, calories, elevation_gain_m, avg_cadence, avg_pace_s_per_km, best_5k_s, best_1k_s, laps_json, splits_json, hr_zones_json, track_json)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(uploadId, workoutId, act.start_time || null, date, act.sport || null, act.name || null, act.distance_m ?? null, act.duration_s ?? null, act.elapsed_s ?? null, act.avg_hr ?? null, act.max_hr ?? null, act.calories ?? null, act.elevation_gain_m ?? null, act.avg_cadence ?? null, act.avg_pace_s_per_km ?? null, act.best_5k_s ?? null, act.best_1k_s ?? null,
    JSON.stringify(act.laps || []), JSON.stringify(act.splits || []), act.hr_zones ? JSON.stringify(act.hr_zones) : null, JSON.stringify(act.track || [])).run();
  return res.meta.last_row_id;
}

async function upsertNutritionDay(env, d, uploadId) {
  await env.DB.prepare(
    `INSERT INTO nutrition_days (date, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, meals_json, source, upload_id, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
     ON CONFLICT(date) DO UPDATE SET calories = excluded.calories, protein_g = excluded.protein_g, carbs_g = excluded.carbs_g, fat_g = excluded.fat_g, fiber_g = excluded.fiber_g,
       sugar_g = excluded.sugar_g, sodium_mg = excluded.sodium_mg, meals_json = excluded.meals_json, source = excluded.source, upload_id = excluded.upload_id, updated_at = datetime('now')`
  ).bind(d.date, num(d.calories), num(d.protein_g), num(d.carbs_g), num(d.fat_g), num(d.fiber_g), num(d.sugar_g), num(d.sodium_mg), d.meals ? JSON.stringify(d.meals) : null, d.source || "myfitnesspal", uploadId).run();
}

async function handleUpload(request, env, settings) {
  const ct = request.headers.get("Content-Type") || "";
  if (!ct.includes("multipart/form-data")) bad("Send multipart/form-data with one or more 'file' fields");
  const form = await request.formData();
  const files = form.getAll("file").filter((f) => f && typeof f === "object" && typeof f.arrayBuffer === "function");
  if (!files.length) bad("No files");
  const workoutId = num(form.get("workout_id"));
  if (workoutId != null) {
    const exists = await env.DB.prepare("SELECT id FROM workouts WHERE id = ?").bind(workoutId).first();
    if (!exists) bad(`Unknown workout_id ${workoutId}`);
  }
  const dateHint = form.get("date") ? assertDate(form.get("date")) : null;
  const sourceHint = form.get("source") || null;
  const tz = num(form.get("tz_offset_min"));
  const maxHr = num(settings.max_hr) || 190;
  const results = [];
  for (const f of files) {
    const bytes = new Uint8Array(await f.arrayBuffer());
    if (bytes.length > 25_000_000) { results.push({ filename: f.name, error: "File over 25 MB" }); continue; }
    const parsed = parseUpload({ filename: f.name, contentType: f.type, bytes, sourceHint, maxHr });
    const gz = await gzip(bytes);
    const storeRaw = gz.length <= MAX_RAW_GZ;
    const parsedJson = parsed.parsed ? JSON.stringify(parsed.parsed) : null;
    const res = await env.DB.prepare(
      `INSERT INTO uploads (workout_id, source, format, filename, content_type, size_bytes, raw, raw_encoding, parsed_json, parse_status, parse_error)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).bind(workoutId, parsed.source, parsed.format, f.name, f.type || null, bytes.length, storeRaw ? toArrayBuffer(gz) : null, storeRaw ? "gzip" : null,
      parsedJson && parsedJson.length < 1_500_000 ? parsedJson : null, parsed.status, parsed.error || (storeRaw ? null : "Raw file too large to store (over 1.8 MB compressed); parsed data kept")).run();
    const uploadId = res.meta.last_row_id;
    const out = { upload_id: uploadId, filename: f.name, format: parsed.format, source: parsed.source, status: parsed.status, error: parsed.error, activities: [], nutrition_days: 0, body_metrics: 0 };

    const single = parsed.activities.length === 1;
    for (const act of parsed.activities) {
      const date = localDateFromActivity(act, tz, dateHint);
      let wid = workoutId;
      if (!wid) wid = await matchOrCreateWorkout(env, date, act, settings, single);
      const id = await insertActivity(env, uploadId, wid, act, date);
      if (wid) await fillWorkoutFromActivities(env, wid);
      out.activities.push({ id, workout_id: wid, date, distance_m: act.distance_m, duration_s: act.duration_s, avg_hr: act.avg_hr, avg_pace_s_per_km: act.avg_pace_s_per_km, best_5k_s: act.best_5k_s, sport: act.sport });
    }
    if (workoutId && !parsed.activities.length) await env.DB.prepare("UPDATE uploads SET workout_id = ? WHERE id = ?").bind(workoutId, uploadId).run();
    for (const d of parsed.nutrition_days) { await upsertNutritionDay(env, d, uploadId); out.nutrition_days++; }
    for (const m of parsed.body_metrics) {
      await env.DB.prepare(`INSERT INTO body_metrics (date, weight_kg, source) VALUES (?, ?, 'myfitnesspal') ON CONFLICT(date, source) DO UPDATE SET weight_kg = excluded.weight_kg, updated_at = datetime('now')`).bind(m.date, m.weight_kg).run();
      out.body_metrics++;
    }
    results.push(out);
  }
  return { uploads: results };
}

// ---------- dashboard / export ----------
async function getDashboard(env, settings, date) {
  const [workouts, sets, body, tests, activities, nutrition, uploads, reports] = await Promise.all([
    env.DB.prepare("SELECT id, date, template_key, kind, status, week_no, phase, duration_min, distance_km, time_sec, avg_hr, rpe, notes, started_at, finished_at, plan_json FROM workouts ORDER BY date, id").all(),
    env.DB.prepare("SELECT s.id, s.client_id, s.workout_id, s.exercise_key, s.set_index, s.weight_kg, s.reps, s.seconds, s.distance_m, s.rpe, w.date FROM sets s JOIN workouts w ON w.id = s.workout_id WHERE s.done = 1 ORDER BY w.date, s.workout_id, s.exercise_key, s.set_index").all(),
    env.DB.prepare("SELECT id, date, weight_kg, source, notes FROM body_metrics ORDER BY date").all(),
    env.DB.prepare("SELECT id, date, week_no, test_key, value, notes FROM tests ORDER BY date").all(),
    env.DB.prepare("SELECT id, upload_id, workout_id, start_time, date, sport, name, distance_m, duration_s, elapsed_s, avg_hr, max_hr, calories, elevation_gain_m, avg_cadence, avg_pace_s_per_km, best_5k_s, best_1k_s, hr_zones_json FROM activities ORDER BY COALESCE(date, start_time)").all(),
    env.DB.prepare("SELECT id, date, calories, protein_g, carbs_g, fat_g, fiber_g, sugar_g, sodium_mg, source FROM nutrition_days ORDER BY date").all(),
    env.DB.prepare("SELECT id, workout_id, source, format, filename, size_bytes, parse_status, parse_error, uploaded_at FROM uploads ORDER BY uploaded_at DESC LIMIT 100").all(),
    env.DB.prepare("SELECT id, title, date, author, created_at FROM reports ORDER BY COALESCE(date, created_at) DESC, id DESC LIMIT 50").all(),
  ]);
  const today = resolveDay(date, settings);
  return {
    generated_at: new Date().toISOString(),
    settings,
    today,
    workouts: workouts.results.map((w) => rowWithJson(w, ["plan_json"])),
    sets: sets.results,
    body: body.results,
    tests: tests.results,
    activities: activities.results.map((a) => rowWithJson(a, ["hr_zones_json"])),
    nutrition: nutrition.results,
    uploads: uploads.results,
    reports: reports.results,
  };
}

async function exportAll(env, settings, includeRaw) {
  const q = async (sql) => (await env.DB.prepare(sql).all()).results;
  const out = {
    exported_at: new Date().toISOString(),
    app: "fitness-tracker",
    program: { name: PROGRAM.name, start_date: settings.program_start_date, templates: Object.keys(PROGRAM.templates), exercises: PROGRAM.exercises },
    settings,
    workouts: (await q("SELECT * FROM workouts ORDER BY date, id")).map((w) => rowWithJson(w, ["plan_json", "checklist_json"])),
    sets: await q("SELECT s.*, w.date FROM sets s JOIN workouts w ON w.id = s.workout_id ORDER BY w.date, s.workout_id, s.exercise_key, s.set_index"),
    body_metrics: await q("SELECT * FROM body_metrics ORDER BY date"),
    tests: await q("SELECT * FROM tests ORDER BY date"),
    activities: (await q("SELECT * FROM activities ORDER BY COALESCE(date, start_time)")).map((a) => rowWithJson(a, ["laps_json", "splits_json", "hr_zones_json", "track_json"])),
    nutrition_days: (await q("SELECT * FROM nutrition_days ORDER BY date")).map((n) => rowWithJson(n, ["meals_json"])),
    uploads: (await q("SELECT id, workout_id, source, format, filename, content_type, size_bytes, raw_encoding, parsed_json, parse_status, parse_error, uploaded_at FROM uploads ORDER BY id")).map((u) => rowWithJson(u, ["parsed_json"])),
    reports: await q("SELECT * FROM reports ORDER BY id"),
  };
  if (includeRaw) {
    const { results } = await env.DB.prepare("SELECT id, raw, raw_encoding FROM uploads WHERE raw IS NOT NULL ORDER BY id").all();
    const byId = new Map(out.uploads.map((u) => [u.id, u]));
    for (const r of results) {
      let bytes = blobToBytes(r.raw);
      if (r.raw_encoding === "gzip") bytes = await gunzip(bytes);
      const u = byId.get(r.id);
      if (u) u.raw_base64 = b64encode(bytes);
    }
  }
  const body = JSON.stringify(out);
  return new Response(body, { headers: { "Content-Type": "application/json; charset=utf-8", "Content-Disposition": `attachment; filename="fitness-export-${todayLocal()}.json"`, "Cache-Control": "no-store" } });
}
