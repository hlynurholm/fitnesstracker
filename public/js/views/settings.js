// Settings: plan start date, phase, targets, logout, how Claude connects.
import { api } from "../api.js";
import { h, clear, toast, store } from "../util.js";
import { PROGRAM, fmtTime, parseTime } from "../program.js";
import { state, loadSettings } from "../app.js";

export async function renderSettings(container) {
  const s = await loadSettings(true);
  clear(container);
  container.appendChild(h("h1", null, "Settings"));

  const form = h("div", { class: "card" });
  const start = h("input", { type: "date", value: s.program_start_date || PROGRAM.startDateDefault });
  const phase = h("select", null, [["", "Follow the plan (weeks 1 to 2, 3 to 6, 7+)"], ["1", "Phase 1: Tune-up"], ["2", "Phase 2: Power"], ["3", "Phase 3: Reactive"]].map(([v, l]) => h("option", { value: v, selected: String(s.phase_override || "") === v }, l)));
  const goal = h("input", { type: "number", step: "0.5", value: s.goal_weight_kg || PROGRAM.body.goalWeightKg });
  const kcal = h("input", { type: "number", step: "10", value: s.calorie_target || PROGRAM.nutrition.calories });
  const prot = h("input", { type: "number", step: "5", value: s.protein_target || PROGRAM.nutrition.proteinG });
  const maxHr = h("input", { type: "number", step: "1", value: s.max_hr || 190 });
  const fiveK = h("input", { type: "text", value: fmtTime(Number(s.five_k_target_sec) || PROGRAM.running.fiveKTargetSec) });
  form.appendChild(h("h3", null, "Plan"));
  form.appendChild(h("label", { class: "field" }, h("span", null, "Week 1 starts on (Monday)"), start));
  form.appendChild(h("label", { class: "field" }, h("span", null, "Jump phase"), phase));
  form.appendChild(h("h3", null, "Targets"));
  form.appendChild(h("div", { class: "inline-fields" },
    h("label", { class: "field" }, h("span", null, "Goal weight (kg)"), goal),
    h("label", { class: "field" }, h("span", null, "Calories per day"), kcal),
    h("label", { class: "field" }, h("span", null, "Protein per day (g)"), prot),
    h("label", { class: "field" }, h("span", null, "Max heart rate (for zones)"), maxHr),
    h("label", { class: "field" }, h("span", null, "5 km target (mm:ss)"), fiveK)));
  form.appendChild(h("button", { class: "btn primary", onClick: async () => {
    try {
      const body = { program_start_date: start.value, phase_override: phase.value || null, goal_weight_kg: goal.value, calorie_target: kcal.value, protein_target: prot.value, max_hr: maxHr.value, five_k_target_sec: parseTime(fiveK.value) };
      state.settings = await api.put("/api/settings", body);
      store.set("ft_settings", state.settings);
      toast("Settings saved");
    } catch (e) { toast(e.message, true); }
  } }, "Save settings"));
  container.appendChild(form);

  container.appendChild(h("div", { class: "card" },
    h("h3", null, "The plan in short"),
    h("p", { class: "small" }, "Mon Lift A + jumps. Tue intervals (6 × 2 min weeks 1 to 4, 5 × 3 min weeks 5 to 8, 4 × 4 min from week 9). Wed Lift B + jumps. Thu easy zone 2 run. Fri Lift C + finisher. Sat off or a long walk. Sun padel (not counted). 5 km time trial in weeks 1, 8 and 16. Deload every 6th week."),
    h("p", { class: "small muted" }, "Diet: about 2,450 kcal and 170 g protein a day, with a weekly fun budget of about 2,500 kcal for beer and sweets. Weigh in 3 mornings a week; aim for 0.4 to 0.6 kg a week.")));

  container.appendChild(h("div", { class: "card" },
    h("h3", null, "How Claude reads this data"),
    h("p", { class: "small" }, "Two ways. Easiest: on the Data page, press \"Copy summary for Claude\" or download the JSON export and paste or upload it in the Claude project. Automatic: Claude can call the API directly with the API token (set with wrangler secret put API_TOKEN):"),
    h("pre", { class: "small", style: { overflowX: "auto", background: "var(--surface-2)", padding: ".6rem", borderRadius: "8px" } },
      `curl -H "Authorization: Bearer $API_TOKEN" ${location.origin}/api/export.json\ncurl -H "Authorization: Bearer $API_TOKEN" ${location.origin}/api/summary.md\ncurl -X POST -H "Authorization: Bearer $API_TOKEN" -H "Content-Type: application/json" \\\n  -d '{"title":"Week 4 review","body_md":"# ..."}' ${location.origin}/api/reports`),
    h("p", { class: "small muted" }, "Reports posted that way show up on the Data page.")));

  container.appendChild(h("div", { class: "card" },
    h("h3", null, "Account"),
    h("div", { class: "row" },
      h("button", { class: "btn", onClick: async () => { await api.post("/api/logout"); location.href = "/login"; } }, "Log out"),
      h("button", { class: "btn ghost", onClick: () => { Object.keys(localStorage).filter((k) => k.startsWith("ft_day_") || k.startsWith("ft_active_")).forEach((k) => localStorage.removeItem(k)); toast("Local cache cleared"); } }, "Clear local cache"))));
}
