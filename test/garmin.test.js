import test from "node:test";
import assert from "node:assert/strict";
import { unzip, flattenMetrics } from "../src/garmin.js";
import { makeZip } from "./fixtures/make-zip.js";
import { makeFit } from "./fixtures/make-fit.js";
import { isFit } from "../src/parsers/fit.js";

test("unzip returns a deflated entry byte for byte", async () => {
  const fit = makeFit();
  const entries = await unzip(makeZip("111_ACTIVITY.fit", fit));
  assert.equal(entries.length, 1);
  assert.equal(entries[0].name, "111_ACTIVITY.fit");
  assert.ok(isFit(entries[0].bytes));
  assert.deepEqual(Buffer.from(entries[0].bytes), Buffer.from(fit));
});

test("unzip returns a stored entry", async () => {
  const entries = await unzip(makeZip("note.txt", new TextEncoder().encode("hello"), { deflate: false }));
  assert.equal(new TextDecoder().decode(entries[0].bytes), "hello");
});

test("unzip rejects data that is not a zip", async () => {
  await assert.rejects(() => unzip(new Uint8Array(64)), /Not a zip/);
});

test("flattenMetrics keeps measurements and drops identifiers, timestamps and lists", () => {
  const day = {
    uuid: "x", userProfilePk: 7, calendarDate: "2026-11-10", source: "garmin", includesWellnessData: true,
    movement: { steps: { goal: 9000, value: 8123, distanceInMeters: 6100.5 } },
    heartRate: { restingValue: 51, minValue: null },
    stress: { qualifier: "balanced" },
    bodyBattery: { maxValue: 90, featureVersion: "3.0", activityEvents: [{ a: 1 }], dynamicFeedbackEvent: { eventTimestampGmt: "2026-11-10T08:00:00.0", bodyBatteryLevel: "HIGH" } },
    wellnessChronology: { totalDurationInMillis: 1 },
  };
  assert.deepEqual(flattenMetrics(day), { "movement.steps.goal": 9000, "movement.steps.value": 8123, "movement.steps.distanceInMeters": 6100.5, "heartRate.restingValue": 51, "stress.qualifier": "balanced", "bodyBattery.maxValue": 90 });
  assert.deepEqual(flattenMetrics({ lastNightAvg: 58, status: "BALANCED", createTimeStamp: "2026-11-10T07:00:00.0" }, "hrv"), { "hrv.lastNightAvg": 58, "hrv.status": "BALANCED" });
});
