// Garmin Connect CSV exports: the activities list ("Activities.csv") and per-activity splits.
import { parseDelimited, rowsToObjects, findCol, toNumber, toSeconds } from "./csv.js";

export function looksLikeGarminCsv(headers) {
  const h = headers.map((x) => x.toLowerCase());
  const hasActivityList = h.includes("activity type") && h.some((x) => x === "date") && h.some((x) => x.startsWith("distance"));
  const hasSplits = h.includes("split") && h.some((x) => x === "time" || x.startsWith("time"));
  return hasActivityList || hasSplits;
}

function parseGarminDate(s) {
  if (!s) return null;
  const m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?/);
  if (m) return `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6] || "00"}`; // no zone: Garmin exports local time
  const d = Date.parse(s);
  return isNaN(d) ? null : new Date(d).toISOString();
}

export function parseGarminCsv(text) {
  const rows = parseDelimited(text);
  const { headers, records } = rowsToObjects(rows);
  const h = headers.map((x) => x.toLowerCase());
  if (h.includes("split")) return parseSplitsCsv(headers, records);
  return parseActivityListCsv(headers, records);
}

function parseActivityListCsv(headers, records) {
  const col = (c) => findCol(headers, c);
  const cType = col(["Activity Type"]), cDate = col(["Date"]), cTitle = col(["Title"]), cDist = col(["Distance"]), cCal = col(["Calories"]);
  const cTime = col(["Time"]), cMoving = col(["Moving Time"]), cElapsed = col(["Elapsed Time"]), cAvgHr = col(["Avg HR"]), cMaxHr = col(["Max HR"]);
  const cPace = col(["Avg Pace"]), cBestPace = col(["Best Pace"]), cAscent = col(["Total Ascent"]), cCad = col(["Avg Run Cadence", "Avg Cadence"]);
  const cTE = col(["Aerobic TE"]), cPower = col(["Avg Power"]), cLaps = col(["Number of Laps"]);
  const activities = records.map((r) => {
    const dist = toNumber(r[cDist]);
    const distanceM = dist != null ? (dist < 200 ? dist * 1000 : dist) : null; // km in the export; metres if it looks huge
    const time = toSeconds(r[cTime]) ?? toSeconds(r[cMoving]);
    const sport = (r[cType] || "").toLowerCase();
    let cad = toNumber(r[cCad]);
    if (cad != null && /run|walk/.test(sport) && cad < 130) cad *= 2;
    return {
      sport: sport || null,
      name: r[cTitle] || null,
      start_time: parseGarminDate(r[cDate]),
      local_time: true,
      distance_m: distanceM != null ? Math.round(distanceM) : null,
      duration_s: time != null ? Math.round(time) : null,
      moving_s: toSeconds(r[cMoving]) != null ? Math.round(toSeconds(r[cMoving])) : null,
      elapsed_s: toSeconds(r[cElapsed]) != null ? Math.round(toSeconds(r[cElapsed])) : null,
      calories: toNumber(r[cCal]),
      avg_hr: toNumber(r[cAvgHr]),
      max_hr: toNumber(r[cMaxHr]),
      avg_pace_s_per_km: toSeconds(r[cPace]) ?? (time && distanceM ? Math.round(time / (distanceM / 1000)) : null),
      best_pace_s_per_km: toSeconds(r[cBestPace]),
      elevation_gain_m: toNumber(r[cAscent]),
      avg_cadence: cad,
      avg_power: toNumber(r[cPower]),
      training_effect: toNumber(r[cTE]),
      lap_count: toNumber(r[cLaps]),
      laps: [], splits: [], track: [], hr_zones: null,
      raw_row: r,
    };
  }).filter((a) => a.start_time || a.distance_m || a.duration_s);
  return { kind: "garmin_activity_list", activities };
}

function parseSplitsCsv(headers, records) {
  const col = (c) => findCol(headers, c);
  const cSplit = col(["Split"]), cTime = col(["Time"]), cMoving = col(["Moving Time"]), cCum = col(["Cumulative Time"]), cDist = col(["Distance"]);
  const cPace = col(["Avg Pace"]), cAvgHr = col(["Avg HR"]), cMaxHr = col(["Max HR"]), cCad = col(["Avg Run Cadence", "Avg Cadence"]), cGain = col(["Elevation Gain", "Total Ascent"]), cCal = col(["Calories"]);
  const laps = [], summary = {};
  let cum = 0, cumDist = 0;
  for (const r of records) {
    const label = (r[cSplit] || "").trim().toLowerCase();
    const secs = toSeconds(r[cTime]) ?? toSeconds(r[cMoving]);
    const dist = toNumber(r[cDist]);
    const distM = dist != null ? (dist < 200 ? dist * 1000 : dist) : null;
    if (label === "summary" || label === "total" || label === "samtals") {
      summary.duration_s = secs != null ? Math.round(secs) : null;
      summary.distance_m = distM != null ? Math.round(distM) : null;
      summary.avg_hr = toNumber(r[cAvgHr]);
      summary.max_hr = toNumber(r[cMaxHr]);
      summary.calories = toNumber(r[cCal]);
      summary.elevation_gain_m = toNumber(r[cGain]);
      summary.avg_pace_s_per_km = toSeconds(r[cPace]);
      continue;
    }
    if (secs == null && distM == null) continue;
    if (secs != null) cum += secs;
    if (distM != null) cumDist += distM;
    laps.push({
      index: laps.length + 1,
      duration_s: secs != null ? Math.round(secs) : null,
      distance_m: distM != null ? Math.round(distM) : null,
      pace_s_per_km: toSeconds(r[cPace]) ?? (secs && distM ? Math.round(secs / (distM / 1000)) : null),
      avg_hr: toNumber(r[cAvgHr]),
      max_hr: toNumber(r[cMaxHr]),
      cumulative_s: toSeconds(r[cCum]) != null ? Math.round(toSeconds(r[cCum])) : Math.round(cum),
    });
  }
  const duration = summary.duration_s ?? (cum ? Math.round(cum) : null);
  const distance = summary.distance_m ?? (cumDist ? Math.round(cumDist) : null);
  const hrLaps = laps.filter((l) => l.avg_hr != null && l.duration_s);
  const avgHr = summary.avg_hr ?? (hrLaps.length ? Math.round(hrLaps.reduce((s, l) => s + l.avg_hr * l.duration_s, 0) / hrLaps.reduce((s, l) => s + l.duration_s, 0)) : null);
  const activity = {
    sport: "running",
    name: null,
    start_time: null,
    distance_m: distance,
    duration_s: duration,
    avg_hr: avgHr,
    max_hr: summary.max_hr ?? (laps.some((l) => l.max_hr != null) ? Math.max(...laps.filter((l) => l.max_hr != null).map((l) => l.max_hr)) : null),
    calories: summary.calories ?? null,
    elevation_gain_m: summary.elevation_gain_m ?? null,
    avg_pace_s_per_km: summary.avg_pace_s_per_km ?? (duration && distance ? Math.round(duration / (distance / 1000)) : null),
    laps,
    splits: laps.filter((l) => l.distance_m && Math.abs(l.distance_m - 1000) < 30).map((l) => ({ km: l.index, distance_m: l.distance_m, seconds: l.duration_s, pace_s_per_km: l.pace_s_per_km, avg_hr: l.avg_hr })),
    track: [], hr_zones: null,
    best_5k_s: distance && distance >= 5000 && distance < 5100 ? duration : null,
  };
  return { kind: "garmin_splits", activities: [activity] };
}
