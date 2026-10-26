// Turns a list of GPS/HR records into an activity summary. Shared by FIT, TCX and GPX parsers.
// record: { t (ms), lat, lon, alt (m), dist (m, cumulative), hr, cad, speed (m/s), power }

const R = 6371000;
function haversine(lat1, lon1, lat2, lon2) {
  const toRad = (x) => (x * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1), dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

function finite(v) { return typeof v === "number" && isFinite(v); }

export function hrZonesFor(maxHr) {
  return [0.5, 0.6, 0.7, 0.8, 0.9].map((f) => Math.round(f * maxHr));
}

// Time at which cumulative distance reaches `target`, interpolated. recs must have dist and t.
function timeAtDistance(recs, startIdx, target) {
  for (let j = startIdx + 1; j < recs.length; j++) {
    if (recs[j].dist >= target) {
      const a = recs[j - 1], b = recs[j];
      const span = b.dist - a.dist;
      const frac = span > 0 ? (target - a.dist) / span : 1;
      return { t: a.t + frac * (b.t - a.t), idx: j };
    }
  }
  return null;
}

export function summarizeActivity(records, laps = [], meta = {}, opts = {}) {
  const maxHr = opts.maxHr || 190;
  let recs = (records || []).filter((r) => finite(r.t)).sort((a, b) => a.t - b.t);

  // Fill cumulative distance from GPS when missing.
  const hasDist = recs.some((r) => finite(r.dist) && r.dist > 0);
  if (!hasDist) {
    let d = 0, prev = null;
    for (const r of recs) {
      if (prev && finite(r.lat) && finite(r.lon) && finite(prev.lat) && finite(prev.lon)) d += haversine(prev.lat, prev.lon, r.lat, r.lon);
      r.dist = d;
      if (finite(r.lat) && finite(r.lon)) prev = r;
    }
  } else {
    let last = 0;
    for (const r of recs) { if (finite(r.dist)) last = r.dist; else r.dist = last; }
  }

  const first = recs[0], last = recs[recs.length - 1];
  const elapsed = first && last ? (last.t - first.t) / 1000 : null;
  const totalDist = finite(meta.distance_m) ? meta.distance_m : last ? last.dist : null;

  // Moving time, HR, cadence, zones.
  let moving = 0, hrTime = 0, hrSum = 0, maxHrSeen = null, cadSum = 0, cadN = 0, powSum = 0, powN = 0;
  const zones = [0, 0, 0, 0, 0];
  const edges = hrZonesFor(maxHr);
  for (let i = 1; i < recs.length; i++) {
    const a = recs[i - 1], b = recs[i];
    const rawDt = (b.t - a.t) / 1000;
    if (rawDt <= 0) continue;
    const dt = Math.min(rawDt, 120); // long gaps (pauses) count at most 2 min
    const dd = b.dist - a.dist;
    const spd = finite(b.speed) ? b.speed : dd / rawDt;
    if (spd > 0.5 || dd > 0.5) moving += dt;
    if (finite(b.hr) && b.hr > 0) {
      hrTime += dt; hrSum += b.hr * dt;
      let z = 0;
      for (let k = 1; k < edges.length; k++) if (b.hr >= edges[k]) z = k;
      zones[z] += dt;
    }
    if (finite(b.cad) && b.cad > 0) { cadSum += b.cad; cadN++; }
    if (finite(b.power) && b.power > 0) { powSum += b.power; powN++; }
  }
  for (const r of recs) if (finite(r.hr) && r.hr > 0 && (maxHrSeen == null || r.hr > maxHrSeen)) maxHrSeen = r.hr;
  const avgHr = finite(meta.avg_hr) ? meta.avg_hr : hrTime > 0 ? Math.round(hrSum / hrTime) : null;
  const maxHrOut = finite(meta.max_hr) ? meta.max_hr : maxHrSeen;
  let avgCad = finite(meta.avg_cadence) ? meta.avg_cadence : cadN ? cadSum / cadN : null;
  const sport = (meta.sport || "running").toString().toLowerCase();
  if (avgCad != null && /run|walk|hik/.test(sport) && avgCad < 130) avgCad = avgCad * 2; // one-foot rpm to steps per minute
  const avgPower = finite(meta.avg_power) ? meta.avg_power : powN ? powSum / powN : null;

  const duration = finite(meta.duration_s) ? meta.duration_s : moving > 0 ? moving : elapsed;

  // Elevation gain with 1 m hysteresis.
  let gain = 0, base = null;
  for (const r of recs) {
    if (!finite(r.alt)) continue;
    if (base == null) { base = r.alt; continue; }
    if (r.alt > base + 1) { gain += r.alt - base; base = r.alt; }
    else if (r.alt < base - 1) base = r.alt;
  }
  const elevationGain = finite(meta.ascent_m) ? meta.ascent_m : recs.some((r) => finite(r.alt)) ? Math.round(gain) : null;

  // 1 km splits.
  const splits = [];
  if (recs.length > 1 && totalDist > 0) {
    let startIdx = 0, startT = first.t, startDist = 0, k = 1;
    while (k * 1000 <= last.dist + 1) {
      const hit = timeAtDistance(recs, startIdx, k * 1000);
      if (!hit) break;
      const secs = (hit.t - startT) / 1000;
      let hs = 0, hn = 0;
      for (let i = startIdx; i <= hit.idx; i++) if (finite(recs[i].hr)) { hs += recs[i].hr; hn++; }
      splits.push({ km: k, distance_m: 1000, seconds: Math.round(secs), pace_s_per_km: Math.round(secs), avg_hr: hn ? Math.round(hs / hn) : null });
      startT = hit.t; startIdx = Math.max(hit.idx - 1, startIdx); startDist = k * 1000; k++;
    }
    const remM = last.dist - startDist;
    if (remM > 50) {
      const secs = (last.t - startT) / 1000;
      let hs = 0, hn = 0;
      for (let i = startIdx; i < recs.length; i++) if (finite(recs[i].hr)) { hs += recs[i].hr; hn++; }
      splits.push({ km: k, distance_m: Math.round(remM), seconds: Math.round(secs), pace_s_per_km: Math.round(secs / (remM / 1000)), avg_hr: hn ? Math.round(hs / hn) : null, partial: true });
    }
  }

  // Best efforts over 1 km and 5 km (fastest contiguous stretch).
  function best(D) {
    if (!recs.length || last.dist < D) return null;
    let bestT = null, j = 1;
    for (let i = 0; i < recs.length - 1; i++) {
      const target = recs[i].dist + D;
      while (j < recs.length && recs[j].dist < target) j++;
      if (j >= recs.length) break;
      const a = recs[j - 1], b = recs[j];
      const span = b.dist - a.dist;
      const frac = span > 0 ? (target - a.dist) / span : 1;
      const tEnd = a.t + frac * (b.t - a.t);
      const dt = (tEnd - recs[i].t) / 1000;
      if (dt > 0 && (bestT == null || dt < bestT)) bestT = dt;
    }
    return bestT == null ? null : Math.round(bestT);
  }
  const best1k = best(1000), best5k = best(5000);

  // Downsampled track for charts (max ~240 points).
  const track = [];
  if (recs.length > 1) {
    const step = Math.max(1, Math.ceil(recs.length / 240));
    for (let i = 0; i < recs.length; i += step) {
      const r = recs[i];
      const prev = recs[Math.max(0, i - step)];
      const dt = (r.t - prev.t) / 1000, dd = r.dist - prev.dist;
      track.push({
        t: Math.round((r.t - first.t) / 1000),
        d: Math.round(r.dist) / 1000,
        hr: finite(r.hr) ? r.hr : null,
        pace: dd > 5 && dt > 0 ? Math.round(dt / (dd / 1000)) : null,
        alt: finite(r.alt) ? Math.round(r.alt * 10) / 10 : null,
      });
    }
  }

  const lapsOut = (laps || []).map((l, i) => ({
    index: l.index ?? i + 1,
    start: l.start || null,
    duration_s: finite(l.duration_s) ? Math.round(l.duration_s) : null,
    distance_m: finite(l.distance_m) ? Math.round(l.distance_m) : null,
    avg_hr: finite(l.avg_hr) ? Math.round(l.avg_hr) : null,
    max_hr: finite(l.max_hr) ? Math.round(l.max_hr) : null,
    pace_s_per_km: finite(l.duration_s) && finite(l.distance_m) && l.distance_m > 0 ? Math.round(l.duration_s / (l.distance_m / 1000)) : null,
    intensity: l.intensity || null,
    trigger: l.trigger || null,
    calories: finite(l.calories) ? l.calories : null,
  }));

  const startTime = meta.start ? new Date(meta.start) : first ? new Date(first.t) : null;
  return {
    sport,
    sub_sport: meta.sub_sport || null,
    name: meta.name || null,
    device: meta.device || null,
    start_time: startTime && !isNaN(startTime) ? startTime.toISOString() : null,
    distance_m: finite(totalDist) ? Math.round(totalDist) : null,
    duration_s: finite(duration) ? Math.round(duration) : null,
    elapsed_s: finite(meta.elapsed_s) ? Math.round(meta.elapsed_s) : finite(elapsed) ? Math.round(elapsed) : null,
    moving_s: moving ? Math.round(moving) : null,
    avg_hr: avgHr,
    max_hr: maxHrOut,
    calories: finite(meta.calories) ? meta.calories : null,
    elevation_gain_m: elevationGain,
    avg_cadence: avgCad != null ? Math.round(avgCad) : null,
    avg_power: avgPower != null ? Math.round(avgPower) : null,
    avg_pace_s_per_km: finite(duration) && finite(totalDist) && totalDist > 0 ? Math.round(duration / (totalDist / 1000)) : null,
    best_1k_s: best1k,
    best_5k_s: best5k,
    hr_zones: { max_hr_used: maxHr, edges, seconds: zones.map((z) => Math.round(z)) },
    laps: lapsOut,
    splits,
    track,
    record_count: recs.length,
    training_effect: meta.training_effect ?? null,
    anaerobic_training_effect: meta.anaerobic_training_effect ?? null,
    local_offset_min: finite(meta.local_offset_min) ? meta.local_offset_min : null,
  };
}
