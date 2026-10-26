import { test } from "node:test";
import assert from "node:assert/strict";
import { makeFit } from "./fixtures/make-fit.js";
import { parseFit, isFit } from "../src/parsers/fit.js";
import { parseTcx, parseGpx } from "../src/parsers/xml.js";
import { parseCsv, toNumber, toSeconds } from "../src/parsers/csv.js";
import { parseMfpCsv, looksLikeMfpCsv } from "../src/parsers/mfp.js";
import { parseGarminCsv, looksLikeGarminCsv } from "../src/parsers/garmin-csv.js";
import { parseUpload } from "../src/parsers/index.js";
import { resolveDay, weekNumber, e1rm, parseTime, fmtTime } from "../public/js/program.js";

test("FIT: synthetic 5k run parses", () => {
  const bytes = makeFit();
  assert.ok(isFit(bytes));
  const a = parseFit(bytes, { maxHr: 190 });
  assert.equal(a.sport, "running");
  assert.equal(a.distance_m, 5000);
  assert.equal(a.duration_s, 1500);
  assert.equal(a.avg_hr, 155);
  assert.equal(a.max_hr, 170);
  assert.equal(a.laps.length, 5);
  assert.equal(a.splits.length, 5);
  assert.ok(Math.abs(a.splits[0].seconds - 300) <= 2, `split ${a.splits[0].seconds}`);
  assert.ok(Math.abs(a.best_5k_s - 1500) <= 3, `best5k ${a.best_5k_s}`);
  assert.equal(a.avg_pace_s_per_km, 300);
  assert.equal(a.avg_cadence, 170); // 85 rpm -> 170 spm
  assert.ok(a.track.length > 50 && a.track.length <= 260);
  assert.equal(a.start_time, "2026-10-27T07:00:00.000Z");
  assert.ok(a.hr_zones.seconds.reduce((x, y) => x + y, 0) > 1400);
});

const TCX = `<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
<Activities><Activity Sport="Running"><Id>2026-10-29T07:00:00.000Z</Id>
<Lap StartTime="2026-10-29T07:00:00.000Z"><TotalTimeSeconds>600</TotalTimeSeconds><DistanceMeters>2000</DistanceMeters><Calories>150</Calories>
<AverageHeartRateBpm><Value>140</Value></AverageHeartRateBpm><MaximumHeartRateBpm><Value>150</Value></MaximumHeartRateBpm><Intensity>Active</Intensity><TriggerMethod>Manual</TriggerMethod>
<Track>
<Trackpoint><Time>2026-10-29T07:00:00.000Z</Time><Position><LatitudeDegrees>64.14</LatitudeDegrees><LongitudeDegrees>-21.94</LongitudeDegrees></Position><AltitudeMeters>10</AltitudeMeters><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>120</Value></HeartRateBpm><Extensions><ns3:TPX><ns3:Speed>3.3</ns3:Speed><ns3:RunCadence>84</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
<Trackpoint><Time>2026-10-29T07:05:00.000Z</Time><Position><LatitudeDegrees>64.15</LatitudeDegrees><LongitudeDegrees>-21.94</LongitudeDegrees></Position><AltitudeMeters>15</AltitudeMeters><DistanceMeters>1000</DistanceMeters><HeartRateBpm><Value>140</Value></HeartRateBpm><Extensions><ns3:TPX><ns3:Speed>3.3</ns3:Speed><ns3:RunCadence>86</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
<Trackpoint><Time>2026-10-29T07:10:00.000Z</Time><Position><LatitudeDegrees>64.16</LatitudeDegrees><LongitudeDegrees>-21.94</LongitudeDegrees></Position><AltitudeMeters>12</AltitudeMeters><DistanceMeters>2000</DistanceMeters><HeartRateBpm><Value>150</Value></HeartRateBpm><Extensions><ns3:TPX><ns3:Speed>3.3</ns3:Speed><ns3:RunCadence>88</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
</Track></Lap><Creator xsi:type="Device_t" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Name>Forerunner 255</Name></Creator></Activity></Activities></TrainingCenterDatabase>`;

test("TCX parses laps and trackpoints", () => {
  const [a] = parseTcx(TCX);
  assert.equal(a.distance_m, 2000);
  assert.equal(a.duration_s, 600);
  assert.equal(a.avg_hr, 140);
  assert.equal(a.max_hr, 150);
  assert.equal(a.calories, 150);
  assert.equal(a.laps.length, 1);
  assert.equal(a.splits.length, 2);
  assert.equal(a.device, "Forerunner 255");
  assert.equal(a.start_time, "2026-10-29T07:00:00.000Z");
});

const GPX = `<?xml version="1.0"?><gpx creator="Garmin Connect" version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:ns3="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
<metadata><time>2026-10-29T07:00:00.000Z</time></metadata>
<trk><name>Reykjavik Running</name><type>running</type><trkseg>
<trkpt lat="64.1400" lon="-21.9400"><ele>10</ele><time>2026-10-29T07:00:00.000Z</time><extensions><ns3:TrackPointExtension><ns3:hr>120</ns3:hr><ns3:cad>84</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
<trkpt lat="64.1490" lon="-21.9400"><ele>12</ele><time>2026-10-29T07:05:00.000Z</time><extensions><ns3:TrackPointExtension><ns3:hr>140</ns3:hr><ns3:cad>86</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
<trkpt lat="64.1580" lon="-21.9400"><ele>14</ele><time>2026-10-29T07:10:00.000Z</time><extensions><ns3:TrackPointExtension><ns3:hr>150</ns3:hr><ns3:cad>88</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
</trkseg></trk></gpx>`;

test("GPX parses with haversine distance", () => {
  const [a] = parseGpx(GPX);
  assert.ok(a.distance_m > 1900 && a.distance_m < 2100, `distance ${a.distance_m}`);
  assert.equal(a.elapsed_s, 600);
  assert.equal(a.name, "Reykjavik Running");
  assert.equal(a.max_hr, 150);
  assert.ok(a.avg_cadence >= 170);
});

test("CSV helpers", () => {
  assert.deepEqual(parseCsv('a,b\n"x, y",2\n'), [["a", "b"], ["x, y", "2"]]);
  assert.equal(toNumber("5,02"), 5.02);
  assert.equal(toNumber("1,234.5"), 1234.5);
  assert.equal(toNumber("--"), null);
  assert.equal(toSeconds("25:37"), 1537);
  assert.equal(toSeconds("1:02:11"), 3731);
});

const MFP = `Date,Meal,Calories,Fat (g),Saturated Fat,Polyunsaturated Fat,Monounsaturated Fat,Trans Fat,Cholesterol,Sodium (mg),Potassium,Carbohydrates (g),Fiber,Sugar,Protein (g),Vitamin A,Vitamin C,Calcium,Iron,Note
2026-10-27,Lunch,700,20,5,2,8,0,100,800,600,70,8,10,50,10,20,15,10,
2026-10-27,Dinner,800,25,8,3,10,0,120,900,700,80,10,12,50,10,20,15,10,
2026-10-27,Snacks,"1,000",30,10,4,12,0,0,300,200,150,2,80,10,0,0,5,2,beer and sweets
2026-10-28,Lunch,650,18,5,2,8,0,90,700,500,60,7,8,55,10,20,15,10,
`;

test("MyFitnessPal nutrition CSV aggregates per day", () => {
  const rows = parseCsv(MFP);
  assert.ok(looksLikeMfpCsv(rows[0]));
  const r = parseMfpCsv(MFP);
  assert.equal(r.kind, "mfp_nutrition");
  assert.equal(r.nutrition_days.length, 2);
  const d = r.nutrition_days[0];
  assert.equal(d.date, "2026-10-27");
  assert.equal(d.calories, 2500);
  assert.equal(d.protein_g, 110);
  assert.equal(d.meals.length, 3);
  const u = parseUpload({ filename: "Nutrition-Summary.csv", bytes: new TextEncoder().encode(MFP) });
  assert.equal(u.source, "myfitnesspal");
  assert.equal(u.status, "parsed");
});

test("MyFitnessPal measurements CSV", () => {
  const r = parseMfpCsv("Date,Weight\n2026-10-27,92.6\n2026-10-28,92.1\n");
  assert.equal(r.kind, "mfp_measurements");
  assert.equal(r.body_metrics.length, 2);
  assert.equal(r.body_metrics[1].weight_kg, 92.1);
});

const GARMIN_LIST = `Activity Type,Date,Favorite,Title,Distance,Calories,Time,Avg HR,Max HR,Aerobic TE,Avg Run Cadence,Max Run Cadence,Avg Pace,Best Pace,Total Ascent,Total Descent,Avg Stride Length,Moving Time,Elapsed Time
Running,2026-10-27 07:02:11,false,Reykjavik Running,5.02,412,25:37,162,181,3.5,168,185,5:06,4:40,32,30,1.17,25:30,26:10
Padel,2026-10-25 18:00:00,false,Padel,--,500,1:30:00,140,175,2.0,--,--,--,--,--,--,--,1:28:00,1:30:00
`;

test("Garmin activities list CSV", () => {
  const rows = parseCsv(GARMIN_LIST);
  assert.ok(looksLikeGarminCsv(rows[0]));
  const r = parseGarminCsv(GARMIN_LIST);
  assert.equal(r.kind, "garmin_activity_list");
  assert.equal(r.activities.length, 2);
  const a = r.activities[0];
  assert.equal(a.distance_m, 5020);
  assert.equal(a.duration_s, 1537);
  assert.equal(a.avg_hr, 162);
  assert.equal(a.avg_pace_s_per_km, 306);
  assert.equal(a.start_time, "2026-10-27T07:02:11");
  assert.equal(a.local_time, true);
});

const GARMIN_SPLITS = `Split,Time,Cumulative Time,Distance,Avg Pace,Avg HR,Max HR,Avg Run Cadence,Calories
1,5:10,5:10,1.00,5:10,150,160,168,80
2,5:05,10:15,1.00,5:05,158,165,170,82
3,5:00,15:15,1.00,5:00,163,170,171,81
4,4:58,20:13,1.00,4:58,167,174,172,83
5,4:50,25:03,1.00,4:50,172,181,174,84
Summary,25:03,25:03,5.00,5:01,162,181,171,410
`;

test("Garmin splits CSV", () => {
  const r = parseGarminCsv(GARMIN_SPLITS);
  assert.equal(r.kind, "garmin_splits");
  const a = r.activities[0];
  assert.equal(a.laps.length, 5);
  assert.equal(a.distance_m, 5000);
  assert.equal(a.duration_s, 1503);
  assert.equal(a.avg_hr, 162);
  assert.equal(a.best_5k_s, 1503);
  assert.equal(a.splits.length, 5);
});

test("Unknown CSV is stored raw", () => {
  const u = parseUpload({ filename: "random.csv", bytes: new TextEncoder().encode("a,b,c\n1,2,3\n") });
  assert.equal(u.status, "stored_raw");
  assert.equal(u.format, "csv");
});

test("Program schedule", () => {
  assert.equal(resolveDay("2026-10-26").templateKey, "lift_a");
  assert.equal(resolveDay("2026-10-27").templateKey, "time_trial_5k");
  assert.equal(resolveDay("2026-11-03").templateKey, "intervals_6x2");
  assert.equal(resolveDay("2026-11-24").templateKey, "intervals_5x3");
  assert.equal(resolveDay("2026-12-15").templateKey, "time_trial_5k");
  assert.equal(resolveDay("2027-01-05").templateKey, "intervals_4x4");
  assert.equal(resolveDay("2026-12-01").deload, true);
  assert.equal(resolveDay("2026-12-01").plan.length, 0);
  assert.equal(resolveDay("2026-12-02").plan[0].sets, 2); // deload halves 4 -> 2
  assert.equal(weekNumber("2026-10-25", "2026-10-26"), 0);
  assert.equal(resolveDay("2026-10-26").phase, 1);
  assert.equal(resolveDay("2026-11-09").phase, 2);
  assert.equal(resolveDay("2026-12-07").phase, 3);
  assert.equal(Math.round(e1rm(100, 5)), 117);
  assert.equal(parseTime("25:37"), 1537);
  assert.equal(fmtTime(1380), "23:00");
});
