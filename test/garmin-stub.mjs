#!/usr/bin/env node
// A stand-in for the Garmin Connect Personal API, for testing the sync without a real key.
// It follows Garmin's reference for the three calls the Worker makes. What the reference leaves open is a guess here:
// the token comes back as {"access_token": ...} and the download is a zip (activity 111) or a bare FIT (222).
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
  const m = url.pathname.match(/^\/download-service\/files\/activity\/(\d+)$/);
  if (m && m[1] === "111") return send(200, Buffer.from(makeZip("111_ACTIVITY.fit", fit)), "application/zip");
  if (m && m[1] === "222") return send(200, fit, "application/octet-stream");
  if (m) return send(500, JSON.stringify({ message: "boom" }));
  send(404, JSON.stringify({ message: "not found" }));
}).listen(8799, "127.0.0.1", () => console.log("Garmin stub on http://127.0.0.1:8799"));
