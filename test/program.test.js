import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDay, scheduledTemplateKey, weekNumber, planHorizon, endOfMonth } from "../public/js/program.js";

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
