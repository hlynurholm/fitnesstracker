import test from "node:test";
import assert from "node:assert/strict";
import { shapeTimeline, sleepTimes, unzip, flattenMetrics } from "../src/garmin.js";
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

test("sleep times become minutes after midnight, from milliseconds or text", () => {
  assert.deepEqual(sleepTimes({ sleepStartTimestampGMT: "2026-11-14T23:10:00.0", sleepEndTimestampGMT: Date.UTC(2026, 10, 15, 6, 52) }), { bedMinutesGMT: 23 * 60 + 10, wakeMinutesGMT: 6 * 60 + 52 });
  assert.deepEqual(sleepTimes({ sleepStartTimestampLocal: Date.UTC(2026, 10, 15, 0, 5) }), { bedMinutesLocal: 5 });
  assert.deepEqual(sleepTimes({ sleepTimeSeconds: 100 }), {});
});

test("a day's timeline: heart rate in 5 minute steps, battery levels and events", () => {
  const t0 = Date.UTC(2026, 10, 15, 8, 0);
  const heart = { heartRateValueDescriptors: [{ index: 0, key: "timestamp" }, { index: 1, key: "heartrate" }], heartRateValues: [[t0, 60], [t0 + 120000, 70], [t0 + 300000, 80], [t0 + 600000, null]] };
  const battery = [{ charged: 40, drained: 55, bodyBatteryValueDescriptorDTOList: [{ bodyBatteryValueDescriptorIndex: 0, bodyBatteryValueDescriptorKey: "timestamp" }, { bodyBatteryValueDescriptorIndex: 1, bodyBatteryValueDescriptorKey: "bodyBatteryLevel" }],
    bodyBatteryValuesArray: [[t0 + 60000, 50], [t0, 52]], bodyBatteryActivityEvent: [{ eventType: "SLEEP", eventStartTimeGmt: "2026-11-15T00:28:00.0", durationInMilliseconds: 3600000, bodyBatteryImpact: 20 }] }];
  const out = shapeTimeline(heart, battery);
  assert.deepEqual(out.hr, [[t0, 65], [t0 + 300000, 80]]);
  assert.deepEqual(out.battery, [[t0, 52], [t0 + 60000, 50]]);
  assert.deepEqual(out.events, [{ type: "sleep", start: Date.UTC(2026, 10, 15, 0, 28), end: Date.UTC(2026, 10, 15, 1, 28), impact: 20 }]);
  assert.equal(out.drained, 55);
  assert.deepEqual(shapeTimeline(null, null), { v: 2, hr: [], battery: [], events: [] });
  // Without descriptors, rows of [time, level] (what Garmin sends with chunks) still read.
  assert.deepEqual(shapeTimeline(null, [{ bodyBatteryValuesArray: [[t0, 44]] }]).battery, [[t0, 44]]);
});
