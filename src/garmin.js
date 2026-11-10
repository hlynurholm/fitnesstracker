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
const MAX_NEW_PER_RUN = 8; // stays well inside the Workers subrequest limit
const DEFAULT_DAYS = 14;

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

// ingest is the upload pipeline from api.js, passed in to avoid a circular import.
export async function syncGarmin(env, settings, ingest, { days = DEFAULT_DAYS } = {}) {
  const result = { at: new Date().toISOString(), configured: garminConfigured(env), ok: false, found: 0, imported: [], already: 0, failed: [], error: null };
  if (!result.configured) { result.error = "GARMIN_API_KEY is not set"; return result; }
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

    let fetched = 0;
    for (const a of list.slice().reverse()) { // oldest first
      const id = String(a.activityId ?? "");
      if (!/^\d+$/.test(id)) continue;
      // Garmin's own export names the file <id>_ACTIVITY.fit, so a file uploaded by hand counts as already imported.
      const seen = await env.DB.prepare("SELECT id FROM uploads WHERE filename LIKE ? ESCAPE '\\' OR filename LIKE ? LIMIT 1").bind(`${id}\\_%`, `${id}.%`).first();
      if (seen) { result.already++; continue; }
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
  // The outcome of the last run is kept with the settings so the apps can show it. It holds no secrets.
  try { await setSettings(env, { garmin_last_sync: JSON.stringify({ at: result.at, ok: result.ok, found: result.found, imported: result.imported.length, already: result.already, error: result.error }) }); } catch {}
  return result;
}
