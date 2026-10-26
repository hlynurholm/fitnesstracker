// Detects the file type and parses what it can. Anything unknown is stored raw.
import { isFit, parseFit } from "./fit.js";
import { parseTcx, parseGpx } from "./xml.js";
import { parseDelimited, rowsToObjects } from "./csv.js";
import { looksLikeGarminCsv, parseGarminCsv } from "./garmin-csv.js";
import { looksLikeMfpCsv, parseMfpCsv } from "./mfp.js";

const dec = new TextDecoder("utf-8", { fatal: false });

export function detect(filename, bytes, contentType = "") {
  const ext = (filename || "").toLowerCase().split(".").pop();
  if (isFit(bytes) || ext === "fit") return "fit";
  const head = dec.decode(bytes.subarray(0, Math.min(bytes.length, 4000)));
  if (/<TrainingCenterDatabase/i.test(head) || ext === "tcx") return "tcx";
  if (/<gpx[\s>]/i.test(head) || ext === "gpx") return "gpx";
  if (ext === "json" || /^\s*[\[{]/.test(head)) return "json";
  if (ext === "csv" || ext === "txt" || /,|;/.test(head.split("\n")[0] || "")) return "csv";
  return "unknown";
}

// Returns { format, source, status, error, parsed, activities, nutrition_days, body_metrics }
export function parseUpload({ filename, contentType, bytes, sourceHint, maxHr }) {
  const format = detect(filename, bytes, contentType);
  const out = { format, source: sourceHint || "other", status: "stored_raw", error: null, parsed: null, activities: [], nutrition_days: [], body_metrics: [] };
  try {
    if (format === "fit") {
      out.source = "garmin";
      const a = parseFit(bytes, { maxHr });
      out.activities = [a];
      out.parsed = { kind: "fit", activity: a };
      out.status = "parsed";
    } else if (format === "tcx") {
      out.source = "garmin";
      const list = parseTcx(dec.decode(bytes), { maxHr });
      out.activities = list;
      out.parsed = { kind: "tcx", activities: list };
      out.status = "parsed";
    } else if (format === "gpx") {
      out.source = "garmin";
      const list = parseGpx(dec.decode(bytes), { maxHr });
      out.activities = list;
      out.parsed = { kind: "gpx", activities: list };
      out.status = "parsed";
    } else if (format === "csv") {
      const text = dec.decode(bytes);
      const rows = parseDelimited(text);
      const { headers, records } = rowsToObjects(rows);
      if (looksLikeMfpCsv(headers) && sourceHint !== "garmin") {
        out.source = "myfitnesspal";
        const r = parseMfpCsv(text);
        out.parsed = r;
        out.nutrition_days = r.nutrition_days || [];
        out.body_metrics = r.body_metrics || [];
        out.status = "parsed";
      } else if (looksLikeGarminCsv(headers)) {
        out.source = "garmin";
        const r = parseGarminCsv(text);
        out.parsed = { kind: r.kind, activities: r.activities };
        out.activities = r.activities;
        out.status = "parsed";
      } else {
        out.parsed = { kind: "csv", headers, rows: records.slice(0, 5000) };
        out.status = "stored_raw";
      }
    } else if (format === "json") {
      out.parsed = { kind: "json", data: JSON.parse(dec.decode(bytes)) };
      out.status = "stored_raw";
    }
  } catch (e) {
    out.status = "failed";
    out.error = String(e && e.message ? e.message : e);
  }
  return out;
}
