import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveDay, scheduledTemplateKey, weekNumber } from "../public/js/program.js";

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
