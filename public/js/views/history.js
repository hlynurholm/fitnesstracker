// History: every logged session, newest first, grouped by program week.
import { api } from "../api.js";
import { h, clear, fmtDay, fmtShort, secondsToHms, segmented } from "../util.js";
import { templateFor, weekNumber, fmtTime, fmtPace } from "../program.js";
import { state } from "../app.js";

export async function renderHistory(container) {
  const workouts = await api.get("/api/workouts?limit=500");
  clear(container);
  container.appendChild(h("div", { class: "page-head" }, h("div", null, h("h1", null, "Calendar"), h("div", { class: "sub" }, "Everything logged, newest first")),
    h("div", { class: "controls" }, segmented([{ label: "Month", href: "/calendar" }, { label: "List", href: "/history" }], 1))));
  if (!workouts.length) {
    container.appendChild(h("div", { class: "card" }, h("p", { class: "muted" }, "Nothing logged yet. Open Today and log the first session.")));
    return;
  }
  const start = state.settings.program_start_date;
  const groups = new Map();
  for (const w of workouts) {
    const wk = weekNumber(w.date, start);
    if (!groups.has(wk)) groups.set(wk, []);
    groups.get(wk).push(w);
  }
  for (const [wk, list] of groups) {
    const done = list.filter((w) => w.status === "done" && w.kind !== "rest").length;
    const card = h("div", { class: "card" });
    card.appendChild(h("div", { class: "card-title" }, h("h3", null, wk >= 1 ? `Week ${wk}` : "Before the plan"), h("span", { class: "badge" }, `${done} done`)));
    for (const w of list) {
      const t = templateFor(w.template_key);
      const bits = [];
      if (w.kind === "lift") bits.push(`${w.set_count} sets`, w.volume_kg ? `${w.volume_kg} kg volume` : null);
      if (w.distance_km) bits.push(`${w.distance_km} km`);
      if (w.time_sec) bits.push(fmtTime(w.time_sec));
      if (w.distance_km && w.time_sec) bits.push(fmtPace(w.time_sec / w.distance_km));
      if (w.avg_hr) bits.push(`${w.avg_hr} bpm`);
      if (w.rpe) bits.push(`RPE ${w.rpe}`);
      if (w.activity_count) bits.push("Garmin");
      card.appendChild(h("a", { class: "list-item", href: `/day/${w.date}`, onClick: () => { try { localStorage.setItem(`ft_active_${w.date}`, JSON.stringify(w.template_key)); } catch {} } },
        h("div", null, h("div", { class: `title kind-${w.kind}` }, `${fmtDay(w.date)} · ${t.name}`), h("div", { class: "sub" }, bits.filter(Boolean).join(" · ") || (w.notes ? w.notes.slice(0, 80) : "no details"))),
        h("span", { class: `badge ${w.status === "done" ? "ok" : w.status === "skipped" ? "danger" : "accent"}` }, w.status.replace("_", " "))));
    }
    container.appendChild(card);
  }
}
