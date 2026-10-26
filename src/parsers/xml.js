// TCX and GPX parsing with fast-xml-parser.
import { XMLParser } from "fast-xml-parser";
import { summarizeActivity } from "./activity.js";

const ARRAYS = new Set(["Activity", "Lap", "Trackpoint", "Track", "trk", "trkseg", "trkpt"]);
const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  removeNSPrefix: true,
  parseTagValue: false,
  trimValues: true,
  isArray: (name) => ARRAYS.has(name),
});

function n(v) { if (v == null || v === "") return undefined; const x = parseFloat(v); return isNaN(x) ? undefined : x; }
function t(v) { if (!v) return undefined; const x = Date.parse(v); return isNaN(x) ? undefined : x; }
function val(x) { if (x == null) return undefined; if (typeof x === "object") return n(x.Value ?? x["#text"]); return n(x); }

export function parseTcx(text, opts = {}) {
  const doc = parser.parse(text);
  const acts = doc?.TrainingCenterDatabase?.Activities?.Activity || [];
  if (!acts.length) throw new Error("No activities in TCX");
  return acts.map((act) => {
    const records = [], laps = [];
    let totalTime = 0, totalDist = 0, calories = 0, hrW = 0, hrT = 0, maxHr = null;
    (act.Lap || []).forEach((lap, i) => {
      const lapTime = n(lap.TotalTimeSeconds), lapDist = n(lap.DistanceMeters);
      const avgHr = val(lap.AverageHeartRateBpm), mx = val(lap.MaximumHeartRateBpm);
      if (lapTime) totalTime += lapTime;
      if (lapDist) totalDist += lapDist;
      if (n(lap.Calories)) calories += n(lap.Calories);
      if (avgHr && lapTime) { hrW += avgHr * lapTime; hrT += lapTime; }
      if (mx != null && (maxHr == null || mx > maxHr)) maxHr = mx;
      laps.push({ index: i + 1, start: lap["@_StartTime"] || null, duration_s: lapTime, distance_m: lapDist, avg_hr: avgHr, max_hr: mx, calories: n(lap.Calories), intensity: lap.Intensity, trigger: lap.TriggerMethod });
      for (const track of lap.Track || []) {
        for (const p of track.Trackpoint || []) {
          const ext = p.Extensions?.TPX || {};
          records.push({
            t: t(p.Time),
            lat: n(p.Position?.LatitudeDegrees),
            lon: n(p.Position?.LongitudeDegrees),
            alt: n(p.AltitudeMeters),
            dist: n(p.DistanceMeters),
            hr: val(p.HeartRateBpm),
            cad: n(ext.RunCadence ?? p.Cadence),
            speed: n(ext.Speed),
            power: n(ext.Watts),
          });
        }
      }
    });
    const meta = {
      sport: act["@_Sport"],
      start: act.Id || null,
      duration_s: totalTime || undefined,
      distance_m: totalDist || undefined,
      calories: calories || undefined,
      avg_hr: hrT ? Math.round(hrW / hrT) : undefined,
      max_hr: maxHr ?? undefined,
      device: act.Creator?.Name || null,
      name: act.Notes || null,
    };
    return summarizeActivity(records, laps, meta, opts);
  });
}

export function parseGpx(text, opts = {}) {
  const doc = parser.parse(text);
  const gpx = doc?.gpx;
  if (!gpx) throw new Error("Not a GPX file");
  const trks = gpx.trk || [];
  if (!trks.length) throw new Error("No tracks in GPX");
  return trks.map((trk) => {
    const records = [];
    for (const seg of trk.trkseg || []) {
      for (const p of seg.trkpt || []) {
        const ext = p.extensions?.TrackPointExtension || p.extensions || {};
        records.push({
          t: t(p.time),
          lat: n(p["@_lat"]),
          lon: n(p["@_lon"]),
          alt: n(p.ele),
          hr: n(ext.hr),
          cad: n(ext.cad),
          power: n(p.extensions?.power),
        });
      }
    }
    const meta = { sport: trk.type || "running", name: trk.name || null, start: gpx.metadata?.time || null, device: gpx["@_creator"] || null };
    return summarizeActivity(records, [], meta, opts);
  });
}
