import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDay, scheduledTemplateKey, weekNumber, planHorizon, endOfMonth, liftRotation } from "../public/js/program.js";

const settings = { program_start_date: "2026-10-26" };

test("week 1 schedule follows the plan", () => {
  assert.equal(resolveDay("2026-10-26", settings).templateKey, "lift_a");
  assert.equal(resolveDay("2026-10-27", settings).templateKey, "intervals_6x2", "no time trial in week 1 since the restart");
  assert.equal(resolveDay("2026-10-27", settings).testWeek, false);
  assert.equal(resolveDay("2026-10-29", settings).templateKey, "easy_run");
  assert.equal(weekNumber("2026-12-15", "2026-10-26"), 8);
  assert.equal(scheduledTemplateKey("2026-12-15", 8), "time_trial_5k");
});

test("an override replaces the planned session and is flagged as moved", () => {
  const s = { ...settings, overrides: { "2026-10-27": "lift_a", "2026-10-26": "intervals_6x2" } };
  const tue = resolveDay("2026-10-27", s);
  assert.equal(tue.templateKey, "lift_a");
  assert.equal(tue.defaultTemplateKey, "intervals_6x2");
  assert.equal(tue.moved, true);
  assert.equal(tue.plan.length > 0, true, "lift plan is built for the moved day");
  assert.equal(resolveDay("2026-10-26", s).templateKey, "intervals_6x2");
  assert.equal(resolveDay("2026-10-28", s).moved, false);
});

test("an unknown override key falls back to the plan", () => {
  const s = { ...settings, overrides: { "2026-10-27": "nope" } };
  assert.equal(resolveDay("2026-10-27", s).templateKey, "intervals_6x2");
});

test("the default start is a Monday and days before it are flagged", () => {
  const d = resolveDay("2026-11-09", {});
  assert.equal(d.week, 1);
  assert.equal(d.templateKey, "lift_a");
  const before = resolveDay("2026-10-26", {});
  assert.equal(before.beforeStart, true);
  assert.equal(before.week, -1);
});

test("the plan is concrete through next month, an estimate for five more, then empty", () => {
  const today = "2026-11-10";
  assert.deepEqual(planHorizon("2026-06-24", today).horizon, "concrete", "the past stays concrete");
  assert.equal(planHorizon("2026-11-10", today).horizon, "concrete");
  assert.equal(planHorizon("2026-12-31", today).horizon, "concrete");
  assert.equal(planHorizon("2027-01-01", today).horizon, "estimate");
  assert.equal(planHorizon("2027-05-31", today).horizon, "estimate");
  assert.equal(planHorizon("2027-06-01", today).horizon, "none");
  assert.equal(planHorizon("2027-06-24", today).horizon, "none");
  assert.deepEqual(planHorizon("2027-06-24", today), { horizon: "none", concreteTo: "2026-12-31", estimateTo: "2027-05-31" });
});

test("the window rolls forward on the 1st, and month ends are right", () => {
  assert.equal(planHorizon("2027-01-31", "2026-11-30").horizon, "estimate");
  assert.equal(planHorizon("2027-01-31", "2026-12-01").horizon, "concrete");
  assert.equal(endOfMonth("2027-01-31", 1), "2027-02-28");
  assert.equal(endOfMonth("2026-12-15", 1), "2027-01-31", "across the year end");
  assert.equal(endOfMonth("2028-01-10", 1), "2028-02-29", "leap year");
});

test("resolveDay carries the horizon", () => {
  const d = resolveDay("2027-06-24", { ...settings, today: "2026-11-10" });
  assert.equal(d.horizon, "none");
  assert.equal(d.templateKey, "easy_run", "the template is still resolved, so moving and logging keep working");
  assert.equal(resolveDay("2026-11-12", { ...settings, today: "2026-11-10" }).horizon, "concrete");
});

test("a skipped lift leads the next week, and the week after is A, B, C again", () => {
  const s = { program_start_date: "2026-11-09", overrides: {} };
  // Week 1: Lift A done Monday, Lift B skipped, Lift C done Friday. Today is Sunday 15 Nov.
  const done = [{ date: "2026-11-09", template_key: "lift_a" }, { date: "2026-11-13", template_key: "lift_c" }];
  const rot = liftRotation(done, s, "2026-11-15");
  assert.equal(rot["2026-11-16"], "lift_b");
  assert.equal(rot["2026-11-18"], "lift_a");
  assert.equal(rot["2026-11-20"], "lift_c");
  assert.deepEqual([rot["2026-11-23"], rot["2026-11-25"], rot["2026-11-27"]], ["lift_a", "lift_b", "lift_c"]);
  // His week of 16 Nov: C on Saturday the 14th, the skipped B on Monday, A on Wednesday. Friday is C, then A, B, C.
  const real = liftRotation([{ date: "2026-11-09", template_key: "lift_a" }, { date: "2026-11-14", template_key: "lift_c" }, { date: "2026-11-16", template_key: "lift_b" }, { date: "2026-11-18", template_key: "lift_a" }], s, "2026-11-20");
  assert.deepEqual(["2026-11-20", "2026-11-23", "2026-11-25", "2026-11-27", "2026-11-30"].map((d) => real[d]), ["lift_c", "lift_a", "lift_b", "lift_c", "lift_a"]);
  assert.equal(rot["2026-11-17"], undefined, "run days are untouched");
  const mon = resolveDay("2026-11-16", { ...s, rotation: rot, today: "2026-11-15" });
  assert.equal(mon.templateKey, "lift_b");
  assert.equal(mon.rotated, true);
  assert.equal(mon.moved, false);
  assert.equal(mon.defaultTemplateKey, "lift_a");
});

test("a lift brought onto a run day counts for the week", () => {
  const s = { program_start_date: "2026-11-09", overrides: { "2026-11-23": "rest_walk" } };
  const week1 = ["lift_a", "lift_b", "lift_c"].map((k, i) => ({ date: ["2026-11-09", "2026-11-11", "2026-11-13"][i], template_key: k }));
  const week2 = ["lift_a", "lift_b", "lift_c"].map((k, i) => ({ date: ["2026-11-16", "2026-11-18", "2026-11-20"][i], template_key: k }));
  // Monday's Lift A was moved to Tuesday the 24th (a run day) and is on that day's list.
  const rot = liftRotation([...week1, ...week2, { date: "2026-11-24", template_key: "lift_a" }], s, "2026-11-24");
  assert.deepEqual([rot["2026-11-25"], rot["2026-11-27"], rot["2026-11-30"]], ["lift_b", "lift_c", "lift_a"]);
});

test("lift rotation: nothing skipped keeps the weekday plan, overrides win, and it can be switched off", () => {
  const s = { program_start_date: "2026-11-09", overrides: {} };
  const done = [{ date: "2026-11-09", template_key: "lift_a" }, { date: "2026-11-11", template_key: "lift_b" }, { date: "2026-11-13", template_key: "lift_c" }];
  const rot = liftRotation(done, s, "2026-11-15");
  assert.deepEqual([rot["2026-11-16"], rot["2026-11-18"], rot["2026-11-20"]], ["lift_a", "lift_b", "lift_c"]);
  assert.equal(resolveDay("2026-11-16", { ...s, rotation: rot, today: "2026-11-15" }).rotated, false);
  // Lift B moved to Tuesday by hand: Wednesday then gets C, not B again.
  const s2 = { ...s, overrides: { "2026-11-17": "lift_b" } };
  const rot2 = liftRotation([{ date: "2026-11-09", template_key: "lift_a" }], s2, "2026-11-15");
  assert.equal(rot2["2026-11-16"], "lift_b");
  assert.equal(rot2["2026-11-17"], undefined);
  assert.equal(rot2["2026-11-18"], "lift_c");
  assert.deepEqual(liftRotation(done, { ...s, lift_rotation: "0" }, "2026-11-15"), {});
  // A lift done today is kept on today, and the next lift day continues from it.
  const rot3 = liftRotation([{ date: "2026-11-09", template_key: "lift_a" }, { date: "2026-11-16", template_key: "lift_b" }], s, "2026-11-16");
  assert.equal(rot3["2026-11-16"], "lift_b");
  assert.equal(rot3["2026-11-18"], "lift_c");
  // Only B done so far: A was skipped, so A comes before C.
  const rot4 = liftRotation([{ date: "2026-11-16", template_key: "lift_b" }], s, "2026-11-16");
  assert.equal(rot4["2026-11-18"], "lift_a");
});
