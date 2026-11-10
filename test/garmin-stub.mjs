#!/usr/bin/env node
// A stand-in for the Garmin Connect Personal API, for testing the sync without a real key.
// It follows Garmin's reference for the three calls the Worker makes. What the reference leaves open is a guess here:
// the token comes back as {"access_token": ...} and the download is a zip (activity 111) or a bare FIT (222).
// Daily summaries, sleep and HRV return steady made-up values; the weight endpoint answers 403 on purpose.
//
//   node test/garmin-stub.mjs            # listens on http://127.0.0.1:8799, key "stub-key"
//   npx wrangler dev --var GARMIN_API_KEY:stub-key --var GARMIN_API_BASE:http://127.0.0.1:8799
//   bash test/garmin-sync.sh
import http from "node:http";
import { makeFit } from "./fixtures/make-fit.js";
import { makeZip } from "./fixtures/make-zip.js";

const fit = Buffer.from(makeFit()); // a 5 km run on 2026-10-27
const run = (id, name) => ({ activityId: id, activityName: name, startTimeLocal: "2026-10-27 07:00:00", startTimeGMT: "2026-10-27 07:00:00", distance: 5000, duration: 1500, averageHR: 155, activityType: { typeKey: "running" } });
const calls = [];

http.createServer((req, res) => {
  const url = new URL(req.url, "http://stub");
  calls.push(`${req.method} ${url.pathname}${url.search}`);
  const send = (status, body, type = "application/json") => { res.writeHead(status, { "Content-Type": type }); res.end(body); };
  if (url.pathname === "/__calls") return send(200, JSON.stringify(calls));
  if (url.pathname.endsWith("/personal-api-key/token")) {
    if (req.method !== "POST" || req.headers.authorization !== "ApiKey stub-key") return send(401, JSON.stringify({ message: "bad key" }));
    return send(200, JSON.stringify({ access_token: "stub-token", expires_in: 86400 }));
  }
  if (req.headers.authorization !== "Bearer stub-token") return send(401, JSON.stringify({ message: "bad token" }));
  if (url.pathname === "/activitylist-service/activities/search/activities") {
    return send(200, JSON.stringify([run(333, "Broken download"), run(222, "Bare FIT run"), run(111, "Zipped run")]));
  }
  // Daily health data, made up but steady, in the shapes of Garmin's reference.
  const each = (from, to) => { const out = []; for (let d = new Date(from + "T00:00:00Z"); d.toISOString().slice(0, 10) <= to && d.getTime() <= Date.now(); d = new Date(d.getTime() + 86400000)) out.push(d.toISOString().slice(0, 10)); return out; };
  const n = (date) => Math.floor(Date.parse(date) / 86400000); // day number, for repeatable variation
  const wave = (date, period, amp) => Math.round(Math.sin(n(date) / period) * amp);
  if (url.pathname === "/usersummary-service/v2/dailysummaries") {
    return send(200, JSON.stringify({ data: each(url.searchParams.get("startDate"), url.searchParams.get("endDate")).map((date) => ({
      uuid: "00000000-0000-0000-0000-000000000000", userProfilePk: 1, calendarDate: date, source: "garmin", includesWellnessData: true,
      movement: { steps: { goal: 9000, value: 8600 + wave(date, 1.3, 3400), distanceInMeters: 6500 + wave(date, 1.3, 2600) }, floorsAscended: { goal: 10, value: 9 + wave(date, 2, 6), distanceInMeters: 27 + wave(date, 2, 18) } },
      calories: { burnedResting: 2050, burnedActive: 620 + wave(date, 1.7, 300), burnedTotal: 2670 + wave(date, 1.7, 300) },
      heartRate: { minValue: 44 + wave(date, 3, 2), maxValue: 150 + wave(date, 1.1, 25), restingValue: 52 - Math.round((n(date) % 120) / 40) + wave(date, 2.5, 2) },
      intensityMinutes: { goal: 150, moderate: 18 + wave(date, 1.9, 16), vigorous: 12 + wave(date, 2.3, 12) },
      stress: { avgLevel: 31 + wave(date, 2.1, 9), maxLevel: 82, qualifier: "balanced", lowStressDurationInMillis: 14400000, mediumStressDurationInMillis: 5400000, highStressDurationInMillis: 1200000, restDurationInMillis: 30000000 },
      bodyBattery: { minValue: 18 + wave(date, 1.5, 10), maxValue: 88 + wave(date, 2.7, 9), chargedValue: 62, drainedValue: 58, featureVersion: "3.0", activityEvents: [{ x: 1 }] },
      respiration: { avgValue: 14, minValue: 10, maxValue: 21 }, pulseOx: { avgValue: 96, minValue: 91 },
    })) }));
  }
  if (url.pathname === "/sleep-service/sleep/dailySleepSummariesByDate") {
    return send(200, JSON.stringify(each(url.searchParams.get("startDate"), url.searchParams.get("endDate")).map((date) => {
      const deep = 4800 + wave(date, 1.4, 1200) * 1, rem = 5400 + wave(date, 2.2, 1500), light = 15000 + wave(date, 1.8, 2400), awake = 1500 + wave(date, 1.2, 900);
      return { id: n(date), userProfilePK: 1, calendarDate: date, sleepTimeSeconds: deep + rem + light, deepSleepSeconds: deep, remSleepSeconds: rem, lightSleepSeconds: light, awakeSleepSeconds: awake,
        sleepStartTimestampGMT: date + "T23:10:00.0", avgSleepStress: 17.5, avgHeartRate: 51, averageRespirationValue: 13.5, awakeCount: 2, sleepScores: { overall: { value: 78 + wave(date, 1.6, 12), qualifierKey: "GOOD" } }, dailyNapDTOS: [] };
    })));
  }
  const hrv = url.pathname.match(/^\/hrv-service\/hrv\/daily\/(\d{4}-\d{2}-\d{2})\/(\d{4}-\d{2}-\d{2})$/);
  if (hrv) return send(200, JSON.stringify({ userProfilePk: 1, hrvSummaries: each(hrv[1], hrv[2]).map((date) => ({ calendarDate: date, weeklyAvg: 58, lastNightAvg: 58 + wave(date, 1.7, 9), lastNight5MinHigh: 84, baseline: { lowUpper: 48, balancedLow: 52, balancedUpper: 66, markerValue: 0.5 }, status: "BALANCED", feedbackPhrase: "HRV_BALANCED_1", createTimeStamp: date + "T07:00:00.0" })) }));
  if (url.pathname.startsWith("/weight-service/weight/range/")) return send(403, JSON.stringify({ message: "no weight scope in the stub" })); // one source failing must not stop the rest

  const m = url.pathname.match(/^\/download-service\/files\/activity\/(\d+)$/);
  if (m && m[1] === "111") return send(200, Buffer.from(makeZip("111_ACTIVITY.fit", fit)), "application/zip");
  if (m && m[1] === "222") return send(200, fit, "application/octet-stream");
  if (m) return send(500, JSON.stringify({ message: "boom" }));
  send(404, JSON.stringify({ message: "not found" }));
}).listen(8799, "127.0.0.1", () => console.log("Garmin stub on http://127.0.0.1:8799"));
