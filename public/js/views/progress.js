// Progress dashboard: weight, lifts (single and overlaid), running, nutrition, adherence, tests.
import { api } from "../api.js";
import { h, clear, fmtShort, fmtDay, secondsToHms, fmtKg, store } from "../util.js";
import { PROGRAM, exerciseFor, templateFor, e1rm, fmtTime, fmtPace, weekNumber, mondayOf, addDays, todayLocal, resolveDay } from "../program.js";
import { lineChart, barChart, dataset, PALETTE, fmtDateTick } from "../charts.js";

export async function renderProgress(container) {
  const d = await api.get("/api/dashboard");
  clear(container);
  container.appendChild(h("h1", null, "Progress"));
  const model = buildModel(d);
  container.appendChild(tiles(model, d));
  const grid = h("div", { class: "charts" });
  container.appendChild(grid);
  grid.appendChild(weightCard(model, d));
  grid.appendChild(adherenceCard(model, d));
  grid.appendChild(liftCard(model));
  grid.appendChild(overlayCard(model));
  grid.appendChild(runCard(model, d));
  grid.appendChild(nutritionCard(model, d));
  grid.appendChild(testsCard(d));
  grid.appendChild(bestsCard(model));
}

// ---------- data model ----------
function buildModel(d) {
  const start = d.settings.program_start_date;
  // Lifts: per exercise, per session
  const byEx = new Map();
  for (const s of d.sets) {
    const ex = exerciseFor(s.exercise_key);
    if (!byEx.has(s.exercise_key)) byEx.set(s.exercise_key, { key: s.exercise_key, ex, sessions: new Map() });
    const e = byEx.get(s.exercise_key);
    const sk = `${s.date}#${s.workout_id}`;
    if (!e.sessions.has(sk)) e.sessions.set(sk, { date: s.date, workout_id: s.workout_id, sets: [] });
    e.sessions.get(sk).sets.push(s);
  }
  const lifts = [];
  for (const e of byEx.values()) {
    const sessions = [...e.sessions.values()].sort((a, b) => a.date.localeCompare(b.date)).map((s) => {
      const kgReps = s.sets.filter((x) => x.weight_kg != null && x.reps != null);
      const top = kgReps.length ? Math.max(...kgReps.map((x) => x.weight_kg)) : null;
      const topSet = kgReps.filter((x) => x.weight_kg === top).sort((a, b) => (b.reps || 0) - (a.reps || 0))[0];
      const best = kgReps.reduce((m, x) => Math.max(m, e1rm(x.weight_kg, x.reps) || 0), 0) || null;
      const volume = kgReps.reduce((v, x) => v + x.weight_kg * x.reps, 0);
      const totalReps = s.sets.reduce((v, x) => v + (x.reps || 0), 0);
      const bestReps = s.sets.reduce((m, x) => Math.max(m, x.reps || 0), 0);
      const bestSeconds = s.sets.reduce((m, x) => Math.max(m, x.seconds || 0), 0);
      return { date: s.date, sets: s.sets, top, topReps: topSet ? topSet.reps : null, e1rm: best, volume, totalReps, bestReps, bestSeconds };
    });
    lifts.push({ key: e.key, ex: e.ex, sessions, count: sessions.length });
  }
  lifts.sort((a, b) => b.count - a.count || a.ex.name.localeCompare(b.ex.name));

  // Weight
  const manual = d.body.filter((b) => b.weight_kg != null).sort((a, b) => a.date.localeCompare(b.date));
  const weights = [];
  const seen = new Map();
  for (const b of manual) { if (!seen.has(b.date) || b.source === "manual") seen.set(b.date, b.weight_kg); }
  for (const [date, kg] of [...seen.entries()].sort((a, b) => a[0].localeCompare(b[0]))) weights.push({ date, kg });
  const rolling = weights.map((w, i) => {
    const from = addDays(w.date, -6);
    const win = weights.filter((x) => x.date >= from && x.date <= w.date);
    return { date: w.date, kg: win.reduce((s, x) => s + x.kg, 0) / win.length, n: win.length };
  });

  // Runs
  const runs = d.workouts.filter((w) => w.kind === "run" && w.status !== "skipped" && (w.time_sec || w.distance_km));
  const actByWorkout = new Map();
  for (const a of d.activities) if (a.workout_id) actByWorkout.set(a.workout_id, a);

  // Adherence per week
  const weeks = new Map();
  const today = todayLocal();
  for (const w of d.workouts) {
    const wk = weekNumber(w.date, start);
    if (wk < 1) continue;
    if (!weeks.has(wk)) weeks.set(wk, { week: wk, days: {} });
    const rec = weeks.get(wk);
    const prev = rec.days[w.date];
    const rank = { done: 3, in_progress: 2, skipped: 1 };
    if (!prev || (rank[w.status] || 0) > (rank[prev.status] || 0)) rec.days[w.date] = { status: w.status, kind: w.kind };
  }
  const currentWeek = weekNumber(today, start);
  for (let wk = 1; wk <= Math.max(currentWeek, 1); wk++) if (!weeks.has(wk)) weeks.set(wk, { week: wk, days: {} });
  const adherence = [...weeks.values()].sort((a, b) => a.week - b.week).map((rec) => {
    const monday = addDays(mondayOf(start), (rec.week - 1) * 7);
    const days = [];
    let planned = 0, done = 0;
    for (let i = 0; i < 7; i++) {
      const date = addDays(monday, i);
      const sched = resolveDay(date, d.settings);
      const isPlanned = sched.template.kind !== "rest";
      const logged = rec.days[date];
      if (isPlanned) planned++;
      if (logged && logged.status === "done" && logged.kind !== "rest") done++;
      days.push({ date, planned: isPlanned, status: logged ? logged.status : null, future: date > today, kind: sched.template.kind });
    }
    return { week: rec.week, days, planned, done };
  });

  return { lifts, weights, rolling, runs, actByWorkout, adherence, currentWeek, start };
}

// ---------- tiles ----------
function tiles(m, d) {
  const goal = Number(d.settings.goal_weight_kg) || PROGRAM.body.goalWeightKg;
  const latest = m.rolling.length ? m.rolling[m.rolling.length - 1] : null;
  const first = m.rolling.length ? m.rolling[0] : null;
  const thisWeek = m.adherence.find((a) => a.week === m.currentWeek);
  const tt = d.tests.filter((t) => t.test_key === "five_k_sec").sort((a, b) => a.value - b.value)[0];
  const best5k = Math.min(...[tt ? tt.value : Infinity, ...d.activities.filter((a) => a.best_5k_s).map((a) => a.best_5k_s), ...m.runs.filter((r) => r.distance_km >= 4.95 && r.distance_km <= 5.3 && r.time_sec).map((r) => r.time_sec)]);
  const liftSessions = d.workouts.filter((w) => w.kind === "lift" && w.status === "done").length;
  const t = (label, value, delta) => h("div", { class: "tile" }, h("div", { class: "label" }, label), h("div", { class: "value" }, value), delta ? h("div", { class: "delta" }, delta) : null);
  return h("div", { class: "tiles" },
    t("Weight (7-day avg)", latest ? `${latest.kg.toFixed(1)} kg` : "–", latest && first && latest.date !== first.date ? `${(latest.kg - first.kg >= 0 ? "+" : "")}${(latest.kg - first.kg).toFixed(1)} kg since ${fmtShort(first.date)}` : "Log a morning weight on Today"),
    t("To goal", latest ? `${Math.max(0, latest.kg - goal).toFixed(1)} kg` : `${goal} kg goal`, latest ? `goal ${goal} kg` : null),
    t("This week", thisWeek ? `${thisWeek.done} of ${thisWeek.planned}` : "–", `week ${m.currentWeek} sessions done`),
    t("Best 5 km", isFinite(best5k) ? fmtTime(best5k) : "–", `target ${fmtTime(Number(d.settings.five_k_target_sec) || PROGRAM.running.fiveKTargetSec)}, ${liftSessions} lift sessions done`));
}

// ---------- cards ----------
function card(title, subtitle, cls = "") {
  const c = h("div", { class: `card ${cls}` });
  c.appendChild(h("div", { class: "card-title" }, h("h3", null, title), subtitle ? h("span", { class: "muted small" }, subtitle) : null));
  return c;
}
function empty(text) { return h("p", { class: "muted small" }, text); }

function weightCard(m, d) {
  const c = card("Body weight", "daily, 7-day average and goal");
  if (!m.weights.length) { c.appendChild(empty("No weigh-ins yet. Enter your morning weight on the Today screen.")); return c; }
  const goal = Number(d.settings.goal_weight_kg) || PROGRAM.body.goalWeightKg;
  const canvas = h("canvas");
  c.appendChild(h("div", { class: "chart-box" }, canvas));
  const labels = m.weights.map((w) => w.date);
  requestAnimationFrame(() => lineChart(canvas, { labels, xLabels: fmtDateTick, yFormatter: (v) => `${Number(v).toFixed(1)} kg`,
    datasets: [
      dataset("Weigh-in", m.weights.map((w) => w.kg), 7, { showLine: false, pointRadius: 3 }),
      dataset("7-day average", m.rolling.map((w) => Math.round(w.kg * 100) / 100), 0, { pointRadius: 0, borderWidth: 2.5 }),
    ], annotationLines: [{ label: `Goal ${goal} kg`, value: goal, color: PALETTE[2] }] }));
  const weekly = new Map();
  for (const w of m.weights) { const wk = weekNumber(w.date, m.start); const arr = weekly.get(wk) || []; arr.push(w.kg); weekly.set(wk, arr); }
  const rows = [...weekly.entries()].sort((a, b) => a[0] - b[0]);
  if (rows.length) {
    const table = h("table", null, h("thead", null, h("tr", null, h("th", null, "Week"), h("th", { class: "num" }, "Avg kg"), h("th", { class: "num" }, "Change"), h("th", { class: "num" }, "Weigh-ins"))), h("tbody", null,
      rows.slice(-8).map(([wk, arr], i, all) => {
        const avg = arr.reduce((s, x) => s + x, 0) / arr.length;
        const prev = i > 0 ? all[i - 1][1] : null;
        const pavg = prev ? prev.reduce((s, x) => s + x, 0) / prev.length : null;
        return h("tr", null, h("td", null, wk >= 1 ? String(wk) : "pre"), h("td", { class: "num" }, avg.toFixed(1)), h("td", { class: "num" }, pavg != null ? (avg - pavg >= 0 ? "+" : "") + (avg - pavg).toFixed(1) : ""), h("td", { class: "num" }, String(arr.length)));
      })));
    c.appendChild(h("div", { class: "table-wrap", style: { marginTop: ".5rem" } }, table));
    c.appendChild(h("p", { class: "muted small" }, "Aim for 0.4 to 0.6 kg a week. Two flat weeks means cutting 200 kcal a day."));
  }
  return c;
}

function adherenceCard(m) {
  const c = card("Sessions", "planned days by week");
  if (!m.adherence.length) { c.appendChild(empty("The plan has not started yet.")); return c; }
  const grid = h("div", { class: "heatmap" });
  grid.appendChild(h("div", { class: "hm-label" }, ""));
  for (const dn of ["M", "T", "W", "T", "F", "S", "S"]) grid.appendChild(h("div", { class: "hm-label", style: { textAlign: "center" } }, dn));
  for (const wk of m.adherence.slice(-16)) {
    grid.appendChild(h("div", { class: "hm-label" }, `W${wk.week}`));
    for (const day of wk.days) {
      const cls = ["hm-cell", day.status === "done" ? "done" : day.status === "skipped" ? "skipped" : day.status === "in_progress" ? "partial" : day.planned ? "planned" : "", day.future ? "future" : ""].join(" ");
      grid.appendChild(h("a", { class: cls, href: `/day/${day.date}`, title: `${fmtDay(day.date)}: ${day.status || (day.planned ? "planned" : "rest")}` }));
    }
  }
  c.appendChild(grid);
  const total = m.adherence.filter((w) => w.week < m.currentWeek).reduce((s, w) => s + w.done, 0);
  const planned = m.adherence.filter((w) => w.week < m.currentWeek).reduce((s, w) => s + w.planned, 0);
  c.appendChild(h("p", { class: "muted small", style: { marginTop: ".5rem" } }, planned ? `${total} of ${planned} planned sessions done in finished weeks (${Math.round((100 * total) / planned)}%).` : "Green = done, yellow = started, red = skipped, grey = planned."));
  return c;
}

function liftCard(m) {
  const c = card("Lift progression", "one lift at a time");
  const kgLifts = m.lifts.filter((l) => l.ex.fields.includes("kg") && l.ex.fields.includes("reps") && l.sessions.some((s) => s.top != null));
  if (!kgLifts.length) { c.appendChild(empty("Log a lifting session and the chart appears here. Estimated 1RM uses the Epley formula from your heaviest set.")); return c; }
  const saved = store.get("ft_lift_pick");
  const select = h("select", null, kgLifts.map((l) => h("option", { value: l.key, selected: l.key === saved }, `${l.ex.short || l.ex.name} (${l.count})`)));
  const metric = h("select", null, [["e1rm", "Estimated 1RM"], ["top", "Top set weight"], ["volume", "Total volume"]].map(([v, l]) => h("option", { value: v }, l)));
  c.appendChild(h("div", { class: "chart-controls" }, select, metric));
  const canvas = h("canvas");
  c.appendChild(h("div", { class: "chart-box" }, canvas));
  const detail = h("div", { class: "table-wrap", style: { marginTop: ".5rem" } });
  c.appendChild(detail);
  const draw = () => {
    const l = kgLifts.find((x) => x.key === select.value) || kgLifts[0];
    store.set("ft_lift_pick", l.key);
    const labels = l.sessions.map((s) => s.date);
    const met = metric.value;
    const data = l.sessions.map((s) => (met === "e1rm" ? (s.e1rm ? Math.round(s.e1rm * 10) / 10 : null) : met === "top" ? s.top : Math.round(s.volume)));
    lineChart(canvas, { labels, xLabels: fmtDateTick, yFormatter: (v) => `${v} kg`, datasets: [dataset(met === "e1rm" ? "Est. 1RM" : met === "top" ? "Top set" : "Volume", data, 0)] });
    clear(detail);
    detail.appendChild(h("table", null, h("thead", null, h("tr", null, h("th", null, "Date"), h("th", null, "Sets"), h("th", { class: "num" }, "Top"), h("th", { class: "num" }, "Est. 1RM"), h("th", { class: "num" }, "Volume"))),
      h("tbody", null, l.sessions.slice(-8).reverse().map((s) => h("tr", null, h("td", null, fmtShort(s.date)), h("td", null, s.sets.map((x) => `${fmtKg(x.weight_kg) || 0}×${x.reps ?? 0}`).join(", ")), h("td", { class: "num" }, s.top != null ? `${fmtKg(s.top)}×${s.topReps}` : ""), h("td", { class: "num" }, s.e1rm ? s.e1rm.toFixed(1) : ""), h("td", { class: "num" }, Math.round(s.volume)))))));
  };
  select.addEventListener("change", draw); metric.addEventListener("change", draw);
  requestAnimationFrame(draw);
  return c;
}

function overlayCard(m) {
  const c = card("Lifts compared", "several lifts on one chart");
  const kgLifts = m.lifts.filter((l) => l.ex.fields.includes("kg") && l.ex.fields.includes("reps") && l.sessions.some((s) => s.e1rm));
  if (!kgLifts.length) { c.appendChild(empty("Needs a few logged lifting sessions.")); return c; }
  const picked = new Set(store.get("ft_overlay_pick", kgLifts.slice(0, 4).map((l) => l.key)));
  const relative = h("input", { type: "checkbox", checked: store.get("ft_overlay_rel", true) });
  const chips = h("div", { class: "chart-controls" });
  kgLifts.forEach((l, i) => {
    const chip = h("span", { class: "chip" + (picked.has(l.key) ? " active" : ""), onClick: () => { picked.has(l.key) ? picked.delete(l.key) : picked.add(l.key); chip.classList.toggle("active"); store.set("ft_overlay_pick", [...picked]); draw(); } },
      h("span", { class: "sw", style: { background: PALETTE[i % PALETTE.length] } }), l.ex.short || l.ex.name);
    chips.appendChild(chip);
  });
  c.appendChild(chips);
  c.appendChild(h("label", { class: "row small", style: { marginBottom: ".4rem" } }, relative, "Show as % of first session (lets barbell and dumbbell lifts share one scale)"));
  const canvas = h("canvas");
  c.appendChild(h("div", { class: "chart-box tall" }, canvas));
  const draw = () => {
    store.set("ft_overlay_rel", relative.checked);
    const dates = [...new Set(kgLifts.filter((l) => picked.has(l.key)).flatMap((l) => l.sessions.map((s) => s.date)))].sort();
    const datasets = kgLifts.map((l, i) => {
      if (!picked.has(l.key)) return null;
      const first = l.sessions.find((s) => s.e1rm);
      const map = new Map(l.sessions.filter((s) => s.e1rm).map((s) => [s.date, relative.checked && first ? Math.round((1000 * s.e1rm) / first.e1rm) / 10 : Math.round(s.e1rm * 10) / 10]));
      return dataset(l.ex.short || l.ex.name, dates.map((d) => map.get(d) ?? null), i, { spanGaps: true });
    }).filter(Boolean);
    lineChart(canvas, { labels: dates, xLabels: fmtDateTick, yFormatter: (v) => relative.checked ? `${v}%` : `${v} kg`, datasets });
  };
  relative.addEventListener("change", draw);
  requestAnimationFrame(draw);
  return c;
}

function runCard(m, d) {
  const c = card("Running", "pace per run and 5 km time");
  if (!m.runs.length && !d.activities.length) { c.appendChild(empty("Log a run (distance and time) or attach a Garmin file.")); return c; }
  const target = Number(d.settings.five_k_target_sec) || PROGRAM.running.fiveKTargetSec;
  const points = m.runs.map((w) => {
    const a = m.actByWorkout.get(w.id);
    const dist = w.distance_km || (a && a.distance_m ? a.distance_m / 1000 : null);
    const sec = w.time_sec || (a && a.duration_s) || null;
    return { date: w.date, key: w.template_key, name: templateFor(w.template_key).name, dist, sec, pace: dist && sec ? sec / dist : null, hr: w.avg_hr || (a && a.avg_hr) || null, best5k: a && a.best_5k_s ? a.best_5k_s : null };
  }).filter((p) => p.pace);
  const canvas = h("canvas");
  c.appendChild(h("div", { class: "chart-box" }, canvas));
  const kinds = [["time_trial_5k", "5 km time trial"], ["intervals", "Intervals"], ["easy_run", "Easy run"], ["other", "Other"]];
  const labels = points.map((p) => p.date);
  const datasets = kinds.map(([k, name], i) => dataset(name, points.map((p) => (p.key === k || (k === "intervals" && p.key.startsWith("intervals")) || (k === "other" && !["time_trial_5k", "easy_run"].includes(p.key) && !p.key.startsWith("intervals")) ? Math.round(p.pace) : null)), i, { showLine: false, pointRadius: 5 }));
  requestAnimationFrame(() => lineChart(canvas, { labels, xLabels: fmtDateTick, yFormatter: (v) => fmtPace(v), yReverse: true, datasets, annotationLines: [{ label: "5 km target pace", value: Math.round(target / 5), color: PALETTE[2] }] }));
  const tts = [...d.tests.filter((t) => t.test_key === "five_k_sec").map((t) => ({ date: t.date, sec: t.value, src: "test" })), ...points.filter((p) => p.key === "time_trial_5k" && p.sec).map((p) => ({ date: p.date, sec: p.sec, src: "run" }))];
  const seen = new Set();
  const uniq = tts.filter((t) => { if (seen.has(t.date)) return false; seen.add(t.date); return true; }).sort((a, b) => a.date.localeCompare(b.date));
  const table = h("table", null, h("thead", null, h("tr", null, h("th", null, "Date"), h("th", null, "Run"), h("th", { class: "num" }, "km"), h("th", { class: "num" }, "Time"), h("th", { class: "num" }, "Pace"), h("th", { class: "num" }, "HR"))),
    h("tbody", null, points.slice(-10).reverse().map((p) => h("tr", null, h("td", null, fmtShort(p.date)), h("td", null, p.name + (p.best5k ? ` (best 5 km ${fmtTime(p.best5k)})` : "")), h("td", { class: "num" }, p.dist ? p.dist.toFixed(2) : ""), h("td", { class: "num" }, fmtTime(p.sec)), h("td", { class: "num" }, fmtPace(p.pace)), h("td", { class: "num" }, p.hr || "")))));
  c.appendChild(h("div", { class: "table-wrap", style: { marginTop: ".5rem" } }, table));
  if (uniq.length) c.appendChild(h("p", { class: "small", style: { marginTop: ".5rem" } }, "5 km time trials: " + uniq.map((t) => `${fmtShort(t.date)} ${fmtTime(t.sec)}`).join(" · ") + `. Target ${fmtTime(target)}.`));
  return c;
}

function nutritionCard(m, d) {
  const c = card("Nutrition", "from MyFitnessPal exports");
  if (!d.nutrition.length) { c.appendChild(empty("Upload a MyFitnessPal CSV export on the Data page. Targets: about 2,450 kcal and 170 g protein a day.")); return c; }
  const kcalT = Number(d.settings.calorie_target) || PROGRAM.nutrition.calories;
  const protT = Number(d.settings.protein_target) || PROGRAM.nutrition.proteinG;
  const days = d.nutrition.slice(-42);
  const canvas = h("canvas");
  c.appendChild(h("div", { class: "chart-box" }, canvas));
  requestAnimationFrame(() => barChart(canvas, { labels: days.map((n) => n.date), xLabels: fmtDateTick, yFormatter: (v) => `${v}`,
    y1Title: "protein g",
    datasets: [{ label: "kcal", data: days.map((n) => Math.round(n.calories)), backgroundColor: PALETTE[1] + "aa" }, { type: "line", label: "protein g", data: days.map((n) => Math.round(n.protein_g)), borderColor: PALETTE[2], backgroundColor: PALETTE[2], pointRadius: 2, borderWidth: 2, yAxisID: "y1", tension: 0.2 }],
    annotationLines: [{ label: `kcal target ${kcalT}`, value: kcalT, color: PALETTE[1] }, { label: `protein target ${protT}`, value: protT, color: PALETTE[2], axis: "y1" }] }));
  const byWeek = new Map();
  for (const n of d.nutrition) { const wk = weekNumber(n.date, m.start); const arr = byWeek.get(wk) || []; arr.push(n); byWeek.set(wk, arr); }
  const avg = (arr, k) => arr.reduce((s, x) => s + (x[k] || 0), 0) / arr.length;
  c.appendChild(h("div", { class: "table-wrap", style: { marginTop: ".5rem" } }, h("table", null,
    h("thead", null, h("tr", null, h("th", null, "Week"), h("th", { class: "num" }, "Days"), h("th", { class: "num" }, "kcal"), h("th", { class: "num" }, "Protein"), h("th", { class: "num" }, "Carbs"), h("th", { class: "num" }, "Fat"), h("th", { class: "num" }, "Sugar"))),
    h("tbody", null, [...byWeek.entries()].sort((a, b) => b[0] - a[0]).slice(0, 8).map(([wk, arr]) => h("tr", null, h("td", null, wk >= 1 ? String(wk) : "pre"), h("td", { class: "num" }, String(arr.length)), h("td", { class: "num", style: { color: avg(arr, "calories") > kcalT + 150 ? "var(--danger)" : "inherit" } }, Math.round(avg(arr, "calories"))), h("td", { class: "num", style: { color: avg(arr, "protein_g") < protT - 20 ? "var(--warn)" : "inherit" } }, Math.round(avg(arr, "protein_g"))), h("td", { class: "num" }, Math.round(avg(arr, "carbs_g"))), h("td", { class: "num" }, Math.round(avg(arr, "fat_g"))), h("td", { class: "num" }, Math.round(avg(arr, "sugar_g")))))))));
  return c;
}

function testsCard(d) {
  const c = card("Performance tests", "weeks 1, 8 and 16");
  if (!d.tests.length) { c.appendChild(empty("Test week numbers show up here: 5 km, broad jump, single leg hops, shuttle and 3RMs.")); return c; }
  const weeks = [...new Set(d.tests.map((t) => t.week_no))].sort((a, b) => a - b);
  const table = h("table", null, h("thead", null, h("tr", null, h("th", null, "Test"), weeks.map((w) => h("th", { class: "num" }, `Week ${w}`)))),
    h("tbody", null, PROGRAM.tests.map((def) => {
      const row = h("tr", null, h("td", null, def.name));
      for (const w of weeks) {
        const t = d.tests.find((x) => x.test_key === def.key && x.week_no === w);
        row.appendChild(h("td", { class: "num" }, t ? (def.input === "time" ? fmtTime(t.value) : `${t.value} ${def.unit}`) : ""));
      }
      return row;
    })));
  c.appendChild(h("div", { class: "table-wrap" }, table));
  const last = weeks[weeks.length - 1];
  const L = d.tests.find((x) => x.test_key === "slh_left_cm" && x.week_no === last), R = d.tests.find((x) => x.test_key === "slh_right_cm" && x.week_no === last);
  if (L && R && L.value && R.value) {
    const ratio = Math.min(L.value, R.value) / Math.max(L.value, R.value);
    c.appendChild(h("p", { class: "small", style: { marginTop: ".5rem", color: ratio < 0.9 ? "var(--danger)" : "var(--ok)" } }, `Single leg hop symmetry: ${Math.round(ratio * 100)}% (${ratio < 0.9 ? "below 90%, do extra single leg work on the weaker side" : "fine"}).`));
  }
  return c;
}

function bestsCard(m) {
  const c = card("Personal bests", "heaviest set and best estimated 1RM");
  const rows = m.lifts.filter((l) => l.sessions.some((s) => s.top != null)).map((l) => {
    let bestTop = null, bestE = null;
    for (const s of l.sessions) {
      if (s.top != null && (!bestTop || s.top > bestTop.top || (s.top === bestTop.top && (s.topReps || 0) > (bestTop.topReps || 0)))) bestTop = s;
      if (s.e1rm && (!bestE || s.e1rm > bestE.e1rm)) bestE = s;
    }
    return { l, bestTop, bestE };
  });
  const others = m.lifts.filter((l) => !l.sessions.some((s) => s.top != null));
  if (!rows.length && !others.length) { c.appendChild(empty("Bests appear once sets are logged.")); return c; }
  c.appendChild(h("div", { class: "table-wrap" }, h("table", null, h("thead", null, h("tr", null, h("th", null, "Exercise"), h("th", { class: "num" }, "Heaviest set"), h("th", { class: "num" }, "Est. 1RM"), h("th", { class: "num" }, "Sessions"))),
    h("tbody", null,
      rows.map(({ l, bestTop, bestE }) => h("tr", null, h("td", null, l.ex.short || l.ex.name), h("td", { class: "num" }, bestTop ? `${fmtKg(bestTop.top)} kg × ${bestTop.topReps} (${fmtShort(bestTop.date)})` : ""), h("td", { class: "num" }, bestE ? `${bestE.e1rm.toFixed(1)} kg` : ""), h("td", { class: "num" }, String(l.count)))),
      others.map((l) => { const best = l.ex.fields.includes("seconds") ? `${Math.max(...l.sessions.map((s) => s.bestSeconds))} s` : `${Math.max(...l.sessions.map((s) => s.bestReps))} reps`; return h("tr", null, h("td", null, l.ex.short || l.ex.name), h("td", { class: "num" }, best), h("td", { class: "num" }, ""), h("td", { class: "num" }, String(l.count))); })))));
  return c;
}
