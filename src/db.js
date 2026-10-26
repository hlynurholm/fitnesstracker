// Small D1 helpers.
import { PROGRAM, resolveDay, templateFor, buildPlan } from "../public/js/program.js";

export async function getSettings(env) {
  const { results } = await env.DB.prepare("SELECT key, value FROM settings").all();
  const s = {};
  for (const r of results || []) s[r.key] = r.value;
  if (!s.program_start_date) s.program_start_date = PROGRAM.startDateDefault;
  return s;
}

export async function setSettings(env, obj) {
  const stmts = [];
  for (const [k, v] of Object.entries(obj)) {
    if (v === null || v === "" || v === undefined) {
      stmts.push(env.DB.prepare("DELETE FROM settings WHERE key = ?").bind(k));
    } else {
      stmts.push(env.DB.prepare("INSERT INTO settings (key, value, updated_at) VALUES (?, ?, datetime('now')) ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')").bind(k, String(v)));
    }
  }
  if (stmts.length) await env.DB.batch(stmts);
}

export function parseJsonField(v, fallback = null) {
  if (v == null || v === "") return fallback;
  if (typeof v !== "string") return v;
  try { return JSON.parse(v); } catch { return fallback; }
}

export function rowWithJson(row, fields) {
  if (!row) return row;
  const out = { ...row };
  for (const f of fields) {
    const key = f.replace(/_json$/, "");
    out[key] = parseJsonField(row[f]);
    if (key !== f) delete out[f];
  }
  return out;
}

// Find or create the workout row for a date + template.
export async function ensureWorkout(env, date, templateKey, settings) {
  const existing = await env.DB.prepare("SELECT * FROM workouts WHERE date = ? AND template_key = ?").bind(date, templateKey).first();
  if (existing) return existing;
  const day = resolveDay(date, settings);
  const t = templateFor(templateKey);
  const plan = buildPlan(templateKey, day.week);
  await env.DB.prepare(
    `INSERT INTO workouts (date, template_key, kind, status, week_no, phase, plan_json, started_at)
     VALUES (?, ?, ?, 'in_progress', ?, ?, ?, datetime('now'))`
  ).bind(date, templateKey, t.kind, day.week, day.phase, plan.length ? JSON.stringify(plan) : null).run();
  return env.DB.prepare("SELECT * FROM workouts WHERE date = ? AND template_key = ?").bind(date, templateKey).first();
}

export const WORKOUT_FIELDS = ["status", "notes", "distance_km", "time_sec", "avg_hr", "rpe", "duration_min", "started_at", "finished_at"];

export function num(v) {
  if (v === "" || v === null || v === undefined) return null;
  const n = Number(v);
  return isNaN(n) ? null : n;
}

export function blobToBytes(v) {
  if (!v) return null;
  if (v instanceof ArrayBuffer) return new Uint8Array(v);
  if (v instanceof Uint8Array) return v;
  if (Array.isArray(v)) return Uint8Array.from(v);
  return null;
}

export async function gzip(bytes) {
  const cs = new CompressionStream("gzip");
  const writer = cs.writable.getWriter();
  writer.write(bytes);
  writer.close();
  return new Uint8Array(await new Response(cs.readable).arrayBuffer());
}

export async function gunzip(bytes) {
  const ds = new DecompressionStream("gzip");
  const writer = ds.writable.getWriter();
  writer.write(bytes);
  writer.close();
  return new Uint8Array(await new Response(ds.readable).arrayBuffer());
}

export function toArrayBuffer(bytes) {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

export function b64encode(bytes) {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  return btoa(s);
}
