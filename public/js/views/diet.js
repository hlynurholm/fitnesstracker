// Diet tab: targets, what MyFitnessPal says was eaten, how the scale responded, and Claude's latest diet note.
import { api } from "../api.js";
import { h, clear, toast, modal, fmtDay, fmtShort, segmented } from "../util.js";
import { PROGRAM, todayLocal, addDays } from "../program.js";
import { barChart, lineChart, PALETTE, fmtDateTick } from "../charts.js";
import { mfpUploadCard } from "./data.js";

const KCAL_PER_KG = 7700;

export async function renderDiet(container) {
  const d = await api.get("/api/diet?days=120");
  clear(container);
  const t = d.targets;
  const days = d.nutrition;
  const today = todayLocal();

  const head = h("div", { class: "page-head" }, h("div", null, h("h1", null, "Diet"), h("div", { class: "sub" }, `${t.calories.toLocaleString("en")} kcal and ${t.protein_g} g protein a day`)));
  container.appendChild(head);

  container.appendChild(tiles(d, today));
  container.appendChild(targetsCard(d));
  if (!days.length) {
    container.appendChild(h("div", { class: "card" },
      h("div", { class: "card-title" }, h("h3", null, "Nothing logged yet")),
      h("p", { class: "muted small" }, "Upload a MyFitnessPal export below and the intake charts, weekly averages and the maintenance estimate fill in here. Weigh-ins from the Today page are used for the weight side.")));
  } else {
    container.appendChild(intakeCard(d));
    container.appendChild(weeksCard(d));
    container.appendChild(daysCard(d));
  }
  container.appendChild(dayTemplateCard(d));
  container.appendChild(notesCard(d));
  container.appendChild(mfpUploadCard(() => renderDiet(container)));
}

// ---------- tiles ----------
function tiles(d, today) {
  const t = d.targets;
  const days = d.nutrition;
  const byDate = new Map(days.map((n) => [n.date, n]));
  const todayRow = byDate.get(today);
  const last7 = days.filter((n) => n.date > addDays(today, -7) && n.date <= today);
  const avg = (arr, k) => (arr.length ? arr.reduce((s, x) => s + (x[k] || 0), 0) / arr.length : null);
  const kcal7 = avg(last7, "calories"), prot7 = avg(last7, "protein_g");
  const tile = (label, value, delta, cls = "") => h("div", { class: "tile" }, h("div", { class: "label" }, label), h("div", { class: "value " + cls }, value), delta ? h("div", { class: "delta" }, delta) : null);
  const signed = (v, unit = "") => `${v >= 0 ? "+" : ""}${Math.round(v)}${unit}`;

  const out = h("div", { class: "tiles" });
  out.appendChild(tile("Today", todayRow ? `${Math.round(todayRow.calories).toLocaleString("en")} kcal` : "–", todayRow ? `${Math.round(todayRow.protein_g)} g protein · ${signed(todayRow.calories - t.calories)} vs target` : "no MyFitnessPal day yet"));
  out.appendChild(tile("7-day average", kcal7 != null ? `${Math.round(kcal7).toLocaleString("en")} kcal` : "–", kcal7 != null ? `${signed(kcal7 - t.calories)} vs target · ${last7.length} of 7 days logged` : "upload an export"));
  out.appendChild(tile("Protein, 7-day", prot7 != null ? `${Math.round(prot7)} g` : "–", prot7 != null ? `${signed(prot7 - t.protein_g, " g")} vs target` : `target ${t.protein_g} g`, prot7 != null && prot7 < t.protein_g - 20 ? "warn" : ""));

  // Implied maintenance: average intake plus what the weight change says was burned on top. Needs 3 weeks.
  const m = impliedMaintenance(d);
  if (m) out.appendChild(tile("Real maintenance", `${(Math.round(m.maintenance / 10) * 10).toLocaleString("en")} kcal`, `from ${m.days} days: ${Math.round(m.intake).toLocaleString("en")} kcal eaten, ${m.changePerWeek > 0 ? "+" : ""}${m.changePerWeek.toFixed(2)} kg a week`));
  else {
    const wk = d.weeks.filter((w) => w.weight_change != null).slice(-1)[0];
    out.appendChild(tile("Expected loss", `${t.loss_per_week_kg[0]} to ${t.loss_per_week_kg[1]} kg`, wk ? `a week. Last week ${wk.weight_change > 0 ? "+" : ""}${wk.weight_change.toFixed(1)} kg` : `a week. Maintenance estimate ${t.maintenance_estimate.toLocaleString("en")} kcal`));
  }
  return out;
}

// Compares intake with the 7-day weight trend over the overlapping span. Only trusted after about three weeks.
function impliedMaintenance(d) {
  const n = d.nutrition;
  const w = d.body;
  if (n.length < 18 || w.length < 6) return null;
  const first = n[0].date, last = n[n.length - 1].date;
  const span = (Date.parse(last) - Date.parse(first)) / 86400000;
  if (span < 20) return null;
  const trend = (date) => { const win = w.filter((b) => b.date <= date && b.date > addDays(date, -7)); return win.length ? win.reduce((s, b) => s + b.weight_kg, 0) / win.length : null; };
  const startKg = trend(addDays(first, 6)), endKg = trend(last);
  if (startKg == null || endKg == null) return null;
  const intake = n.reduce((s, x) => s + (x.calories || 0), 0) / n.length;
  const perDay = (endKg - startKg) / span;
  return { maintenance: intake - perDay * KCAL_PER_KG, intake, changePerWeek: perDay * 7, days: n.length };
}

// ---------- cards ----------
function card(title, subtitle) {
  const c = h("div", { class: "card" });
  c.appendChild(h("div", { class: "card-title" }, h("h3", null, title), subtitle ? h("span", { class: "muted small" }, subtitle) : null));
  return c;
}

function targetsCard(d) {
  const t = d.targets;
  const c = card("Targets", "from the plan");
  const row = (label, value, sub) => h("div", { class: "list-item" }, h("div", null, h("div", { class: "title" }, label), sub ? h("div", { class: "sub" }, sub) : null), h("div", { class: "val" }, value));
  c.appendChild(h("div", { class: "action-list" },
    row("Calories", `${t.calories.toLocaleString("en")} kcal a day`, `about ${(t.maintenance_estimate - t.calories).toLocaleString("en")} under the ${t.maintenance_estimate.toLocaleString("en")} kcal maintenance estimate`),
    row("Protein", `${t.protein_g} g a day`, "spread over 3 to 4 meals, 40 to 50 g each"),
    row("Fun budget", `${t.fun_budget_week_kcal.toLocaleString("en")} kcal a week`, `beer and sweets, about ${Math.round(t.fun_budget_week_kcal / 7 / 10) * 10} a day, already inside the daily target`),
    row("Weight", `${t.loss_per_week_kg[0]} to ${t.loss_per_week_kg[1]} kg a week`, `goal ${t.goal_weight_kg} kg. Weigh in 3 mornings a week, read only the weekly average`),
    row("Steps", "8,000 to 10,000 a day", "pram walks count")));
  c.appendChild(h("p", { class: "muted small", style: { margin: ".8rem 0 0" } }, PROGRAM.nutrition.note));
  c.appendChild(h("a", { class: "btn text", href: "/settings", style: { marginTop: ".4rem" } }, "Edit targets in Settings"));
  return c;
}

function intakeCard(d) {
  const t = d.targets;
  const c = card("Intake", "kcal per day, protein on the right");
  let span = 42;
  const canvas = h("canvas");
  const spans = [42, 84, 120];
  const seg = segmented(spans.map((n, i) => ({ label: n === 42 ? "6 weeks" : n === 84 ? "12 weeks" : "All", onClick: (e) => { span = n; seg.querySelectorAll("button").forEach((x, j) => x.classList.toggle("active", j === i)); draw(); } })), 0);
  seg.style.marginBottom = ".6rem";
  c.appendChild(seg);
  c.appendChild(h("div", { class: "chart-box" }, canvas));
  const draw = () => {
    const days = fillGaps(d.nutrition.slice(-span));
    barChart(canvas, { labels: days.map((n) => n.date), xLabels: fmtDateTick, yFormatter: (v) => `${v}`, y1Title: "protein g",
      datasets: [
        { label: "kcal", data: days.map((n) => (n.calories == null ? null : Math.round(n.calories))), backgroundColor: days.map((n) => (n.calories > t.calories + 150 ? PALETTE[8] + "99" : PALETTE[1] + "aa")) },
        { type: "line", label: "protein g", data: days.map((n) => (n.protein_g == null ? null : Math.round(n.protein_g))), borderColor: PALETTE[2], backgroundColor: PALETTE[2], pointRadius: 2, borderWidth: 2, yAxisID: "y1", tension: 0.2, spanGaps: true },
      ],
      annotationLines: [{ label: `kcal target ${t.calories}`, value: t.calories, color: PALETTE[1] }, { label: `protein target ${t.protein_g}`, value: t.protein_g, color: PALETTE[2], axis: "y1" }] });
  };
  requestAnimationFrame(draw);

  // Weight alongside, same span, when there are weigh-ins.
  if (d.body.length >= 2) {
    const wc = h("canvas");
    c.appendChild(h("p", { class: "muted small", style: { margin: ".9rem 0 .3rem" } }, "Morning weight and 7-day average over the same period"));
    c.appendChild(h("div", { class: "chart-box", style: { height: "180px" } }, wc));
    requestAnimationFrame(() => {
      const w = d.body;
      const rolling = w.map((b) => { const win = w.filter((x) => x.date <= b.date && x.date > addDays(b.date, -7)); return Math.round((win.reduce((s, x) => s + x.weight_kg, 0) / win.length) * 100) / 100; });
      lineChart(wc, { labels: w.map((b) => b.date), xLabels: fmtDateTick, yFormatter: (v) => `${Number(v).toFixed(1)} kg`,
        datasets: [{ label: "Weigh-in", data: w.map((b) => b.weight_kg), borderColor: PALETTE[7], backgroundColor: PALETTE[7], pointRadius: 3, borderWidth: 0, showLine: false },
          { label: "7-day average", data: rolling, borderColor: PALETTE[0], backgroundColor: PALETTE[0] + "33", pointRadius: 0, borderWidth: 2, tension: 0.3 }],
        annotationLines: [{ label: `Goal ${t.goal_weight_kg} kg`, value: t.goal_weight_kg, color: PALETTE[2] }] });
    });
  }
  return c;
}

// Inserts empty days so gaps show as gaps instead of the bars closing up.
function fillGaps(days) {
  if (!days.length) return days;
  const out = [];
  let cur = days[0].date;
  const byDate = new Map(days.map((n) => [n.date, n]));
  const last = days[days.length - 1].date;
  while (cur <= last) { out.push(byDate.get(cur) || { date: cur, calories: null, protein_g: null }); cur = addDays(cur, 1); }
  return out;
}

function weeksCard(d) {
  const t = d.targets;
  const c = card("Weeks", "averages and the scale");
  const rows = d.weeks.filter((w) => w.days_logged || w.weigh_ins).slice(-10).reverse();
  const kcalCls = (v) => (v == null ? "" : v > t.calories + 150 ? "num danger" : v < t.calories - 300 ? "num warn" : "num");
  c.appendChild(h("div", { class: "table-wrap" }, h("table", null,
    h("thead", null, h("tr", null, h("th", null, "Week"), h("th", { class: "num" }, "Days"), h("th", { class: "num" }, "kcal"), h("th", { class: "num" }, "Protein"), h("th", { class: "num" }, "Weight"), h("th", { class: "num" }, "Change"))),
    h("tbody", null, rows.map((w) => h("tr", null,
      h("td", null, w.week >= 1 ? `Wk ${w.week}` : "Before", h("div", { class: "muted small" }, fmtShort(w.monday))),
      h("td", { class: "num" }, String(w.days_logged)),
      h("td", { class: kcalCls(w.kcal_avg) }, w.kcal_avg == null ? "–" : String(w.kcal_avg)),
      h("td", { class: w.protein_avg != null && w.protein_avg < t.protein_g - 20 ? "num warn" : "num" }, w.protein_avg == null ? "–" : `${w.protein_avg} g`),
      h("td", { class: "num" }, w.weight_avg == null ? "–" : `${w.weight_avg.toFixed(1)} kg`),
      h("td", { class: "num " + (w.weight_change == null ? "" : w.weight_change <= -0.3 ? "ok" : w.weight_change > 0.2 ? "danger" : "") }, w.weight_change == null ? "–" : `${w.weight_change > 0 ? "+" : ""}${w.weight_change.toFixed(1)}`)))))));
  c.appendChild(h("p", { class: "muted small", style: { margin: ".6rem 0 0" } }, `Red kcal: more than 150 over target. Orange protein: more than 20 g under. A deficit of ${t.maintenance_estimate - t.calories} kcal a day should show as about ${((t.maintenance_estimate - t.calories) * 7 / KCAL_PER_KG).toFixed(1)} kg a week once water weight settles.`));
  return c;
}

function daysCard(d) {
  const t = d.targets;
  const c = card("Last 14 days", "tap a day for its meals");
  const rows = d.nutrition.slice(-14).reverse();
  const list = h("div", { class: "action-list" });
  for (const n of rows) {
    const over = n.calories - t.calories;
    list.appendChild(h("button", { class: "list-item", onClick: () => dayDialog(n, t) },
      h("div", null, h("div", { class: "title" }, fmtDay(n.date)), h("div", { class: "sub" }, `${Math.round(n.protein_g)} g protein · ${Math.round(n.carbs_g)} g carbs · ${Math.round(n.fat_g)} g fat${n.sugar_g ? ` · ${Math.round(n.sugar_g)} g sugar` : ""}`)),
      h("div", { class: "val" }, h("div", null, `${Math.round(n.calories).toLocaleString("en")} kcal`), h("div", { class: "small " + (over > 150 ? "danger" : over < -300 ? "warn" : "muted") }, `${over >= 0 ? "+" : ""}${Math.round(over)}`))));
  }
  c.appendChild(list);
  return c;
}

function dayDialog(n, t) {
  const meals = Array.isArray(n.meals) ? n.meals : [];
  const content = h("div", null,
    h("p", { class: "small muted" }, `${Math.round(n.calories)} kcal of ${t.calories} · ${Math.round(n.protein_g)} g protein of ${t.protein_g}`),
    meals.length ? h("div", { class: "table-wrap" }, h("table", null,
      h("thead", null, h("tr", null, h("th", null, "Meal"), h("th", { class: "num" }, "kcal"), h("th", { class: "num" }, "Protein"))),
      h("tbody", null, meals.map((m) => h("tr", null, h("td", null, m.meal || "Meal", m.note ? h("div", { class: "muted small" }, m.note) : null), h("td", { class: "num" }, String(Math.round(m.calories || 0))), h("td", { class: "num" }, `${Math.round(m.protein_g || 0)} g`)))))) : h("p", { class: "muted small" }, "No meal breakdown in this export, only the day totals."));
  modal({ title: fmtDay(n.date, true), content, actions: [{ label: "Close", class: "ghost" }] });
}

function dayTemplateCard(d) {
  const c = card("A day that hits the numbers", "from the plan");
  const rows = d.day_template || PROGRAM.nutrition.dayTemplate;
  c.appendChild(h("div", { class: "table-wrap" }, h("table", null,
    h("thead", null, h("tr", null, h("th", null, "When"), h("th", null, "What"), h("th", { class: "num" }, "kcal"), h("th", { class: "num" }, "Protein"))),
    h("tbody", null, rows.map((r) => h("tr", null, h("td", null, r.when), h("td", null, r.what), h("td", { class: "num" }, String(r.kcal)), h("td", { class: "num" }, r.protein ? `${r.protein} g` : "")))),
    h("tfoot", null, h("tr", null, h("td", null, "Total"), h("td", null, ""), h("td", { class: "num" }, String(rows.reduce((s, r) => s + r.kcal, 0))), h("td", { class: "num" }, `${rows.reduce((s, r) => s + (r.protein || 0), 0)} g`))))));
  c.appendChild(h("p", { class: "muted small", style: { margin: ".6rem 0 0" } }, "Bread and cereal are not the problem. They have been replacing protein, so keep some but always pair them with protein."));
  return c;
}

// Latest report posted with section "diet". A future scheduled Claude task writes here through POST /api/reports.
function notesCard(d) {
  const c = card("Claude's diet notes", d.report ? fmtShort(d.report.date || d.report.created_at) : "nothing yet");
  if (!d.report) {
    c.appendChild(h("p", { class: "muted small" }, "When Claude reviews the uploads, the note lands here. Until then, use \"Copy summary for Claude\" on the Data page and ask in the project."));
    return c;
  }
  const html = window.marked ? marked.parse(d.report.body_md) : d.report.body_md;
  c.appendChild(h("h4", { style: { margin: "0 0 .4rem" } }, d.report.title));
  c.appendChild(h("div", { class: "md small", html }));
  c.appendChild(h("a", { class: "btn text", href: `/reports/${d.report.id}` }, "Open as a page"));
  return c;
}
