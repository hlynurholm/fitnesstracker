// Garmin FIT decoding via the official FIT JavaScript SDK.
import { Decoder, Stream } from "@garmin/fitsdk";
import { summarizeActivity } from "./activity.js";

const SEMI = 180 / 2 ** 31;
function deg(v) { return typeof v === "number" ? (Math.abs(v) > 180 ? v * SEMI : v) : undefined; }
const FIT_EPOCH_S = 631065600; // 1989-12-31T00:00:00Z
function ms(d) { return d instanceof Date ? d.getTime() : typeof d === "number" ? (d + FIT_EPOCH_S) * 1000 : undefined; }
function iso(d) { const t = ms(d); return t ? new Date(t).toISOString() : null; }

export function isFit(bytes) {
  return bytes.length > 12 && String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]) === ".FIT";
}

export function parseFit(bytes, opts = {}) {
  const stream = Stream.fromByteArray(bytes);
  const decoder = new Decoder(stream);
  if (!decoder.isFIT()) throw new Error("Not a FIT file");
  const { messages, errors } = decoder.read({ includeUnknownData: false, mergeHeartRates: true });
  const session = (messages.sessionMesgs || [])[0] || {};
  const laps = messages.lapMesgs || [];
  const recordMesgs = messages.recordMesgs || [];
  const activity = (messages.activityMesgs || [])[0] || {};
  const fileId = (messages.fileIdMesgs || [])[0] || {};

  const records = recordMesgs.map((r) => ({
    t: ms(r.timestamp),
    lat: deg(r.positionLat),
    lon: deg(r.positionLong),
    alt: r.enhancedAltitude ?? r.altitude,
    dist: r.distance,
    hr: r.heartRate,
    cad: r.cadence != null ? r.cadence + (r.fractionalCadence || 0) : undefined,
    speed: r.enhancedSpeed ?? r.speed,
    power: r.power,
  }));

  const lapList = laps.map((l, i) => ({
    index: i + 1,
    start: iso(l.startTime),
    duration_s: l.totalTimerTime ?? l.totalElapsedTime,
    distance_m: l.totalDistance,
    avg_hr: l.avgHeartRate,
    max_hr: l.maxHeartRate,
    calories: l.totalCalories,
    intensity: l.intensity,
    trigger: l.lapTrigger,
  }));

  let localOffset = null;
  if (activity.localTimestamp != null && activity.timestamp) {
    // localTimestamp is "local time written as if it were UTC"; the SDK may return it as a Date or FIT seconds.
    const lt = ms(activity.localTimestamp), ut = ms(activity.timestamp);
    if (lt && ut) localOffset = Math.round((lt - ut) / 60000);
    if (localOffset != null && Math.abs(localOffset) > 14 * 60) localOffset = null;
  }

  const meta = {
    sport: session.sport,
    sub_sport: session.subSport,
    start: iso(session.startTime),
    duration_s: session.totalTimerTime,
    elapsed_s: session.totalElapsedTime,
    distance_m: session.totalDistance,
    avg_hr: session.avgHeartRate,
    max_hr: session.maxHeartRate,
    calories: session.totalCalories,
    ascent_m: session.totalAscent,
    avg_cadence: session.avgRunningCadence ?? session.avgCadence,
    avg_power: session.avgPower,
    training_effect: session.totalTrainingEffect,
    anaerobic_training_effect: session.totalAnaerobicTrainingEffect,
    device: [fileId.manufacturer, fileId.garminProduct ?? fileId.product].filter((x) => x != null).join(" ") || null,
    local_offset_min: localOffset,
  };
  const summary = summarizeActivity(records, lapList, meta, opts);
  summary.decoder_errors = (errors || []).map((e) => String(e.message || e)).slice(0, 5);
  return summary;
}
