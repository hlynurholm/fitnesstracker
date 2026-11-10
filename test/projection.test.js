import { test } from "node:test";
import assert from "node:assert/strict";
import { projectLift, projectFiveK, projectIntervalPace, projectBodyWeight, projectDay } from "../src/projection.js";
import { resolveDay, PROGRAM } from "../public/js/program.js";

const settings = { program_start_date: "2026-11-09" };
const squat = { key: "back_squat", sets: 4, startKg: 75 };

test("a lift with no history follows the plan rule and tapers", () => {
  // 75 kg start, 2.5 kg step every 2 weeks = 1.25 kg a week, fading over 12 weeks.
  const l = projectLift(squat, [], "2027-02-01", "2026-11-09"); // 12 weeks ahead
  const gain = 1.25 * 12 * (1 - Math.exp(-1)); // 9.48
  assert.equal(l.value, `about ${Math.round((75 + gain) / 2.5) * 2.5} kg`);
  assert.equal(l.value, "about 85 kg");
  assert.match(l.basis, /start 75 kg, one step every 2 weeks/);
  // Far out it levels off below start + rate * taper (90 kg), instead of growing for ever.
  assert.equal(projectLift(squat, [], "2028-11-09", "2026-11-09").value, "about 90 kg");
});

test("a lift with enough history follows the logged trend, capped at one step a week", () => {
  const steady = [{ date: "2026-11-09", top: 75 }, { date: "2026-11-16", top: 76.25 }, { date: "2026-11-23", top: 77.5 }, { date: "2026-11-30", top: 78.75 }]; // 1.25 kg a week
  const l = projectLift(squat, steady, "2026-12-28", "2026-12-01"); // 4 weeks after the last session
  assert.equal(l.value, "about 82.5 kg"); // 78.75 + 1.25 * 12 * (1 - e^(-1/3)) = 83.0, to the nearest 2.5
  assert.match(l.basis, /your trend over 4 sessions, last 78.8 kg/);
  const rocket = steady.map((s, i) => ({ ...s, top: 75 + i * 10 })); // 10 kg a week is capped at 2.5
  assert.equal(projectLift(squat, rocket, "2026-12-07", "2026-12-01").value, "about 107.5 kg"); // 105 + 2.5 * 12 * (1 - e^(-1/12)) = 107.4
  const falling = steady.map((s, i) => ({ ...s, top: 80 - i * 2.5 }));
  assert.equal(projectLift(squat, falling, "2027-03-01", "2026-12-01").value, "about 72.5 kg", "a falling trend projects flat, not down");
});

test("bodyweight exercises and lifts with nothing to start from are skipped", () => {
  assert.equal(projectLift({ key: "band_pull_up", sets: 4 }, [], "2027-02-01", "2026-11-09"), null);
  assert.equal(projectLift({ key: "db_bench", sets: 4 }, [], "2027-02-01", "2026-11-09"), null);
  assert.match(projectLift({ key: "db_bench", sets: 4 }, [{ date: "2026-11-09", top: 30 }], "2027-02-01", "2026-11-09").value, /per hand$/);
});

test("5 km goes from the starting point to the target at week 16, then towards the stretch", () => {
  // Plan: 31:30 on 2026-11-09, 28:00 on 2027-03-01 (16 weeks), 26:00 on 2027-06-21.
  assert.equal(projectFiveK(settings, null, "2027-01-04").value, "about 29:45 (5:57/km)"); // half way: 1890 - 105
  assert.equal(projectFiveK(settings, null, "2027-03-01").value, "about 28:00 (5:36/km)");
  assert.equal(projectFiveK(settings, null, "2027-04-26").value, "about 27:00 (5:24/km)"); // half way to the stretch
  assert.equal(projectFiveK(settings, null, "2028-01-01").value, "about 26:00 (5:12/km)", "flat after the stretch");
  // A real test replaces the starting point; one already under the target never projects slower.
  assert.match(projectFiveK(settings, { date: "2026-12-15", value: 1740 }, "2027-03-01").value, /about 28:00/);
  assert.match(projectFiveK(settings, { date: "2026-12-15", value: 1620 }, "2027-03-01").value, /about 27:00/);
});

test("interval pace follows the plan's 5 s every 2 weeks within the planned weeks", () => {
  const t = PROGRAM.templates.intervals_4x4; // 5:30/km from week 9
  assert.equal(projectIntervalPace(t, 9).value, "about 5:30/km");
  assert.equal(projectIntervalPace(t, 12).value, "about 5:25/km");
  assert.equal(projectIntervalPace(t, 16).value, "about 5:15/km");
  assert.equal(projectIntervalPace(t, 30).value, "about 5:15/km", "held after the plan ends");
  assert.equal(projectIntervalPace(PROGRAM.templates.easy_run, 12), null);
});

test("body weight loses 0.4 to 0.6 kg a week from the 7-day average and stops at the goal", () => {
  const weighIns = [{ date: "2026-11-10", weight_kg: 92 }, { date: "2026-11-06", weight_kg: 93 }, { date: "2026-10-20", weight_kg: 99 }]; // average of the last 7 days: 92.5
  assert.equal(projectBodyWeight({}, weighIns, "2027-01-19", "2026-11-10").value, "86.5 kg to 88.5 kg"); // 10 weeks: 92.5 - 6 and 92.5 - 4
  assert.equal(projectBodyWeight({}, weighIns, "2027-03-16", "2026-11-10").value, "85 kg to 85.5 kg"); // 18 weeks: the fast end has reached the goal
  assert.equal(projectBodyWeight({}, weighIns, "2027-12-01", "2026-11-10").value, "85 kg, the goal");
  assert.match(projectBodyWeight({}, [], "2027-01-19", "2026-11-10").basis, /93 kg starting weight/);
});

test("a day's projection has the lines for its kind", () => {
  const today = "2026-11-10";
  const lift = resolveDay("2027-01-11", { ...settings, today }); // Monday: Lift A
  const run = resolveDay("2027-01-12", { ...settings, today }); // Tuesday: intervals
  const rest = resolveDay("2027-01-16", { ...settings, today });
  const history = { lifts: {}, fiveK: null, weighIns: [] };
  assert.deepEqual(projectDay(lift, settings, history, today).lines.map((l) => l.label), ["Back squat", "Body weight"]);
  assert.deepEqual(projectDay(run, settings, history, today).lines.map((l) => l.label), ["Interval pace", "5 km", "Body weight"]);
  assert.deepEqual(projectDay(rest, settings, history, today).lines.map((l) => l.label), ["Body weight"]);
});
