// Projections for estimated days: where lift weights, running pace and body weight would be on a future date if
// things go to plan. Rough by design. Each line says what it is based on, and the logged data takes over from the
// plan's rules as soon as there is enough of it.
//
// The assumptions are the numbers in PROGRAM.projection (public/js/program.js). Everything here is a pure function of
// the day, today's date and a little history, so it can be tested without a database.
import { PROGRAM, exerciseFor, addDays, daysBetween, mondayOf, weekNumber, fmtTime, fmtPace, parseTime } from "../public/js/program.js";

const round = (v, step) => Math.round(v / step) * step;
const kg = (v) => `${Math.round(v * 10) / 10} kg`;

// Least squares slope of y over x.
function slope(points) {
  const n = points.length;
  const mx = points.reduce((s, p) => s + p.x, 0) / n, my = points.reduce((s, p) => s + p.y, 0) / n;
  const den = points.reduce((s, p) => s + (p.x - mx) ** 2, 0);
  return den ? points.reduce((s, p) => s + (p.x - mx) * (p.y - my), 0) / den : 0;
}

// Straight lines between (date, value) points; flat after the last one.
function along(points, date) {
  for (let i = 1; i < points.length; i++) {
    const [d0, v0] = points[i - 1], [d1, v1] = points[i];
    if (date <= d1) { const span = daysBetween(d0, d1); return span > 0 ? v0 + (v1 - v0) * Math.min(1, Math.max(0, daysBetween(d0, date) / span)) : v1; }
  }
  return points[points.length - 1][1];
}

// One lift. sessions: [{ date, top }] oldest first, top = heaviest logged set that day.
// Gains taper off: the weekly rate fades over liftTaperWeeks, so a five month estimate is not five months of
// straight-line progress.
export function projectLift(entry, sessions, date, today) {
  const ex = exerciseFor(entry.key);
  if (!ex.fields.includes("kg") || ex.kgOptional) return null;
  const P = PROGRAM.projection, step = ex.increment || 2.5;
  const last = sessions[sessions.length - 1];
  const from = last ? last.top : entry.startKg;
  if (!from) return null;
  const enough = sessions.length >= P.liftTrendMinSessions && daysBetween(sessions[0].date, last.date) >= 14;
  // Own trend when there is one, never faster than one step a week and never negative. Otherwise the plan's rule.
  const rate = enough ? Math.min(step, Math.max(0, slope(sessions.map((s) => ({ x: daysBetween(sessions[0].date, s.date) / 7, y: s.top })))))
    : step / P.liftStepEveryWeeks;
  const weeks = Math.max(0, daysBetween(last ? last.date : today, date) / 7);
  const gain = rate * P.liftTaperWeeks * (1 - Math.exp(-weeks / P.liftTaperWeeks));
  return {
    label: ex.short || ex.name,
    value: `about ${kg(round(from + gain, step))}${ex.kgHint === "per hand" ? " per hand" : ""}`,
    basis: enough ? `your trend over ${sessions.length} sessions, last ${kg(last.top)}` : last ? `last ${kg(last.top)}, one step every ${P.liftStepEveryWeeks} weeks` : `start ${kg(from)}, one step every ${P.liftStepEveryWeeks} weeks`,
  };
}

// 5 km time: from the latest test (or the plan's starting point) to the target at the end of the planned weeks,
// then on to the stretch target over the same span again.
export function projectFiveK(settings, lastTest, date) {
  const start = mondayOf(settings.program_start_date || PROGRAM.startDateDefault);
  const planEnd = addDays(start, PROGRAM.plannedWeeks * 7), stretchEnd = addDays(planEnd, PROGRAM.plannedWeeks * 7);
  const anchor = lastTest && lastTest.value ? [lastTest.date, lastTest.value] : [start, PROGRAM.running.fiveKBaselineSec];
  const target = Math.min(anchor[1], Number(settings.five_k_target_sec) || PROGRAM.running.fiveKTargetSec);
  const stretch = Math.min(target, PROGRAM.running.fiveKStretchSec);
  const points = anchor[0] < planEnd ? [anchor, [planEnd, target], [stretchEnd, stretch]] : [anchor, [stretchEnd, stretch]];
  const sec = Math.round(along(points, date));
  return {
    label: "5 km",
    value: `about ${fmtTime(sec)} (${fmtPace(sec / 5)})`,
    basis: lastTest && lastTest.value ? `from your ${fmtTime(lastTest.value)} on ${lastTest.date} towards the ${fmtTime(target)} target` : `from the ${fmtTime(anchor[1])} starting point towards the ${fmtTime(target)} target`,
  };
}

// Interval pace by the plan's own rule, within the planned weeks. After that it is held.
export function projectIntervalPace(template, week) {
  const sec = template.intervals && template.pace ? parseTime(template.pace.replace("/km", "")) : null;
  if (!sec) return null;
  const P = PROGRAM.projection;
  const blockStart = week <= 4 ? 1 : week <= 8 ? 5 : 9;
  const steps = Math.max(0, Math.floor((Math.min(week, PROGRAM.plannedWeeks) - blockStart) / P.paceStepEveryWeeks));
  return { label: "Interval pace", value: `about ${fmtPace(sec - steps * P.paceStepSec)}`, basis: `${template.pace} now, ${P.paceStepSec} s/km faster every ${P.paceStepEveryWeeks} weeks if the last rep felt controlled` };
}

// Body weight: the plan's loss per week from the current 7-day average, never below the goal.
// weighIns: [{ date, weight_kg }] newest first.
export function projectBodyWeight(settings, weighIns, date, today) {
  const goal = Number(settings.goal_weight_kg) || PROGRAM.body.goalWeightKg;
  const latest = weighIns[0];
  const week = latest ? weighIns.filter((b) => daysBetween(b.date, latest.date) < 7) : [];
  const from = week.length ? week.reduce((s, b) => s + b.weight_kg, 0) / week.length : PROGRAM.body.startWeightKg;
  const weeks = Math.max(0, daysBetween(latest ? latest.date : today, date) / 7);
  const [slow, fast] = PROGRAM.nutrition.lossPerWeekKg;
  const high = Math.max(goal, from - slow * weeks), low = Math.max(goal, from - fast * weeks);
  return {
    label: "Body weight",
    value: high <= goal ? `${kg(goal)}, the goal` : low <= goal ? `${kg(goal)} to ${kg(round(high, 0.5))}` : `${kg(round(low, 0.5))} to ${kg(round(high, 0.5))}`,
    basis: `${kg(from)} ${latest ? "7-day average" : "starting weight"}, losing ${slow} to ${fast} kg a week`,
  };
}

// Everything for one estimated day. history: { lifts: { key: [{date, top}] }, fiveK: {date, value} | null, weighIns: [...] }
export function projectDay(day, settings, history, today) {
  const lines = [];
  const kind = day.template.kind;
  if (kind === "lift") for (const e of day.plan) { const l = projectLift(e, history.lifts[e.key] || [], day.date, today); if (l) lines.push(l); }
  if (kind === "run") {
    const pace = projectIntervalPace(day.template, weekNumber(day.date, settings.program_start_date || PROGRAM.startDateDefault));
    if (pace) lines.push(pace);
    lines.push(projectFiveK(settings, history.fiveK, day.date));
  }
  lines.push(projectBodyWeight(settings, history.weighIns || [], day.date, today));
  return { lines, note: "Projections, not targets. They follow your logged numbers where there are enough, and the plan's rules where there are not, so they sharpen as you log more." };
}
