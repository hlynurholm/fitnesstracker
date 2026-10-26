// Minimal RFC 4180 CSV parser. Handles quotes, escaped quotes, CRLF, and a BOM.
export function parseCsv(text) {
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  const rows = [];
  let row = [], field = "", inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; } else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") { row.push(field); field = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field); field = "";
      if (row.some((f) => f.trim() !== "")) rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== "" || row.length) { row.push(field); if (row.some((f) => f.trim() !== "")) rows.push(row); }
  return rows;
}

// Semicolon-separated fallback (some European exports).
export function parseDelimited(text) {
  const firstLine = text.split(/\r?\n/, 1)[0] || "";
  if ((firstLine.match(/;/g) || []).length > (firstLine.match(/,/g) || []).length) {
    return parseCsv(text.replace(/;/g, ","));
  }
  return parseCsv(text);
}

export function rowsToObjects(rows) {
  if (!rows.length) return { headers: [], records: [] };
  const headers = rows[0].map((h) => h.trim());
  const records = rows.slice(1).map((r) => {
    const o = {};
    headers.forEach((h, i) => { o[h] = (r[i] ?? "").trim(); });
    return o;
  });
  return { headers, records };
}

// Find a column by candidate names (case-insensitive, prefix match on the header).
export function findCol(headers, candidates) {
  const lower = headers.map((h) => h.toLowerCase());
  for (const c of candidates) {
    const cl = c.toLowerCase();
    let i = lower.indexOf(cl);
    if (i >= 0) return headers[i];
    i = lower.findIndex((h) => h.startsWith(cl));
    if (i >= 0) return headers[i];
  }
  return null;
}

// "5.02", "5,02", "1,234.5", "--", "" -> number or null
export function toNumber(v) {
  if (v == null) return null;
  let s = String(v).trim().replace(/[^\d.,:\-]/g, "");
  if (!s || s === "--" || s === "-") return null;
  if (s.includes(":")) return null;
  if (s.includes(",") && !s.includes(".")) {
    // 1,234 (thousands) vs 5,02 (decimal comma)
    s = /,\d{3}(,\d{3})*$/.test(s) ? s.replace(/,/g, "") : s.replace(",", ".");
  } else s = s.replace(/,/g, "");
  const n = parseFloat(s);
  return isNaN(n) ? null : n;
}

// "25:37", "1:02:11", "00:25:37.5" -> seconds
export function toSeconds(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s || s === "--") return null;
  const parts = s.split(":").map((p) => parseFloat(p.replace(",", ".")));
  if (parts.some((p) => isNaN(p))) return null;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 1) return parts[0];
  return null;
}
