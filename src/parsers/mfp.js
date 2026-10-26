// MyFitnessPal CSV exports (Nutrition-Summary, Measurement-Summary, Exercise-Summary).
import { parseDelimited, rowsToObjects, findCol, toNumber } from "./csv.js";

export function looksLikeMfpCsv(headers) {
  const h = headers.map((x) => x.toLowerCase());
  const hasDate = h.some((x) => x === "date");
  const nutrition = hasDate && h.some((x) => x.startsWith("calories")) && (h.some((x) => x.startsWith("protein")) || h.includes("meal"));
  const measurement = hasDate && h.some((x) => x.startsWith("weight")) && h.length <= 6;
  const exercise = hasDate && h.includes("exercise") && h.some((x) => x.startsWith("exercise calories"));
  return nutrition || measurement || exercise;
}

function isoDate(s) {
  if (!s) return null;
  s = String(s).trim();
  let m = s.match(/^(\d{4})-(\d{1,2})-(\d{1,2})/);
  if (m) return `${m[1]}-${m[2].padStart(2, "0")}-${m[3].padStart(2, "0")}`;
  m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})/); // US m/d/yyyy
  if (m) return `${m[3]}-${m[1].padStart(2, "0")}-${m[2].padStart(2, "0")}`;
  m = s.match(/^(\d{1,2})\.(\d{1,2})\.(\d{4})/); // d.m.yyyy
  if (m) return `${m[3]}-${m[2].padStart(2, "0")}-${m[1].padStart(2, "0")}`;
  const d = Date.parse(s);
  return isNaN(d) ? null : new Date(d).toISOString().slice(0, 10);
}

export function parseMfpCsv(text) {
  const rows = parseDelimited(text);
  const { headers, records } = rowsToObjects(rows);
  const h = headers.map((x) => x.toLowerCase());
  const cDate = findCol(headers, ["Date"]);
  if (h.includes("exercise") && h.some((x) => x.startsWith("exercise calories"))) {
    return { kind: "mfp_exercise", rows: records.map((r) => ({ ...r, date: isoDate(r[cDate]) })) };
  }
  if (h.some((x) => x.startsWith("weight")) && !h.some((x) => x.startsWith("calories"))) {
    const cW = findCol(headers, ["Weight"]);
    const body = records.map((r) => ({ date: isoDate(r[cDate]), weight_kg: toNumber(r[cW]) })).filter((r) => r.date && r.weight_kg);
    return { kind: "mfp_measurements", body_metrics: body };
  }
  const cMeal = findCol(headers, ["Meal"]);
  const cCal = findCol(headers, ["Calories"]);
  const cProt = findCol(headers, ["Protein"]);
  const cCarb = findCol(headers, ["Carbohydrates", "Carbs"]);
  const cFat = findCol(headers, ["Fat (g)", "Fat"]);
  const cFiber = findCol(headers, ["Fiber", "Fibre"]);
  const cSugar = findCol(headers, ["Sugar"]);
  const cSodium = findCol(headers, ["Sodium"]);
  const cNote = findCol(headers, ["Note"]);
  const days = new Map();
  for (const r of records) {
    const date = isoDate(r[cDate]);
    if (!date) continue;
    const d = days.get(date) || { date, calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sugar_g: 0, sodium_mg: 0, meals: [] };
    const meal = {
      meal: cMeal ? r[cMeal] : null,
      calories: toNumber(r[cCal]) || 0,
      protein_g: toNumber(r[cProt]) || 0,
      carbs_g: toNumber(r[cCarb]) || 0,
      fat_g: toNumber(r[cFat]) || 0,
      fiber_g: toNumber(r[cFiber]) || 0,
      sugar_g: toNumber(r[cSugar]) || 0,
      sodium_mg: toNumber(r[cSodium]) || 0,
      note: cNote ? r[cNote] || null : null,
    };
    d.calories += meal.calories; d.protein_g += meal.protein_g; d.carbs_g += meal.carbs_g; d.fat_g += meal.fat_g;
    d.fiber_g += meal.fiber_g; d.sugar_g += meal.sugar_g; d.sodium_mg += meal.sodium_mg;
    d.meals.push(meal);
    days.set(date, d);
  }
  const list = [...days.values()].map((d) => {
    for (const k of ["calories", "protein_g", "carbs_g", "fat_g", "fiber_g", "sugar_g", "sodium_mg"]) d[k] = Math.round(d[k] * 10) / 10;
    return d;
  }).sort((a, b) => a.date.localeCompare(b.date));
  return { kind: "mfp_nutrition", nutrition_days: list };
}
