import { Encoder, Profile } from "@garmin/fitsdk";

// Build a synthetic 5 km run as a FIT file: 1500 s, 5000 m, HR climbing 140 -> 170.
export function makeFit() {
  const enc = new Encoder();
  const start = new Date("2026-10-27T07:00:00Z");
  enc.writeMesg({ mesgNum: Profile.MesgNum.FILE_ID, type: "activity", manufacturer: "garmin", product: 4315, timeCreated: start, serialNumber: 12345 });
  const n = 300;
  const records = [];
  for (let i = 0; i <= n; i++) {
    const t = new Date(start.getTime() + i * 5000);
    const dist = (5000 * i) / n;
    const lat = 64.1466 + (dist / 111000) * 0.5;
    const lon = -21.9426 + (dist / 55000) * 0.5;
    records.push({ mesgNum: Profile.MesgNum.RECORD, timestamp: t, positionLat: Math.round(lat / (180 / 2 ** 31)), positionLong: Math.round(lon / (180 / 2 ** 31)), distance: dist, speed: 3.333, heartRate: Math.round(140 + 30 * (i / n)), cadence: 85, altitude: 20 + 5 * Math.sin(i / 20) });
  }
  for (const r of records) enc.writeMesg(r);
  for (let k = 0; k < 5; k++) {
    enc.writeMesg({ mesgNum: Profile.MesgNum.LAP, timestamp: new Date(start.getTime() + (k + 1) * 300000), startTime: new Date(start.getTime() + k * 300000), totalElapsedTime: 300, totalTimerTime: 300, totalDistance: 1000, avgHeartRate: 145 + k * 5, maxHeartRate: 150 + k * 5, intensity: "active", lapTrigger: "distance" });
  }
  enc.writeMesg({ mesgNum: Profile.MesgNum.SESSION, timestamp: new Date(start.getTime() + 1500000), startTime: start, totalElapsedTime: 1500, totalTimerTime: 1500, totalDistance: 5000, sport: "running", subSport: "generic", avgHeartRate: 155, maxHeartRate: 170, totalCalories: 400, totalAscent: 30, avgCadence: 85, avgSpeed: 3.333 });
  enc.writeMesg({ mesgNum: Profile.MesgNum.ACTIVITY, timestamp: new Date(start.getTime() + 1500000), localTimestamp: Math.floor((start.getTime() + 1500000) / 1000) - 631065600, numSessions: 1, type: "manual", event: "activity", eventType: "stop" });
  return enc.close();
}

