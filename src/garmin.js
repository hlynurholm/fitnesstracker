// Pulls new activities from the Garmin Connect Personal API and feeds each original file through the same pipeline
// as a manual upload. Runs on a schedule (see wrangler.jsonc) and on demand through POST /api/garmin/sync.
//
// Garmin's reference: https://developer.garmin.com/gc-developer-program/personal/personal-api/
// The API key is the Worker secret GARMIN_API_KEY. It is exchanged for a 24 hour access token on every run, so no
// token is ever stored. Without the secret the sync does nothing.
//
// Two things the reference does not spell out are handled defensively and reported in the result if they differ:
// the JSON field that carries the access token, and the format of the downloaded file (Garmin's own "export original"
// is a zip with one .fit inside, so both a zip and a bare .fit are accepted).
import { setSettings } from "./db.js";
import { isFit } from "./parsers/fit.js";

const DEFAULT_BASE = "https://personal.connectapi.garmin.com";
const MAX_NEW_PER_RUN = 3; // each new file costs several database queries; the next run picks up the rest
const DEFAULT_DAYS = 14;
const HISTORY_DAYS = 120; // daily metrics fetched the first time

export function garminConfigured(env) {
  return typeof env.GARMIN_API_KEY === "string" && env.GARMIN_API_KEY.length > 0;
}

function isoDate(d) { return d.toISOString().slice(0, 10); }

async function garminFetch(base, path, init, what) {
  let res;
  try { res = await fetch(base + path, init); } catch (e) { throw new Error(`${what}: network error (${e.message || e})`); }
  if (!res.ok) {
    const body = (await res.text().catch(() => "")).slice(0, 200);
    const hint = res.status === 401 || res.status === 403 ? " Check that the API key is valid and has not expired." : "";
    throw new Error(`${what}: Garmin answered ${res.status}.${hint}${body ? ` ${body}` : ""}`);
  }
  return res;
}

async function accessToken(env, base) {
  const res = await garminFetch(base, "/personalapitoken-service/personal-api/personal-api-key/token",
    { method: "POST", headers: { Authorization: `ApiKey ${env.GARMIN_API_KEY}` } }, "Getting an access token");
  const text = (await res.text()).trim();
  let token = null;
  try {
    const j = JSON.parse(text);
    token = typeof j === "string" ? j : j.access_token || j.accessToken || j.token || null;
  } catch { if (text && !/\s/.test(text)) token = text; } // a bare token rather than JSON
  if (!token) throw new Error("Getting an access token: the response had no token field this code recognises (access_token, accessToken, token).");
  return token;
}

// Reads a zip archive and returns its entries as { name, bytes }. Stored and deflated entries only, which is all
// a Garmin export uses.
export async function unzip(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let eocd = -1;
  for (let i = bytes.length - 22; i >= Math.max(0, bytes.length - 22 - 65535); i--) {
    if (view.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("Not a zip archive");
  const count = view.getUint16(eocd + 10, true);
  let p = view.getUint32(eocd + 16, true);
  const dec = new TextDecoder();
  const out = [];
  for (let n = 0; n < count; n++) {
    if (view.getUint32(p, true) !== 0x02014b50) throw new Error("Corrupt zip directory");
    const method = view.getUint16(p + 10, true);
    const compressedSize = view.getUint32(p + 20, true);
    const nameLen = view.getUint16(p + 28, true), extraLen = view.getUint16(p + 30, true), commentLen = view.getUint16(p + 32, true);
    const local = view.getUint32(p + 42, true);
    const name = dec.decode(bytes.subarray(p + 46, p + 46 + nameLen));
    p += 46 + nameLen + extraLen + commentLen;
    if (name.endsWith("/")) continue;
    const dataStart = local + 30 + view.getUint16(local + 26, true) + view.getUint16(local + 28, true);
    const data = bytes.subarray(dataStart, dataStart + compressedSize);
    if (method === 0) out.push({ name, bytes: data });
    else if (method === 8) {
      const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
      out.push({ name, bytes: new Uint8Array(await new Response(stream).arrayBuffer()) });
    } else throw new Error(`Zip entry ${name} uses compression method ${method}, which is not supported`);
  }
  return out;
}

// The activity recording out of whatever the download endpoint returned.
async function activityFile(bytes, activityId) {
  if (bytes.length > 4 && bytes[0] === 0x50 && bytes[1] === 0x4b) {
    const entries = await unzip(bytes);
    const pick = entries.find((e) => isFit(e.bytes)) || entries.find((e) => /\.(fit|tcx|gpx)$/i.test(e.name));
    if (!pick) throw new Error(`the zip held no activity file (${entries.map((e) => e.name).join(", ") || "empty"})`);
    return { filename: pick.name.split("/").pop(), bytes: pick.bytes };
  }
  if (isFit(bytes)) return { filename: `${activityId}_ACTIVITY.fit`, bytes };
  const head = new TextDecoder().decode(bytes.subarray(0, 300));
  if (/<TrainingCenterDatabase/i.test(head)) return { filename: `${activityId}_ACTIVITY.tcx`, bytes };
  if (/<gpx[\s>]/i.test(head)) return { filename: `${activityId}_ACTIVITY.gpx`, bytes };
  throw new Error("the download was neither a zip nor a FIT, TCX or GPX file");
}

// Minutes to add to UTC to get the activity's local time, from the two start times Garmin gives.
function offsetMinutes(a) {
  const local = Date.parse(String(a.startTimeLocal || "").replace(" ", "T") + "Z");
  const gmt = Date.parse(String(a.startTimeGMT || "").replace(" ", "T") + "Z");
  return isNaN(local) || isNaN(gmt) ? null : Math.round((local - gmt) / 60000);
}

// ---------- daily health metrics ----------

// Fields that are identifiers, timestamps or nested event lists rather than measurements.
const SKIP = /uuid|userProfilePk|userProfilePK|^id$|timestamp|featureVersion|feedbackEvent|activityEvents|wellnessChronology|jetLag|algorithmVersion|^source$|^includes|calendarDate|summaryDate|dailyNapDTOS|deviceId|userNote|kidSleepNote|ageGroup|sleepVersion|createTimeStamp|samplePk|sourceType/i;

// Flattens one day's object into { "group.field": number | short string }.
export function flattenMetrics(obj, prefix = "", out = {}) {
  for (const [k, v] of Object.entries(obj || {})) {
    if (v == null || SKIP.test(k)) continue;
    const name = prefix ? `${prefix}.${k}` : k;
    if (typeof v === "number" && isFinite(v)) out[name] = v;
    else if (typeof v === "string" && v.length <= 40 && !/^\d{4}-\d{2}-\d{2}T/.test(v)) out[name] = v;
    else if (typeof v === "object" && !Array.isArray(v)) flattenMetrics(v, name, out);
  }
  return out;
}

function chunks(from, to, size) {
  const out = [];
  for (let d = new Date(from + "T00:00:00Z"); isoDate(d) <= to; d = new Date(d.getTime() + size * 86400000)) {
    const end = new Date(Math.min(d.getTime() + (size - 1) * 86400000, Date.parse(to + "T00:00:00Z")));
    out.push([isoDate(d), isoDate(end)]);
  }
  return out;
}

// Pulls every daily metric Garmin has for the last `days` days into daily_metrics. Each source is fetched on its own,
// so one that fails (or that the watch does not record) does not stop the others; failures come back in `errors`.
export async function syncGarminDaily(env, { days = 3 } = {}) {
  const result = { days: 0, errors: [] };
  if (!garminConfigured(env)) { result.errors.push("GARMIN_API_KEY is not set"); return result; }
  const base = (env.GARMIN_API_BASE || DEFAULT_BASE).replace(/\/+$/, "");
  const span = Math.min(366, Math.max(1, Number(days) || 3));
  const to = isoDate(new Date(Date.now() + 86400000)); // tomorrow in UTC, so "today" is covered in every time zone
  const from = isoDate(new Date(Date.now() - span * 86400000));
  const byDate = {};
  const put = (date, prefix, obj) => { if (/^\d{4}-\d{2}-\d{2}$/.test(date || "")) flattenMetrics(obj, prefix, (byDate[date] = byDate[date] || {})); };
  let auth;
  try { auth = { headers: { Authorization: `Bearer ${await accessToken(env, base)}`, Accept: "application/json" } }; }
  catch (e) { result.errors.push(e.message || String(e)); return result; }
  const get = async (path, what) => {
    try { return await (await garminFetch(base, path, auth, what)).json(); }
    catch (e) { result.errors.push(e.message || String(e)); return null; }
  };

  // Steps, floors, calories, heart rate, intensity minutes, stress, Body Battery, hydration, respiration, pulse ox.
  const summary = await get(`/usersummary-service/v2/dailysummaries?startDate=${from}&endDate=${to}`, "Daily summaries");
  for (const d of (summary && (summary.data || summary)) || []) put(String(d.calendarDate || "").slice(0, 10), "", d);
  // Sleep, at most 31 days per request.
  for (const [a, b] of chunks(from, to, 31)) {
    const sleep = await get(`/sleep-service/sleep/dailySleepSummariesByDate?startDate=${a}&endDate=${b}`, "Sleep");
    for (const d of Array.isArray(sleep) ? sleep : []) put(String(d.calendarDate || "").slice(0, 10), "sleep", d);
  }
  // Overnight heart rate variability.
  for (const [a, b] of chunks(from, to, 28)) {
    const hrv = await get(`/hrv-service/hrv/daily/${a}/${b}`, "HRV");
    for (const d of (hrv && hrv.hrvSummaries) || []) put(String(d.calendarDate || "").slice(0, 10), "hrv", d);
  }
  // Weight and body composition logged in Garmin. Kept as Garmin sends it; the app's own weigh-ins are not touched.
  const weight = await get(`/weight-service/weight/range/${from}/${to}`, "Weight");
  for (const d of (weight && weight.dailyWeightSummaries) || []) put(String(d.summaryDate || "").slice(0, 10), "weight", d.latestWeight || {});

  const dates = Object.keys(byDate).filter((d) => Object.keys(byDate[d]).length).sort();
  if (!dates.length) return result;
  // Merge into what is stored, so a source that failed this time keeps its earlier values.
  const { results: existing } = await env.DB.prepare("SELECT date, data FROM daily_metrics WHERE date >= ? AND date <= ?").bind(dates[0], dates[dates.length - 1]).all();
  const old = Object.fromEntries(existing.map((r) => { try { return [r.date, JSON.parse(r.data)]; } catch { return [r.date, {}]; } }));
  for (let i = 0; i < dates.length; i += 40) { // 2 bound values per row, D1 allows 100 per statement
    const part = dates.slice(i, i + 40);
    await env.DB.prepare(`INSERT INTO daily_metrics (date, data, updated_at) VALUES ${part.map(() => "(?, ?, datetime('now'))").join(", ")}
      ON CONFLICT(date) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`)
      .bind(...part.flatMap((d) => [d, JSON.stringify({ ...(old[d] || {}), ...byDate[d] })])).run();
  }
  result.days = dates.length;
  return result;
}

// ingest is the upload pipeline from api.js, passed in to avoid a circular import.
export async function syncGarmin(env, settings, ingest, { days = DEFAULT_DAYS, dailyDays } = {}) {
  const result = { at: new Date().toISOString(), configured: garminConfigured(env), ok: false, found: 0, imported: [], already: 0, failed: [], error: null, daily: null };
  if (!result.configured) { result.error = "GARMIN_API_KEY is not set"; return result; }
  // Daily health metrics: the last few days on a normal run, and a few months the first time.
  const { n } = (await env.DB.prepare("SELECT COUNT(*) AS n FROM daily_metrics").first()) || { n: 0 };
  result.daily = await syncGarminDaily(env, { days: dailyDays || (n ? 3 : HISTORY_DAYS) });
  const base = (env.GARMIN_API_BASE || DEFAULT_BASE).replace(/\/+$/, "");
  const type = env.GARMIN_ACTIVITY_TYPE === undefined ? "running" : env.GARMIN_ACTIVITY_TYPE; // "" means every type
  try {
    const token = await accessToken(env, base);
    const auth = { headers: { Authorization: `Bearer ${token}`, Accept: "application/json" } };
    const span = Math.min(366, Math.max(1, Number(days) || DEFAULT_DAYS));
    const q = new URLSearchParams({ startDate: isoDate(new Date(Date.now() - span * 86400000)), limit: "99", sortOrder: "desc" });
    if (type) q.set("activityType", type);
    const list = await (await garminFetch(base, `/activitylist-service/activities/search/activities?${q}`, auth, "Listing activities")).json();
    if (!Array.isArray(list)) throw new Error("Listing activities: expected a JSON array");
    result.found = list.length;

    // Garmin's own export names the file <id>_ACTIVITY.fit, so a file uploaded by hand counts as already imported.
    const { results: files } = await env.DB.prepare("SELECT filename FROM uploads WHERE filename IS NOT NULL ORDER BY id DESC LIMIT 2000").all();
    const have = new Set(files.map((f) => (String(f.filename).match(/^(\d+)[_.]/) || [])[1]).filter(Boolean));
    let fetched = 0;
    for (const a of list.slice().reverse()) { // oldest first
      const id = String(a.activityId ?? "");
      if (!/^\d+$/.test(id)) continue;
      if (have.has(id)) { result.already++; continue; }
      if (fetched >= MAX_NEW_PER_RUN) { result.more = true; break; }
      fetched++;
      try {
        const res = await garminFetch(base, `/download-service/files/activity/${id}`, { headers: { Authorization: `Bearer ${token}` } }, `Downloading activity ${id}`);
        const file = await activityFile(new Uint8Array(await res.arrayBuffer()), id);
        const filename = file.filename.startsWith(id) ? file.filename : `${id}_${file.filename}`;
        const offset = offsetMinutes(a);
        const out = await ingest(env, settings, {
          filename, contentType: "application/octet-stream", bytes: file.bytes, workoutId: null, sourceHint: "garmin",
          dateHint: /^\d{4}-\d{2}-\d{2}/.test(a.startTimeLocal || "") ? a.startTimeLocal.slice(0, 10) : null,
          tz: offset == null ? null : -offset, // same sign convention as the browser's getTimezoneOffset()
        });
        if (out.status === "failed") result.failed.push({ id, name: a.activityName || null, error: `stored, but could not parse: ${out.error}` });
        else result.imported.push({ id, name: a.activityName || null, date: out.activities[0]?.date || null, upload_id: out.upload_id, workout_id: out.activities[0]?.workout_id ?? null });
      } catch (e) {
        result.failed.push({ id, name: a.activityName || null, error: e.message || String(e) });
      }
    }
    result.ok = result.failed.length === 0;
    if (result.failed.length) result.error = `${result.failed.length} of ${fetched} downloads failed. First: ${result.failed[0].error}`;
  } catch (e) {
    result.error = e.message || String(e);
  }
  if (result.daily.errors.length) { result.ok = false; result.error = [result.error, `Daily metrics: ${result.daily.errors[0]}`].filter(Boolean).join(" ") ; }
  // The outcome of the last run is kept with the settings so the apps can show it. It holds no secrets.
  try { await setSettings(env, { garmin_last_sync: JSON.stringify({ at: result.at, ok: result.ok, found: result.found, imported: result.imported.length, already: result.already, daily_days: result.daily.days, error: result.error }) }); } catch {}
  return result;
}
