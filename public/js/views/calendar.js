// Calendar: month grid of planned sessions. Tap a day to open it, swap it with another day, or change its session.
import { api } from "../api.js";
import { h, clear, toast, modal, fmtDay, segmented, MONTHS_LONG, store } from "../util.js";
import { PROGRAM, addDays, mondayOf, todayLocal, WEEKDAYS, templateFor, daysBetween } from "../program.js";
import { navigate } from "../app.js";

export const SHORT_NAMES = { lift_a: "Lift A", lift_b: "Lift B", lift_c: "Lift C", intervals_6x2: "Intervals", intervals_5x3: "Intervals", intervals_4x4: "Intervals", time_trial_5k: "5 km TT", easy_run: "Easy run", rest_walk: "Off", rest_padel: "Padel", other: "Other" };
const PHONE_NAMES = { lift_a: "Lift A", lift_b: "Lift B", lift_c: "Lift C", intervals_6x2: "Int", intervals_5x3: "Int", intervals_4x4: "Int", time_trial_5k: "5 km", easy_run: "Easy", rest_walk: "Off", rest_padel: "Padel", other: "Other" };
export const PICKABLE = ["lift_a", "lift_b", "lift_c", "intervals_6x2", "intervals_5x3", "intervals_4x4", "time_trial_5k", "easy_run", "other", "rest_walk"];

export async function renderCalendar(container, { month }) {
  const today = todayLocal();
  const ym = month || today.slice(0, 7);
  const view = new CalendarView(container, ym, today);
  await view.load();
  view.render();
  return () => {};
}

function monthRange(ym) {
  const [y, m] = ym.split("-").map(Number);
  const first = `${ym}-01`;
  const last = `${ym}-${String(new Date(Date.UTC(y, m, 0)).getUTCDate()).padStart(2, "0")}`;
  return { first, last, gridStart: mondayOf(first), gridEnd: addDays(mondayOf(last), 6) };
}
function shiftMonth(ym, n) {
  const [y, m] = ym.split("-").map(Number);
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

class CalendarView {
  constructor(container, ym, today) {
    this.container = container; this.ym = ym; this.today = today; this.swapFrom = null;
  }
  async load() {
    const r = monthRange(this.ym);
    this.range = r;
    this.data = await api.get(`/api/schedule?from=${r.gridStart}&to=${r.gridEnd}`);
    this.days = this.data.days;
  }
  dayFor(date) { return this.days.find((d) => d.date === date); }
  mainWorkout(d) { return d.workouts.find((w) => w.template_key === d.templateKey) || d.workouts.find((w) => w.status !== "skipped") || d.workouts[0] || null; }

  render() {
    const c = this.container;
    clear(c);
    const [y, m] = this.ym.split("-").map(Number);
    c.appendChild(h("div", { class: "page-head" },
      h("div", null, h("h1", null, "Calendar"), h("div", { class: "sub" }, "Tap a day to open it, or move its session")),
      h("div", { class: "controls" }, segmented([{ label: "Month", href: "/calendar" }, { label: "List", href: "/history" }], 0))));

    const card = h("div", { class: "card" });
    card.appendChild(h("div", { class: "cal-head" },
      h("button", { class: "btn icon", "aria-label": "Previous month", onClick: () => navigate(`/calendar/${shiftMonth(this.ym, -1)}`) }, "‹"),
      h("div", { class: "row", style: { gap: ".5rem" } }, h("h2", null, `${MONTHS_LONG[m - 1]} ${y}`), this.ym !== this.today.slice(0, 7) ? h("button", { class: "btn text small", onClick: () => navigate("/calendar") }, "Today") : null),
      h("button", { class: "btn icon", "aria-label": "Next month", onClick: () => navigate(`/calendar/${shiftMonth(this.ym, 1)}`) }, "›")));
    if (this.swapFrom) {
      const f = this.dayFor(this.swapFrom);
      card.appendChild(h("div", { class: "banner info swap-banner" }, h("span", null, `Swapping ${f.name} (${fmtDay(f.date)}). Tap the other day.`), h("button", { class: "btn small", onClick: () => { this.swapFrom = null; this.render(); } }, "Cancel")));
    }
    card.appendChild(h("div", { class: "cal-weekdays" }, WEEKDAYS.map((w) => h("span", null, w))));
    const grid = h("div", { class: "cal-grid" });
    for (const d of this.days) grid.appendChild(this.cell(d));
    card.appendChild(grid);
    card.appendChild(h("div", { class: "cal-legend" },
      h("span", null, h("b", { class: "kind-lift" }, "Lift")), h("span", null, h("b", { class: "kind-run" }, "Run")),
      h("span", null, h("b", { class: "ok" }, "Done")), h("span", null, h("i", { style: { background: "var(--accent)", width: "6px", height: "6px" } }), "Moved from the plan")));
    c.appendChild(card);
    c.appendChild(this.summaryCard());
  }

  cell(d) {
    const w = this.mainWorkout(d);
    const inMonth = d.date.startsWith(this.ym);
    const cls = ["cal-cell", d.kind, w ? w.status : "", inMonth ? "" : "out", d.date === this.today ? "today" : "", d.moved ? "moved" : "",
      this.swapFrom === d.date ? "swap-source" : this.swapFrom ? "swap-target" : ""].join(" ");
    const extras = d.workouts.filter((x) => x !== w && x.status !== "skipped");
    const el = h("div", { class: cls, role: "button", tabindex: "0", title: `${fmtDay(d.date)}: ${d.name}` },
      h("span", { class: "d" }, String(Number(d.date.slice(8)))),
      h("span", { class: "s" }, h("i", { class: "dot" }), h("span", { class: "lbl-long" }, SHORT_NAMES[d.templateKey] || d.name), h("span", { class: "lbl-short" }, PHONE_NAMES[d.templateKey] || d.name)),
      extras.length ? h("span", { class: "extra" }, `+${extras.length} more`) : d.date.slice(8) !== "01" && d.date === mondayOf(d.date) && d.week >= 1 ? h("span", { class: "extra" }, `Wk ${d.week}`) : null);
    const act = () => (this.swapFrom ? this.confirmSwap(d) : this.daySheet(d));
    el.addEventListener("click", act);
    el.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); act(); } });
    return el;
  }

  summaryCard() {
    const inMonth = this.days.filter((d) => d.date.startsWith(this.ym));
    const planned = inMonth.filter((d) => d.kind !== "rest");
    const done = planned.filter((d) => { const w = this.mainWorkout(d); return w && w.status === "done"; }).length;
    const past = planned.filter((d) => d.date < this.today).length;
    const skipped = planned.filter((d) => { const w = this.mainWorkout(d); return w && w.status === "skipped"; }).length;
    const lifts = planned.filter((d) => d.kind === "lift").length, runs = planned.filter((d) => d.kind === "run").length;
    return h("div", { class: "card" },
      h("div", { class: "card-title" }, h("h3", null, "This month"), h("span", { class: `badge ${done && done >= past ? "ok" : ""}` }, `${done} of ${planned.length} done`)),
      h("p", { class: "muted small", style: { margin: 0 } }, `${lifts} lifting days and ${runs} runs planned${skipped ? `, ${skipped} skipped` : ""}${past > done ? `, ${past - done} past without a log` : ""}. Extras like padel are not counted.`));
  }

  daySheet(d) {
    const w = this.mainWorkout(d);
    const t = templateFor(d.templateKey);
    const info = h("div", null,
      h("div", { class: `kind-label kind-${d.kind}` }, d.kind === "rest" ? "Rest" : d.kind),
      h("h2", { style: { marginBottom: ".1rem" } }, d.name),
      h("div", { class: "muted small" }, [t.subtitle, d.deload ? "deload week" : null, d.testWeek ? "test week" : null].filter(Boolean).join(" · ")),
      d.moved ? h("div", { class: "muted small", style: { marginTop: ".3rem" } }, `Moved. The plan has ${templateFor(d.defaultTemplateKey).name} on this day.`) : null,
      w ? h("div", { style: { marginTop: ".5rem" } }, h("span", { class: `badge ${w.status === "done" ? "ok" : w.status === "skipped" ? "danger" : "accent"}` }, w.status.replace("_", " ")), " ",
        h("span", { class: "muted small" }, [w.set_count ? `${w.set_count} sets` : null, w.distance_km ? `${w.distance_km} km` : null].filter(Boolean).join(" · "))) : null);
    const list = h("div", { class: "action-list", style: { marginTop: ".8rem" } });
    const item = (title, sub, cls, fn) => list.appendChild(h("div", { class: `list-item ${cls || ""}`, onClick: fn }, h("div", null, h("div", { class: "title" }, title), sub ? h("div", { class: "sub" }, sub) : null), h("span", { class: "chev" }, "›")));
    item("Open this day", d.date === this.today ? "Today" : fmtDay(d.date, true), "accent", () => { close(); navigate(`/day/${d.date}`); });
    item("Swap with another day", "Then tap the day to swap with", "", () => { close(); this.swapFrom = d.date; this.render(); toast("Tap the other day"); });
    item("Change the session on this day", "Pick any session, without touching other days", "", () => { close(); this.pickTemplate(d); });
    if (d.moved) item(`Back to the plan: ${templateFor(d.defaultTemplateKey).name}`, "Removes the change for this day", "", async () => { close(); await this.setDay(d.date, null); });
    const close = modal({ title: fmtDay(d.date, true), content: h("div", null, info, list), actions: [{ label: "Close", class: "ghost" }] });
  }

  pickTemplate(d) {
    const list = h("div", { class: "search-list action-list" });
    for (const k of PICKABLE) {
      const t = PROGRAM.templates[k];
      list.appendChild(h("div", { class: "list-item", onClick: async () => { close(); if (k !== d.templateKey) await this.setDay(d.date, k); } },
        h("div", null, h("div", { class: `title kind-${t.kind}` }, t.name, k === d.defaultTemplateKey ? h("span", { class: "badge", style: { marginLeft: ".4rem" } }, "planned") : null, k === d.templateKey && k !== d.defaultTemplateKey ? h("span", { class: "badge accent", style: { marginLeft: ".4rem" } }, "current") : null), h("div", { class: "sub" }, t.subtitle)),
        h("span", { class: "chev" }, "›")));
    }
    const close = modal({ title: `Session for ${fmtDay(d.date)}`, content: list, actions: [{ label: "Cancel", class: "ghost" }] });
  }

  confirmSwap(d) {
    if (d.date === this.swapFrom) { this.swapFrom = null; this.render(); return; }
    const a = this.dayFor(this.swapFrom), b = d;
    const content = h("div", null,
      h("p", null, h("b", null, fmtDay(a.date)), ` becomes ${b.name}.`),
      h("p", null, h("b", null, fmtDay(b.date)), ` becomes ${a.name}.`),
      a.kind === "lift" && b.kind === "lift" ? null : h("p", { class: "muted small" }, "Anything already logged stays on its day."));
    modal({ title: "Swap these two days?", content, actions: [
      { label: "Cancel", class: "ghost", onClick: () => { this.swapFrom = null; this.render(); } },
      { label: "Swap", class: "primary", onClick: async () => {
        try {
          await api.post("/api/schedule/swap", { a: a.date, b: b.date });
          store.del(`ft_active_${a.date}`); store.del(`ft_active_${b.date}`); store.del(`ft_day_${a.date}`); store.del(`ft_day_${b.date}`);
          toast("Swapped");
        } catch (e) { toast(e.message, true); }
        this.swapFrom = null;
        await this.load(); this.render();
      } },
    ] });
  }

  async setDay(date, key) {
    try {
      await api.put(`/api/schedule/${date}`, { template_key: key });
      store.del(`ft_active_${date}`); store.del(`ft_day_${date}`);
      toast(key ? "Session changed" : "Back to the plan");
    } catch (e) { toast(e.message, true); }
    await this.load(); this.render();
  }
}
