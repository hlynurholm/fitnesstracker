// Today / day view: the logging screen.
import { api, queuedWrite } from "../api.js";
import { h, clear, toast, modal, fmtDay, fmtShort, uuid, debounce, store, secondsToHms, fmtKg } from "../util.js";
import { PROGRAM, templateFor, exerciseFor, addDays, mondayOf, todayLocal, e1rm, fmtTime, parseTime, fmtPace, WEEKDAYS } from "../program.js";
import { state } from "../app.js";
import { PICKABLE } from "./calendar.js";

const FIELD_META = {
  kg: { label: "kg", attrs: { type: "number", inputmode: "decimal", step: "0.5", min: "0" } },
  reps: { label: "reps", attrs: { type: "number", inputmode: "numeric", step: "1", min: "0" } },
  seconds: { label: "sec", attrs: { type: "number", inputmode: "numeric", step: "5", min: "0" } },
  meters: { label: "m", attrs: { type: "number", inputmode: "numeric", step: "5", min: "0" } },
};
const FIELD_TO_COL = { kg: "weight_kg", reps: "reps", seconds: "seconds", meters: "distance_m" };

export async function renderToday(container, { date }) {
  const cacheKey = `ft_day_${date}`;
  let data, offline = false;
  try {
    data = await api.get(`/api/day/${date}`);
    store.set(cacheKey, data);
  } catch (e) {
    data = store.get(cacheKey);
    if (!data) throw e;
    offline = true;
  }
  const view = new DayView(container, date, data, offline);
  view.render();
  return () => view.destroy();
}

class DayView {
  constructor(container, date, data, offline) {
    this.container = container;
    this.date = date;
    this.data = data;
    this.offline = offline;
    this.day = data.day;
    this.today = data.today || todayLocal();
    const preferred = store.get(`ft_active_${date}`);
    this.workout = (preferred && data.workouts.find((w) => w.template_key === preferred)) || data.active || null;
    this.templateKey = this.workout ? this.workout.template_key : this.day.templateKey;
    this.template = templateFor(this.templateKey);
    this.plan = this.workout && Array.isArray(this.workout.plan) && this.workout.plan.length ? this.workout.plan : this.day.templateKey === this.templateKey ? this.day.plan : buildPlanFor(this.templateKey, this.day.week);
    this.checklist = (this.workout && this.workout.checklist) || {};
    this.blockNotes = { ...((this.workout && this.workout.block_notes) || {}) }; // exercise key or warmup | jumps | finisher
    this.rows = {};
    this.lastTick = null;
    this.timer = null;
    this.countdown = null; // running set countdown { label, endsAt, stop }
    this.wakeLock = null;
    this.editing = false; // a finished workout opened for corrections
    this.initRows();
    this.saveWorkoutDebounced = debounce((patch) => this.saveWorkout(patch), 600);
    this.noteSavers = {};
    this.onVisible = () => { if (document.visibilityState === "visible" && this.mode() === "log") this.keepAwake(); };
    document.addEventListener("visibilitychange", this.onVisible);
  }

  destroy() {
    if (this.timer) clearInterval(this.timer);
    if (this.countdown) this.countdown.stop(true);
    document.removeEventListener("visibilitychange", this.onVisible);
    this.releaseWakeLock();
    this.container.classList.remove("with-bar");
  }

  // Keep the screen on while logging. Safari and Chrome support it; elsewhere it quietly does nothing.
  async keepAwake() {
    if (!("wakeLock" in navigator) || this.wakeLock) return;
    try { this.wakeLock = await navigator.wakeLock.request("screen"); this.wakeLock.addEventListener("release", () => { this.wakeLock = null; }); } catch { this.wakeLock = null; }
  }
  releaseWakeLock() { if (this.wakeLock) { try { this.wakeLock.release(); } catch {} this.wakeLock = null; } }

  // ---------- notes per exercise or block ----------
  saveNote(block, text) {
    this.blockNotes[block] = text;
    if (!this.noteSavers[block]) this.noteSavers[block] = debounce(async (t) => {
      const body = { template_key: this.templateKey, block, note: t };
      const r = await queuedWrite("PUT", `/api/day/${this.date}/notes`, body, `note:${this.date}:${this.templateKey}:${block}`);
      if (r.ok && r.data && r.data.workout_id && !this.workout) { this.workout = { id: r.data.workout_id, template_key: this.templateKey, status: "in_progress", sets: [] }; store.set(`ft_active_${this.date}`, this.templateKey); }
      this.refreshCache();
    }, 700);
    this.noteSavers[block](text);
  }

  // A "Note" toggle with an auto-growing textarea under it. Open from the start when a note exists.
  noteField(block, placeholder) {
    const existing = this.blockNotes[block] || "";
    const wrap = h("div", { class: "note-field" + (existing ? " open" : "") });
    const ta = h("textarea", { rows: 1, placeholder, "aria-label": placeholder });
    ta.value = existing;
    const grow = () => { ta.style.height = "auto"; ta.style.height = Math.min(200, ta.scrollHeight) + "px"; };
    ta.addEventListener("input", () => { grow(); this.saveNote(block, ta.value); });
    const btn = h("button", { class: "btn text note-toggle", onClick: () => { wrap.classList.add("open"); ta.focus(); requestAnimationFrame(grow); } }, existing ? "Note" : "+ Note");
    wrap.appendChild(btn);
    wrap.appendChild(ta);
    if (existing) requestAnimationFrame(grow);
    return wrap;
  }

  initRows() {
    const sets = Object.keys(this.rows).length ? this.allSets() : this.workout ? this.workout.sets || [] : [];
    this.rows = {};
    for (const e of this.plan) {
      const existing = sets.filter((s) => s.exercise_key === e.key).sort((a, b) => a.set_index - b.set_index || a.id - b.id);
      const rows = existing.map((s) => ({ client_id: s.client_id, set_index: s.set_index, kg: s.weight_kg, reps: s.reps, seconds: s.seconds, meters: s.distance_m, saved: isDone(s), touched: true }));
      while (rows.length < e.sets) rows.push({ client_id: uuid(), set_index: rows.length, kg: null, reps: null, seconds: null, meters: null, saved: false });
      this.rows[e.key] = rows;
    }
    // Sets logged for exercises no longer in the plan (keep them visible).
    for (const s of sets) if (!this.rows[s.exercise_key]) {
      this.plan.push({ key: s.exercise_key, sets: 0, reps: "", added: true });
      this.rows[s.exercise_key] = [];
    }
    for (const s of sets) if (!this.rows[s.exercise_key].some((r) => r.client_id === s.client_id)) {
      this.rows[s.exercise_key].push({ client_id: s.client_id, set_index: s.set_index, kg: s.weight_kg, reps: s.reps, seconds: s.seconds, meters: s.distance_m, saved: isDone(s), touched: true });
    }
  }

  // ---------- persistence ----------
  async saveWorkout(patch) {
    const body = { template_key: this.templateKey, ...patch };
    const r = await queuedWrite("PUT", `/api/day/${this.date}/workout`, body, `workout:${this.date}:${this.templateKey}:${Object.keys(patch).join(",")}`);
    if (r.ok && r.data && r.data.id) {
      const w = r.data;
      this.workout = { ...(this.workout || {}), ...w, sets: this.workout ? this.workout.sets || [] : w.sets || [] };
      store.set(`ft_active_${this.date}`, this.templateKey);
      this.refreshCache();
    }
    return r;
  }

  refreshCache() {
    const d = this.data;
    const idx = d.workouts.findIndex((w) => w.template_key === this.templateKey);
    const merged = { ...(this.workout || { template_key: this.templateKey, date: this.date, status: "in_progress" }), sets: this.allSets(), plan: this.plan, checklist: this.checklist, block_notes: this.blockNotes };
    if (idx >= 0) d.workouts[idx] = merged; else d.workouts.push(merged);
    d.active = merged;
    store.set(`ft_day_${this.date}`, d);
  }

  // Every row with a value, ticked or draft (done 0). Used for the cache and for rebuilding rows.
  allSets() {
    const out = [];
    for (const [key, rows] of Object.entries(this.rows)) for (const r of rows) if (r.saved || r.touched) out.push({ client_id: r.client_id, exercise_key: key, set_index: r.set_index, weight_kg: r.kg, reps: r.reps, seconds: r.seconds, distance_m: r.meters, done: r.saved ? 1 : 0 });
    return out;
  }
  doneSets() { return this.allSets().filter((s) => s.done); }

  async saveSet(key, row) {
    const ex = exerciseFor(key);
    const hasValue = ex.fields.some((f) => row[f] != null && row[f] !== "");
    if (!hasValue) return;
    row.touched = true;
    if (row.saved) this.lastTick = Date.now();
    this.refreshCache();
    const body = { date: this.date, template_key: this.templateKey, exercise_key: key, set_index: row.set_index, weight_kg: row.kg, reps: row.reps, seconds: row.seconds, distance_m: row.meters, done: row.saved ? 1 : 0 };
    const r = await queuedWrite("PUT", `/api/sets/${row.client_id}`, body, `set:${row.client_id}`);
    if (r.ok && r.data && r.data.workout_id && !this.workout) {
      this.workout = { id: r.data.workout_id, template_key: this.templateKey, status: "in_progress", sets: [] };
      store.set(`ft_active_${this.date}`, this.templateKey);
    }
    this.updateStatusBadge();
  }

  async deleteSet(key, row) {
    const rows = this.rows[key];
    rows.splice(rows.indexOf(row), 1);
    rows.forEach((r, i) => (r.set_index = i));
    if (row.saved || row.touched) {
      this.refreshCache();
      try { await api.del(`/api/sets/${row.client_id}`); } catch (e) { toast(e.message, true); }
    }
  }

  // Re-fetch the day from the server and draw it again (after schedule changes or uploads).
  async reload() {
    try {
      const fresh = await api.get(`/api/day/${this.date}`);
      store.set(`ft_day_${this.date}`, fresh);
      this.destroy();
      new DayView(this.container, this.date, fresh, false).render();
    } catch (e) { toast(e.message, true); }
  }

  // ---------- rendering ----------
  render() {
    const c = this.container;
    clear(c);
    c.classList.remove("with-bar");
    if (this.template.kind === "lift" && this.mode() === "log") this.keepAwake(); else this.releaseWakeLock();
    const day = this.day;
    const isToday = this.date === this.today;
    if (this.offline) c.appendChild(h("div", { class: "banner" }, "Offline: showing the last saved copy of this day. New entries are saved on the phone and synced later."));

    c.appendChild(h("div", { class: "page-head" },
      h("div", null,
        h("h1", null, isToday ? "Today" : fmtDay(this.date)),
        h("div", { class: "sub" }, isToday ? fmtDay(this.date, true) : h("a", { href: "/" }, "Back to today"))),
      h("div", { class: "controls" },
        h("a", { class: "btn icon", href: `/day/${addDays(this.date, -1)}`, "aria-label": "Previous day" }, "‹"),
        h("a", { class: "btn icon", href: `/day/${addDays(this.date, 1)}`, "aria-label": "Next day" }, "›"))));

    const meta = h("div", { class: "day-meta" });
    if (day.week >= 1) meta.appendChild(h("span", { class: "badge accent" }, `Week ${day.week}`));
    meta.appendChild(h("span", { class: "badge" }, `Phase ${day.phase}: ${day.phaseName}`));
    if (day.deload) meta.appendChild(h("span", { class: "badge warn" }, "Deload week"));
    if (day.testWeek) meta.appendChild(h("span", { class: "badge warn" }, "Test week"));
    if (day.moved) meta.appendChild(h("span", { class: "badge accent" }, "Moved from the plan"));
    if (day.beyondPlan) meta.appendChild(h("span", { class: "badge" }, "Beyond the 16 planned weeks"));
    c.appendChild(meta);
    if (day.beforeStart) c.appendChild(h("div", { class: "banner info" }, `The plan starts Monday ${fmtShort(day.startDate)}. This shows the normal session for a ${day.weekdayName}.`));
    if (day.deload) c.appendChild(h("div", { class: "banner" }, "Deload: every 6th week all sets are cut in half. Keep the weight, do half the sets."));

    c.appendChild(this.weekStrip());
    c.appendChild(this.bodyWeightCard());
    for (const card of this.sessionCards()) c.appendChild(card);

    const others = this.data.workouts.filter((w) => w.template_key !== this.templateKey);
    if (others.length) {
      c.appendChild(h("div", { class: "section-title" }, "Also on this day"));
      for (const w of others) c.appendChild(this.otherWorkoutCard(w));
    }
    if (day.testWeek) c.appendChild(this.testsCard());
    if (this.template.kind !== "lift" && this.template.kind !== "run") c.appendChild(this.kneeCard());
    else if (this.template.kind === "run") c.appendChild(this.kneeCard(true));
    this.startTimer();
  }

  weekStrip() {
    const strip = h("div", { class: "week-strip" });
    this.data.week.forEach((d, i) => {
      const w = d.workouts.find((x) => x.template_key === d.templateKey) || d.workouts.find((x) => x.status !== "skipped") || d.workouts[0];
      const cls = ["week-day", d.kind, w ? w.status : "", d.date === this.today ? "today" : "", d.date === this.date ? "selected" : "", d.moved ? "moved" : ""].join(" ");
      strip.appendChild(h("a", { class: cls, href: `/day/${d.date}`, title: d.name, "aria-current": d.date === this.date ? "date" : null },
        WEEKDAYS[i].slice(0, 3),
        h("b", null, String(Number(d.date.slice(8)))),
        h("span", { class: "dot" })));
    });
    return strip;
  }

  bodyWeightCard() {
    const input = h("input", { type: "number", inputmode: "decimal", step: "0.1", min: "30", max: "300", placeholder: "kg", value: this.data.body && this.data.body.weight_kg != null ? this.data.body.weight_kg : "", style: { maxWidth: "104px", textAlign: "center" } });
    const save = async () => {
      const v = input.value === "" ? null : Number(input.value);
      const r = await queuedWrite("PUT", "/api/body", { date: this.date, weight_kg: v }, `body:${this.date}`);
      if (r.ok) { toast(v == null ? "Weigh-in removed" : "Weight saved"); this.data.body = v == null ? null : { date: this.date, weight_kg: v }; store.set(`ft_day_${this.date}`, this.data); }
    };
    input.addEventListener("change", save);
    return h("div", { class: "card row between", style: { flexWrap: "nowrap" } },
      h("div", null, h("div", { style: { fontWeight: 600 } }, "Morning weight"), h("div", { class: "muted small" }, "Three mornings a week is enough.")),
      input);
  }

  statusBadge() {
    const st = this.workout ? this.workout.status : null;
    const logged = this.doneSets().length;
    if (st === "done") return h("span", { class: "badge ok" }, "Done");
    if (st === "skipped") return h("span", { class: "badge danger" }, "Skipped");
    if (this.template.kind === "lift") return this.workout && this.workout.started_at ? h("span", { class: "badge accent" }, "In progress") : h("span", { class: "badge" }, "Not started");
    if (logged || (this.workout && this.workout.time_sec)) return h("span", { class: "badge accent" }, "In progress");
    return h("span", { class: "badge" }, "Not started");
  }
  updateStatusBadge() { const el = this.container.querySelector("[data-status]"); if (el) { clear(el); el.appendChild(this.statusBadge()); } }

  sessionCards() {
    const t = this.template;
    const cards = [];
    const head = h("div", { class: "card session-card" });
    head.appendChild(h("div", { class: "card-title" },
      h("div", null,
        h("div", { class: `kind-label kind-${t.kind}` }, [t.kind === "rest" ? "Rest" : t.kind === "other" ? "Other" : t.kind, t.duration].filter(Boolean).join(" · ")),
        h("h2", { style: { margin: 0 } }, t.name),
        t.subtitle ? h("div", { class: "muted small" }, t.subtitle) : null),
      h("div", { dataset: { status: "1" } }, this.statusBadge())));
    if (this.day.moved && this.templateKey === this.day.templateKey) head.appendChild(h("p", { class: "muted small" }, `The plan has ${templateFor(this.day.defaultTemplateKey).name} today. You moved it.`));
    for (const x of this.day.extras || []) if (this.templateKey === this.day.templateKey) head.appendChild(h("p", { class: "muted small" }, x));
    if (t.kind === "lift") {
      const mode = this.mode();
      if (t.tips && t.tips.length) head.appendChild(h("p", { class: "tips" }, t.tips.join(" ")));
      if (mode === "overview") {
        head.appendChild(h("button", { class: "btn primary wide", style: { marginTop: ".9rem" }, onClick: () => this.startWorkout() }, "Start workout"));
        cards.push(head, this.planCard(), this.actionsCard());
      } else if (mode === "log") {
        cards.push(head, ...this.liftCards(), this.finishCard(), this.actionsCard(), this.timerBar());
      } else {
        cards.push(head, ...this.summaryCards(), this.actionsCard());
      }
      return cards;
    }
    if (t.kind === "run" || t.kind === "other") this.runBody(head); else this.restBody(head);
    cards.push(head, this.finishCard(), this.actionsCard());
    return cards;
  }

  // overview: nothing started yet. log: started, or a finished workout opened for edits. summary: finished.
  mode() {
    const w = this.workout;
    if (w && w.status === "done") return this.editing ? "log" : "summary";
    if (w && (w.started_at || (w.sets || []).length)) return "log";
    return "overview";
  }

  async startWorkout() {
    const r = await this.saveWorkout({ status: "in_progress", started_at: new Date().toISOString() });
    if (!r.ok && !r.queued) return;
    if (!this.workout) this.workout = { template_key: this.templateKey, status: "in_progress", sets: [] };
    this.workout.started_at = this.workout.started_at || new Date().toISOString();
    this.refreshCache();
    toast("Workout started");
    this.render();
    window.scrollTo({ top: 0 });
  }

  // What the session holds, without any inputs.
  planCard() {
    const t = this.template;
    const card = h("div", { class: "card" });
    card.appendChild(h("div", { class: "card-title" }, h("h3", null, "Plan"), h("span", { class: "muted small" }, `${this.plan.length} lifts`)));
    const list = h("div", null);
    const row = (title, sub, extra) => list.appendChild(h("div", { class: "list-item" }, h("div", null, h("div", { class: "title" }, title), sub ? h("div", { class: "sub" }, sub) : null), extra ? h("span", { class: "muted small" }, extra) : null));
    if (t.blocks.includes("warmup")) row(PROGRAM.warmup.title, `${PROGRAM.warmup.items.length} drills`, `${PROGRAM.warmup.minutes} min`);
    if (t.blocks.includes("jumps")) row(`${PROGRAM.jumps.title}, phase ${this.day.phase}`, (PROGRAM.jumps.byPhase[this.day.phase] || []).map((j) => j.name).join(", "), `${PROGRAM.jumps.minutes} min`);
    for (const e of this.plan) {
      const ex = exerciseFor(e.key);
      const last = this.data.last[e.key];
      const target = e.sets ? `${e.sets} × ${e.reps}${e.sets !== e.plannedSets && e.plannedSets ? " (deload)" : ""}` : "";
      row(ex.name, [target, last ? `last ${describeSets(ex, last.sets)}` : e.startKg ? `start around ${e.startKg} kg` : null].filter(Boolean).join(" · "));
    }
    if (t.blocks.includes("finisher") && t.finisher) row(t.finisher.title, t.finisher.text, `${t.finisher.minutes} min`);
    card.appendChild(list);
    return card;
  }

  // Finished workout: results per lift, duration, notes, and a way back in to fix mistakes.
  summaryCards() {
    const w = this.workout;
    const cards = [];
    const card = h("div", { class: "card" });
    const dur = w.duration_min || minutesBetween(w.started_at, w.finished_at);
    card.appendChild(h("div", { class: "card-title" }, h("h3", null, "Results"), h("span", { class: "muted small" }, [dur ? `${dur} min` : null, w.rpe ? `RPE ${w.rpe}` : null].filter(Boolean).join(" · "))));
    const done = this.doneSets();
    const list = h("div", null);
    for (const e of this.plan) {
      const ex = exerciseFor(e.key);
      const sets = done.filter((s) => s.exercise_key === e.key).sort((a, b) => a.set_index - b.set_index);
      const note = this.blockNotes[e.key];
      list.appendChild(h("div", { class: "list-item" }, h("div", null, h("div", { class: "title" }, ex.name), h("div", { class: "sub" }, sets.length ? describeSets(ex, sets) : "not logged"), note ? h("div", { class: "sub note" }, note) : null), h("span", { class: `badge ${sets.length ? "ok" : ""}` }, `${sets.length}${e.sets ? `/${e.sets}` : ""}`)));
    }
    card.appendChild(list);
    const blocks = ["warmup", "jumps", "finisher"].filter((b) => this.template.blocks.includes(b) && this.checklist[b]);
    if (blocks.length) card.appendChild(h("p", { class: "muted small", style: { margin: ".8rem 0 0" } }, blocks.map((b) => `${BLOCK_NAMES[b]} ${Object.values(this.checklist[b]).filter(Boolean).length} ticked`).join(" · ")));
    for (const b of ["warmup", "jumps", "finisher"]) if (this.blockNotes[b]) card.appendChild(h("p", { class: "small", style: { margin: ".4rem 0 0" } }, h("span", { class: "muted" }, `${BLOCK_NAMES[b]}: `), this.blockNotes[b]));
    if (w.notes) card.appendChild(h("p", { style: { margin: ".8rem 0 0" } }, w.notes));
    card.appendChild(h("button", { class: "btn tinted wide", style: { marginTop: "1rem" }, onClick: () => { this.editing = true; this.render(); } }, "Edit workout"));
    cards.push(card);
    return cards;
  }

  // ----- lift -----
  liftCards() {
    const t = this.template;
    const cards = [];
    if (t.blocks.includes("warmup")) cards.push(h("div", { class: "card" }, this.checklistBlock("warmup", `${PROGRAM.warmup.title} (${PROGRAM.warmup.minutes} min)`, PROGRAM.warmup.items, PROGRAM.warmup.note)));
    if (t.blocks.includes("jumps")) {
      const items = (PROGRAM.jumps.byPhase[this.day.phase] || []).map((j) => ({ id: j.id, text: `${j.name}: ${j.sets}`, sub: j.note }));
      cards.push(h("div", { class: "card" }, this.checklistBlock("jumps", `${PROGRAM.jumps.title}, phase ${this.day.phase} (${PROGRAM.jumps.minutes} min)`, items, `${PROGRAM.jumps.note} ${PROGRAM.jumps.phaseNotes[this.day.phase] || ""}`)));
    }
    cards.push(h("div", { class: "section-title" }, "Lifts"));
    for (const e of this.plan) cards.push(this.exerciseBlock(e));
    cards.push(h("button", { class: "btn tinted wide add-exercise", onClick: () => this.addExerciseDialog() }, "+ Add an exercise"));
    if (t.blocks.includes("finisher") && t.finisher) {
      cards.push(h("div", { class: "card" }, this.checklistBlock("finisher", t.finisher.title, [{ id: "done", text: t.finisher.text }], null, true)));
    }
    cards.push(h("p", { class: "muted small", style: { margin: "1rem .25rem 0" } }, "Progression: once you hit the top of the rep range on every set with 1 to 2 reps left, add weight next time (2.5 kg for barbell, one dumbbell step). Bad week? Minimum version: Lift A, Lift B and one interval session at about 45 min each. Keep the jumps, cut the accessories."));
    return cards;
  }

  checklistBlock(blockId, title, items, note, open = false) {
    const ticked = this.checklist[blockId] || {};
    const total = items.length, doneCount = items.filter((i) => ticked[i.id]).length;
    const det = h("details", { open: open || (doneCount > 0 && doneCount < total) });
    const sum = h("summary", null, h("span", null, title, h("span", { class: `badge ${doneCount === total ? "ok" : ""}` }, `${doneCount}/${total}`)));
    det.appendChild(sum);
    if (note) det.appendChild(h("p", { class: "muted small", style: { marginTop: ".5rem" } }, note));
    for (const it of items) {
      const cb = h("input", { type: "checkbox", checked: !!ticked[it.id] });
      const label = h("label", { class: "check" + (ticked[it.id] ? " done" : "") }, cb, h("span", null, h("span", { class: "text" }, it.text), it.sub ? h("div", { class: "sub" }, it.sub) : null));
      cb.addEventListener("change", () => {
        this.checklist[blockId] = { ...(this.checklist[blockId] || {}), [it.id]: cb.checked };
        label.classList.toggle("done", cb.checked);
        const dc = items.filter((i) => this.checklist[blockId][i.id]).length;
        const b = sum.querySelector(".badge"); b.textContent = `${dc}/${total}`; b.className = `badge ${dc === total ? "ok" : ""}`;
        this.saveWorkoutDebounced({ checklist: this.checklist });
        this.refreshCache();
      });
      det.appendChild(label);
    }
    det.appendChild(this.noteField(blockId, `Note on the ${(BLOCK_NAMES[blockId] || title.replace(/\s*\(.*\)$/, "")).toLowerCase()}`));
    return det;
  }

  exerciseBlock(e) {
    const ex = exerciseFor(e.key);
    const rows = this.rows[e.key] || (this.rows[e.key] = []);
    const last = this.data.last[e.key];
    const block = h("div", { class: "card exercise", dataset: { key: e.key } });
    const target = e.sets ? `${e.sets} × ${e.reps}${e.sets !== e.plannedSets && e.plannedSets ? ` (deload, normally ${e.plannedSets})` : ""}` : "";
    const head = h("div", { class: "ex-head" },
      h("div", null,
        h("div", { class: "ex-name" }, ex.name),
        h("div", { class: "ex-target" }, [target, e.note, ex.kgHint ? `kg = ${ex.kgHint}` : null].filter(Boolean).join(" · "))),
      h("button", { class: "btn more", "aria-label": "Exercise options", onClick: () => this.exerciseMenu(e) }, "···"));
    block.appendChild(head);
    if (last) block.appendChild(h("div", { class: "ex-last" }, `Last time (${fmtShort(last.date)}): ${describeSets(ex, last.sets)}`, last.note ? h("div", { class: "ex-last-note" }, `“${last.note}”`) : null));
    const hint = progressionHint(ex, e, last);
    if (hint) block.appendChild(h("div", { class: "hint" }, hint));

    const fields = ex.fields.slice(0, 2);
    const one = fields.length === 1 ? " one-field" : "";
    block.appendChild(h("div", { class: "set-grid set-head" + one }, h("span", null, "Set"), fields.map((f) => h("span", null, FIELD_META[f].label + (f === "kg" && ex.kgOptional ? " (opt.)" : ""))), h("span", null, "")));
    const rowsEl = h("div", { class: "set-rows" });
    rows.forEach((row, i) => rowsEl.appendChild(this.setRow(e, ex, row, i, fields)));
    block.appendChild(rowsEl);
    const note = this.noteField(e.key, `Note on ${ex.short || ex.name}`);
    block.appendChild(h("div", { class: "set-foot" },
      h("div", { class: "row", style: { gap: ".2rem" } },
        h("button", { class: "btn text", onClick: () => { rows.push({ client_id: uuid(), set_index: rows.length, kg: null, reps: null, seconds: null, meters: null, saved: false }); rowsEl.appendChild(this.setRow(e, ex, rows[rows.length - 1], rows.length - 1, fields)); } }, "+ Add set"),
        note.querySelector(".note-toggle")),
      h("button", { class: "btn text muted", onClick: async () => {
        const row = rows[rows.length - 1];
        if (!row) return;
        if ((row.saved || row.touched) && !confirm("Remove the last logged set?")) return;
        await this.deleteSet(e.key, row);
        rowsEl.lastChild && rowsEl.removeChild(rowsEl.lastChild);
      } }, "Remove set")));
    block.appendChild(note);
    return block;
  }

  placeholderFor(ex, e, rows, i, field) {
    const last = this.data.last[e.key];
    const prev = i > 0 ? rows[i - 1] : null;
    if (prev && prev[field] != null && prev[field] !== "") return prev[field];
    if (last) {
      const ls = last.sets[Math.min(i, last.sets.length - 1)];
      const col = FIELD_TO_COL[field];
      if (ls && ls[col] != null) return ls[col];
    }
    if (field === "kg" && e.startKg) return e.startKg;
    if (field === "reps" && e.repsMin) return e.repsMin;
    if (field === "seconds" && e.seconds) return e.seconds;
    if (field === "meters" && e.meters) return e.meters;
    return "";
  }

  setRow(e, ex, row, i, fields) {
    const rows = this.rows[e.key];
    const tick = h("button", { class: "tick" + (row.saved ? " done" : ""), "aria-label": "Log set" }, "✓");
    const inputs = {};
    const save = debounce(() => this.saveSet(e.key, row).then(() => tick.classList.toggle("done", row.saved)), 700);
    const rowEl = h("div", { class: "set-grid set-row" + (fields.length === 1 ? " one-field" : "") }, h("span", { class: "set-no" }, String(i + 1)));
    for (const f of fields) {
      const inp = h("input", { ...FIELD_META[f].attrs, value: row[f] ?? "", placeholder: String(this.placeholderFor(ex, e, rows, i, f)), class: row[f] != null ? "filled" : "", "aria-label": FIELD_META[f].label });
      inp.addEventListener("input", () => { row[f] = inp.value === "" ? null : Number(inp.value); inp.classList.toggle("filled", row[f] != null); save(); });
      inp.addEventListener("focus", () => inp.select());
      inputs[f] = inp;
      const cell = h("div", { class: "cell" + (f === "seconds" ? " has-count" : "") }, inp);
      if (f === "seconds") {
        // Countdown: runs from the typed value or the placeholder, then logs the set. Tap again to stop early.
        const go = h("button", { class: "count-btn", "aria-label": "Start countdown", title: "Start countdown" }, "▶");
        go.addEventListener("click", () => {
          if (this.countdown && this.countdown.row === row) { this.countdown.stop(); return; }
          if (this.countdown) this.countdown.stop(true);
          const target = Number(inp.value || this.placeholderFor(ex, e, rows, i, "seconds")) || 0;
          if (!target) { toast("Type the seconds first"); return; }
          this.runCountdown({ row, target, inp, go, label: ex.short || ex.name, onDone: () => { row.seconds = target; inp.value = String(target); inp.classList.add("filled"); complete(); } });
        });
        cell.appendChild(go);
      } else cell.appendChild(h("span", { class: "unit" }, FIELD_META[f].label));
      rowEl.appendChild(cell);
    }
    // Empty fields take the placeholder (last time or previous set), then the set is saved.
    const complete = () => {
      for (const f of fields) {
        if (row[f] == null || row[f] === "") {
          const ph = this.placeholderFor(ex, e, rows, i, f);
          if (ph !== "" && !(f === "kg" && ex.kgOptional && ph === "")) { row[f] = Number(ph); inputs[f].value = ph; inputs[f].classList.add("filled"); }
        }
      }
      if (!fields.some((f) => row[f] != null && row[f] !== "")) { toast("Type the numbers first"); return; }
      row.saved = true;
      save.flush();
      tick.classList.add("done");
      // Update placeholders of the next row.
      const next = rowEl.nextSibling;
      if (next) next.querySelectorAll("input").forEach((inp, idx) => { const f = fields[idx]; if (!inp.value) inp.placeholder = String(this.placeholderFor(ex, e, rows, i + 1, f)); });
    };
    tick.addEventListener("click", () => {
      if (row.saved) {
        // Untick: keep the numbers, mark the set as not done.
        row.saved = false;
        tick.classList.remove("done");
        save.flush();
        this.updateStatusBadge();
        return;
      }
      complete();
    });
    rowEl.appendChild(tick);
    return rowEl;
  }

  // Set countdown shown in the input and in the timer bar. Buzzes and beeps at zero, then logs the set.
  runCountdown({ row, target, inp, go, label, onDone }) {
    const audio = makeAudio();
    const startedAt = Date.now();
    const endsAt = startedAt + target * 1000;
    inp.readOnly = true; inp.classList.add("counting"); go.textContent = "■"; go.classList.add("running");
    let lastShown = null;
    const tickFn = () => {
      const left = Math.max(0, Math.ceil((endsAt - Date.now()) / 1000));
      if (left !== lastShown) { inp.value = String(left); lastShown = left; if (left <= 3 && left > 0 && audio) audio.beep(880, 0.08); }
      if (left <= 0) { finish(); }
    };
    const iv = setInterval(tickFn, 200);
    const cleanup = () => { clearInterval(iv); inp.readOnly = false; inp.classList.remove("counting"); go.textContent = "▶"; go.classList.remove("running"); this.countdown = null; };
    const finish = () => { cleanup(); buzz(); if (audio) { audio.beep(1320, 0.25); setTimeout(() => audio.beep(1320, 0.35), 300); } onDone(); };
    const stop = (silent) => { cleanup(); if (silent) { inp.value = row.seconds ?? ""; return; } const elapsed = Math.round((Date.now() - startedAt) / 1000); row.seconds = elapsed; inp.value = String(elapsed); inp.classList.add("filled"); toast(`Stopped at ${elapsed} s`); };
    this.countdown = { row, label, endsAt, stop };
    tickFn();
  }

  // Fixed bar above the tabs: workout time, rest since the last tick, and a running countdown.
  timerBar() {
    this.container.classList.add("with-bar");
    return h("div", { class: "timer-bar", dataset: { timer: "1" } },
      h("div", { class: "tb-item" }, h("span", { class: "tb-label" }, "Workout"), h("span", { class: "tb-value", dataset: { tbWorkout: "1" } }, "0:00")),
      h("div", { class: "tb-item" }, h("span", { class: "tb-label" }, "Rest"), h("span", { class: "tb-value", dataset: { tbRest: "1" } }, "–")),
      h("div", { class: "tb-item tb-count", dataset: { tbCount: "1" }, hidden: true }, h("span", { class: "tb-label", dataset: { tbCountLabel: "1" } }, ""), h("span", { class: "tb-value", dataset: { tbCountValue: "1" } }, "")));
  }

  exerciseMenu(e) {
    const ex = exerciseFor(e.key);
    const list = h("div", { class: "action-list" });
    list.appendChild(h("div", { class: "list-item", onClick: () => { close(); this.pickExercise((key) => this.replaceExercise(e, key), `Replace ${ex.name} with`); } }, h("div", null, h("div", { class: "title" }, "Replace with another exercise")), h("span", { class: "chev" }, "›")));
    list.appendChild(h("div", { class: "list-item danger", onClick: async () => {
      if (!confirm(`Remove ${ex.name} from this session?`)) return;
      close();
      this.plan = this.plan.filter((p) => p !== e);
      await this.saveWorkout({ plan: this.plan });
      this.render();
    } }, h("div", null, h("div", { class: "title" }, "Remove from this session")), h("span", { class: "chev" }, "›")));
    const content = h("div", null, list, h("p", { class: "muted small", style: { marginTop: ".8rem" } }, "Changes only affect this session. The plan itself stays the same."));
    const close = modal({ title: ex.name, content, actions: [{ label: "Cancel", class: "ghost" }] });
  }

  async replaceExercise(e, newKey) {
    const idx = this.plan.indexOf(e);
    if (idx < 0) return;
    this.plan[idx] = { ...e, key: newKey, note: e.note, startKg: undefined, replaces: e.key };
    this.initRows();
    await this.saveWorkout({ plan: this.plan });
    this.render();
  }

  addExerciseDialog() {
    this.pickExercise(async (key) => {
      const ex = exerciseFor(key);
      this.plan.push({ key, sets: 3, reps: ex.fields.includes("seconds") ? "30 s" : "8 to 10", repsMin: 8, repsMax: 10, added: true });
      this.initRows();
      await this.saveWorkout({ plan: this.plan });
      this.render();
    }, "Add an exercise");
  }

  pickExercise(onPick, title) {
    const all = Object.entries(PROGRAM.exercises).filter(([, v]) => !v.hidden).map(([key, v]) => ({ key, ...v }));
    const search = h("input", { type: "text", placeholder: "Search, or type a new name", autofocus: true });
    const list = h("div", { class: "search-list action-list" });
    const draw = () => {
      clear(list);
      const q = search.value.trim().toLowerCase();
      const matches = all.filter((x) => !q || x.name.toLowerCase().includes(q) || x.group.includes(q));
      for (const x of matches.slice(0, 40)) list.appendChild(h("div", { class: "list-item", onClick: () => { close(); onPick(x.key); } }, h("div", null, h("div", { class: "title" }, x.name), h("div", { class: "sub" }, `${x.group} · ${x.fields.join(" + ")}`)), h("span", { class: "chev" }, "›")));
      if (q && !matches.some((x) => x.name.toLowerCase() === q)) {
        const key = "custom:" + q.replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "");
        list.appendChild(h("div", { class: "list-item", onClick: () => { close(); onPick(key); } }, h("div", null, h("div", { class: "title" }, `Add "${search.value.trim()}"`), h("div", { class: "sub" }, "custom exercise, kg + reps")), h("span", { class: "chev" }, "›")));
      }
    };
    search.addEventListener("input", draw);
    draw();
    const close = modal({ title, content: h("div", null, search, list), actions: [{ label: "Cancel", class: "ghost" }] });
    setTimeout(() => search.focus(), 50);
  }

  // ----- run / other -----
  runBody(card) {
    const t = this.template;
    const w = this.workout || {};
    if (t.detail) card.appendChild(h("p", { style: { marginTop: ".4rem" } }, t.detail));
    if (t.intervals) {
      const iv = t.intervals;
      card.appendChild(h("div", { class: "banner info" }, `10 min easy jog, then ${iv.reps} × ${iv.workSec / 60} min hard with ${iv.restSec / 60} min easy between, then a few minutes easy. Pace steady across every rep.`));
    }
    if (t.timeTrial) {
      const target = Number(state.settings.five_k_target_sec) || PROGRAM.running.fiveKTargetSec;
      card.appendChild(h("div", { class: "banner info" }, `Target by week 16: under ${fmtTime(target)} (${fmtPace(target / 5)}). PB ${fmtTime(PROGRAM.running.fiveKPbSec)}. Under 25:00 today means the target moves to 22:00.`));
    }
    const dist = h("input", { type: "number", inputmode: "decimal", step: "0.01", min: "0", placeholder: t.timeTrial ? "5.00" : "km", value: w.distance_km ?? "" });
    const time = h("input", { type: "text", inputmode: "numeric", placeholder: "mm:ss", value: w.time_sec ? fmtTime(w.time_sec) : "" });
    const hr = h("input", { type: "number", inputmode: "numeric", placeholder: "bpm", value: w.avg_hr ?? "" });
    const pace = h("div", { class: "muted small", style: { minHeight: "1.2em", marginTop: ".4rem" } });
    const updatePace = () => {
      const d = Number(dist.value), s = parseTime(time.value);
      pace.textContent = d > 0 && s ? `Pace ${fmtPace(s / d)}` : "";
    };
    updatePace();
    const saveFields = debounce(async () => {
      const body = { distance_km: dist.value === "" ? null : Number(dist.value), time_sec: parseTime(time.value), avg_hr: hr.value === "" ? null : Number(hr.value) };
      await this.saveWorkout(body);
      updatePace();
      this.updateStatusBadge();
    }, 700);
    [dist, time, hr].forEach((i) => i.addEventListener("input", () => { updatePace(); saveFields(); }));
    card.appendChild(h("div", { class: "inline-fields", style: { marginTop: ".6rem" } },
      h("label", { class: "field" }, h("span", null, "Distance (km)"), dist),
      h("label", { class: "field" }, h("span", null, "Time"), time),
      h("label", { class: "field" }, h("span", null, "Avg heart rate"), hr)));
    card.appendChild(pace);
    card.appendChild(this.garminBlock());
  }

  garminBlock() {
    const acts = (this.workout && this.workout.activities) || [];
    const wrap = h("div", { style: { marginTop: ".4rem" } });
    wrap.appendChild(h("div", { class: "section-title" }, "Garmin"));
    for (const a of acts) {
      wrap.appendChild(h("div", { class: "list-item", style: { cursor: "pointer" }, onClick: () => showActivity(a.id) },
        h("div", null,
          h("div", { class: "title" }, `${a.distance_m ? (a.distance_m / 1000).toFixed(2) + " km" : ""} ${a.duration_s ? "· " + fmtTime(a.duration_s) : ""} ${a.avg_pace_s_per_km ? "· " + fmtPace(a.avg_pace_s_per_km) : ""}`),
          h("div", { class: "sub" }, [a.avg_hr ? `avg HR ${a.avg_hr}` : null, a.max_hr ? `max ${a.max_hr}` : null, a.best_5k_s ? `best 5 km ${fmtTime(a.best_5k_s)}` : null, a.elevation_gain_m != null ? `${Math.round(a.elevation_gain_m)} m up` : null].filter(Boolean).join(" · "))),
        h("span", { class: "chev" }, "›")));
    }
    const file = h("input", { type: "file", accept: ".fit,.tcx,.gpx,.csv,application/octet-stream", multiple: true });
    file.addEventListener("change", async () => {
      if (!file.files.length) return;
      const fd = new FormData();
      for (const f of file.files) fd.append("file", f);
      fd.append("date", this.date);
      fd.append("source", "garmin");
      fd.append("tz_offset_min", String(new Date().getTimezoneOffset()));
      try {
        if (!this.workout || !this.workout.id) await this.saveWorkout({});
        if (this.workout && this.workout.id) fd.append("workout_id", String(this.workout.id));
        toast("Uploading");
        const r = await api.upload(fd);
        const failed = r.uploads.filter((u) => u.status === "failed");
        toast(failed.length ? `Stored, but could not parse: ${failed[0].error}` : "Garmin file attached", failed.length > 0);
        await this.reload();
      } catch (e) { toast(e.message, true); }
    });
    wrap.appendChild(h("label", { class: "field", style: { marginBottom: 0 } }, h("span", null, acts.length ? "Attach another file (FIT, TCX, GPX or CSV)" : "Attach the Garmin file for this run (FIT, TCX, GPX or CSV)"), file));
    return wrap;
  }

  // ----- rest -----
  restBody(card) {
    const t = this.template;
    if (t.detail) card.appendChild(h("p", { style: { marginTop: ".4rem" } }, t.detail));
    card.appendChild(h("p", { class: "muted small", style: { margin: 0 } }, PROGRAM.stepsNote));
  }

  kneeCard(optional = false) {
    const card = h("div", { class: "card" });
    card.appendChild(h("div", { class: "card-title" }, h("h3", null, PROGRAM.kneeRoutine.title), h("span", { class: "badge" }, `${PROGRAM.kneeRoutine.minutes} min`)));
    card.appendChild(h("p", { class: "muted small" }, PROGRAM.kneeRoutine.note + (optional ? " Optional after the run." : "")));
    card.appendChild(this.checklistBlock("knee", "Routine", PROGRAM.kneeRoutine.items, null, false));
    return card;
  }

  // ----- tests -----
  testsCard() {
    const card = h("div", { class: "card" });
    card.appendChild(h("div", { class: "card-title" }, h("h3", null, `Test week ${this.day.week}`), h("span", { class: "badge warn" }, "Fill in during the week")));
    card.appendChild(h("p", { class: "muted small" }, "5 km on Tuesday, jumps and shuttle after a warm-up, 3RMs on the lifting days. One leg hopping less than 90% of the other is the warning sign."));
    const byKey = {};
    for (const t of this.data.tests || []) byKey[t.test_key] = t;
    const grid = h("div", { class: "inline-fields" });
    for (const def of PROGRAM.tests) {
      const existing = byKey[def.key];
      const inp = h("input", def.input === "time" ? { type: "text", inputmode: "numeric", placeholder: "mm:ss", value: existing ? fmtTime(existing.value) : "" } : { type: "number", inputmode: "decimal", step: def.step || "1", placeholder: def.unit, value: existing ? existing.value : "" });
      inp.addEventListener("change", async () => {
        const value = def.input === "time" ? parseTime(inp.value) : inp.value === "" ? null : Number(inp.value);
        const date = existing ? existing.date : this.date;
        const r = await queuedWrite("PUT", "/api/tests", { date, test_key: def.key, value }, `test:${date}:${def.key}`);
        if (r.ok) toast("Test saved");
      });
      grid.appendChild(h("label", { class: "field" }, h("span", null, `${def.name} (${def.unit})`), inp));
    }
    card.appendChild(grid);
    return card;
  }

  // ----- notes, finish, secondary actions -----
  finishCard() {
    const st = this.workout ? this.workout.status : "in_progress";
    const card = h("div", { class: "card" });
    const ta = h("textarea", { placeholder: "How it felt, knees, anything for later" });
    ta.value = (this.workout && this.workout.notes) || "";
    ta.addEventListener("input", () => this.saveWorkoutDebounced({ notes: ta.value }));
    card.appendChild(h("label", { class: "field" }, h("span", null, "Notes"), ta));
    if (st !== "done") card.appendChild(h("button", { class: "btn primary wide", onClick: () => this.finishDialog() }, this.template.kind === "rest" ? "Mark day done" : this.template.kind === "lift" ? "Finish workout" : "Finish session"));
    else if (this.template.kind === "lift") card.appendChild(h("button", { class: "btn primary wide", onClick: () => { this.editing = false; this.render(); window.scrollTo({ top: 0 }); } }, "Done editing"));
    else card.appendChild(h("button", { class: "btn wide", onClick: async () => { await this.saveWorkout({ status: "in_progress" }); this.render(); } }, "Reopen session"));
    if (this.template.kind !== "lift") card.appendChild(h("div", { class: "timer", dataset: { timer: "1" }, style: { marginTop: ".6rem", textAlign: "center" } }));
    return card;
  }

  actionsCard() {
    const st = this.workout ? this.workout.status : "in_progress";
    const list = h("div", { class: "card action-list" });
    const item = (title, sub, cls, fn) => list.appendChild(h("div", { class: `list-item ${cls || ""}`, onClick: fn }, h("div", null, h("div", { class: "title" }, title), sub ? h("div", { class: "sub" }, sub) : null), h("span", { class: "chev" }, "›")));
    item("Move or change this session", "Swap with another day, or do a different session today", "accent", () => this.changeDialog());
    if (st !== "skipped") item("Skip this session", null, "", async () => { await this.saveWorkout({ status: "skipped" }); toast("Marked as skipped"); this.render(); });
    else item("Unskip", null, "", async () => { await this.saveWorkout({ status: "in_progress" }); this.render(); });
    if (this.workout && this.workout.id) item("Delete this session and its sets", null, "danger", async () => {
      if (!confirm("Delete this session and all its sets?")) return;
      try { await api.del(`/api/workouts/${this.workout.id}`); store.del(`ft_active_${this.date}`); toast("Deleted"); location.reload(); } catch (e) { toast(e.message, true); }
    });
    return list;
  }

  finishDialog() {
    let rpe = this.workout && this.workout.rpe ? this.workout.rpe : null;
    const sets = this.doneSets();
    const volume = sets.reduce((s, x) => s + (x.weight_kg || 0) * (x.reps || 0), 0);
    const elapsed = this.workout && this.workout.started_at && this.workout.status !== "done" ? minutesBetween(this.workout.started_at, new Date().toISOString()) : null;
    const rpeRow = h("div", { class: "rpe" });
    for (let i = 1; i <= 10; i++) rpeRow.appendChild(h("button", { class: rpe === i ? "active" : "", onClick: (ev) => { rpe = i; rpeRow.querySelectorAll("button").forEach((b) => b.classList.toggle("active", b === ev.currentTarget)); } }, String(i)));
    const content = h("div", null,
      this.template.kind === "lift" ? h("p", { class: "muted" }, `${sets.length} sets logged${volume ? `, ${Math.round(volume)} kg total volume` : ""}${elapsed ? `, ${elapsed} min` : ""}.`) : null,
      h("div", { class: "field" }, h("span", null, "How hard was it? (1 easy, 10 all out)"), rpeRow));
    modal({
      title: this.template.kind === "lift" ? "Finish workout" : "Finish session", content,
      actions: [
        { label: "Cancel", class: "ghost" },
        { label: "Done", class: "primary", onClick: async () => {
          const patch = { status: "done" };
          if (rpe) patch.rpe = rpe;
          if (this.workout && this.workout.started_at && this.workout.status !== "done") {
            patch.finished_at = new Date().toISOString();
            patch.duration_min = minutesBetween(this.workout.started_at, patch.finished_at);
          }
          this.editing = false;
          await this.saveWorkout(patch);
          if (this.template.timeTrial && this.workout && this.workout.time_sec && this.workout.distance_km >= 4.9 && this.workout.distance_km <= 5.3) {
            await queuedWrite("PUT", "/api/tests", { date: this.date, test_key: "five_k_sec", value: this.workout.time_sec }, `test:${this.date}:five_k_sec`);
          }
          toast("Session done");
          this.render();
        } },
      ],
    });
  }

  // Move this day's session to another day (swap), or change what is done today.
  async changeDialog() {
    const monday = mondayOf(this.date);
    let sched = null;
    try { sched = await api.get(`/api/schedule?from=${monday}&to=${addDays(monday, 13)}`); } catch (e) { toast(e.message, true); return; }
    const content = h("div", null);
    content.appendChild(h("p", { class: "muted small" }, "Days are interchangeable. Avoid two lifting days back to back, and keep jump days 48 hours apart."));
    content.appendChild(h("div", { class: "section-title", style: { margin: ".9rem 0 .2rem" } }, "Swap with another day"));
    const days = h("div", { class: "action-list" });
    for (const d of sched.days) {
      if (d.date === this.date) continue;
      const w = d.workouts.find((x) => x.template_key === d.templateKey);
      days.appendChild(h("div", { class: "list-item", onClick: () => {
        close();
        modal({ title: "Swap these two days?", content: h("div", null, h("p", null, h("b", null, fmtDay(this.date)), ` becomes ${d.name}.`), h("p", null, h("b", null, fmtDay(d.date)), ` becomes ${this.day.template.name}.`)),
          actions: [{ label: "Cancel", class: "ghost" }, { label: "Swap", class: "primary", onClick: async () => {
            try {
              await api.post("/api/schedule/swap", { a: this.date, b: d.date });
              store.del(`ft_active_${this.date}`); store.del(`ft_active_${d.date}`); store.del(`ft_day_${d.date}`);
              toast("Swapped");
            } catch (e) { toast(e.message, true); }
            this.reload();
          } }] });
      } },
        h("div", null, h("div", { class: `title` }, `${fmtDay(d.date)}`, d.date === this.today ? h("span", { class: "badge accent", style: { marginLeft: ".4rem" } }, "today") : null), h("div", { class: `sub kind-${d.kind}` }, [d.name, w ? w.status.replace("_", " ") : null, d.moved ? "moved" : null].filter(Boolean).join(" · "))),
        h("span", { class: "chev" }, "›")));
    }
    content.appendChild(days);
    content.appendChild(h("div", { class: "section-title", style: { margin: "1rem 0 .2rem" } }, "Or do a different session today"));
    const list = h("div", { class: "action-list" });
    for (const k of PICKABLE) {
      const t = PROGRAM.templates[k];
      list.appendChild(h("div", { class: "list-item", onClick: async () => {
        close();
        if (k === this.day.templateKey) return;
        try { await api.put(`/api/schedule/${this.date}`, { template_key: k }); store.del(`ft_active_${this.date}`); toast("Session changed"); } catch (e) { toast(e.message, true); }
        this.reload();
      } }, h("div", null, h("div", { class: `title kind-${t.kind}` }, t.name, k === this.day.defaultTemplateKey ? h("span", { class: "badge", style: { marginLeft: ".4rem" } }, "planned") : null, k === this.day.templateKey && this.day.moved ? h("span", { class: "badge accent", style: { marginLeft: ".4rem" } }, "current") : null), h("div", { class: "sub" }, t.subtitle)), h("span", { class: "chev" }, "›")));
    }
    content.appendChild(list);
    if (this.day.moved) content.appendChild(h("button", { class: "btn tinted wide", style: { marginTop: ".9rem" }, onClick: async () => {
      close();
      try { await api.put(`/api/schedule/${this.date}`, { template_key: null }); store.del(`ft_active_${this.date}`); toast("Back to the plan"); } catch (e) { toast(e.message, true); }
      this.reload();
    } }, `Back to the plan: ${templateFor(this.day.defaultTemplateKey).name}`));
    const close = modal({ title: "Move or change", content, actions: [{ label: "Cancel", class: "ghost" }] });
  }

  otherWorkoutCard(w) {
    const t = templateFor(w.template_key);
    return h("div", { class: "card", style: { cursor: "pointer" }, onClick: () => { store.set(`ft_active_${this.date}`, w.template_key); this.destroy(); new DayView(this.container, this.date, this.data, this.offline).render(); } },
      h("div", { class: "card-title" }, h("h3", { class: `kind-${t.kind}` }, t.name), h("span", { class: `badge ${w.status === "done" ? "ok" : w.status === "skipped" ? "danger" : ""}` }, w.status.replace("_", " "))),
      h("div", { class: "muted small" }, `${(w.sets || []).length} sets${w.distance_km ? ` · ${w.distance_km} km` : ""}${w.time_sec ? ` · ${fmtTime(w.time_sec)}` : ""}. Tap to open.`));
  }

  startTimer() {
    if (this.timer) clearInterval(this.timer);
    const update = () => {
      const el = this.container.querySelector("[data-timer]");
      if (!el) return;
      const w = this.workout;
      const workoutText = w && w.started_at && w.status !== "done" ? secondsToHms(Math.max(0, (Date.now() - parseWhen(w.started_at)) / 1000)) : null;
      const restText = this.lastTick ? secondsToHms(Math.round((Date.now() - this.lastTick) / 1000)) : null;
      if (el.classList.contains("timer-bar")) {
        el.querySelector("[data-tb-workout]").textContent = workoutText || (w && w.status === "done" ? "done" : "0:00");
        el.querySelector("[data-tb-rest]").textContent = restText || "–";
        const c = el.querySelector("[data-tb-count]");
        if (this.countdown) { c.hidden = false; el.querySelector("[data-tb-count-label]").textContent = this.countdown.label; el.querySelector("[data-tb-count-value]").textContent = secondsToHms(Math.max(0, Math.ceil((this.countdown.endsAt - Date.now()) / 1000))); }
        else c.hidden = true;
        return;
      }
      el.textContent = [workoutText ? `Workout ${workoutText}` : null, restText ? `Rest ${restText}` : null].filter(Boolean).join(" · ");
    };
    this.timer = setInterval(update, 500);
    update();
  }
}

const BLOCK_NAMES = { warmup: "Warm-up", jumps: "Jumps", finisher: "Finisher" };
function isDone(s) { return s.done == null ? true : Number(s.done) !== 0; }
function buzz() { try { if (navigator.vibrate) navigator.vibrate([200, 100, 200, 100, 400]); } catch {} }
// Short beeps through WebAudio. Created inside the tap handler so iOS allows it.
function makeAudio() {
  try {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    if (!Ctx) return null;
    const ctx = new Ctx();
    if (ctx.state === "suspended") ctx.resume();
    return { beep(freq, dur) { try { const o = ctx.createOscillator(), g = ctx.createGain(); o.frequency.value = freq; o.type = "sine"; g.gain.value = 0.15; o.connect(g); g.connect(ctx.destination); o.start(); o.stop(ctx.currentTime + dur); } catch {} } };
  } catch { return null; }
}
function parseWhen(v) {
  if (!v) return NaN;
  const d = new Date(/[TZ]/.test(v) ? v : v.replace(" ", "T") + "Z");
  return d.getTime();
}
function minutesBetween(a, b) {
  const x = parseWhen(a), y = parseWhen(b);
  if (isNaN(x) || isNaN(y) || y < x) return null;
  return Math.max(1, Math.round((y - x) / 60000));
}

function buildPlanFor(templateKey, week) {
  const t = templateFor(templateKey);
  if (!t.exercises) return [];
  const deload = week >= 1 && week % PROGRAM.deloadEveryWeeks === 0;
  return t.exercises.map((e) => ({ ...e, sets: deload ? Math.max(1, Math.ceil(e.sets / 2)) : e.sets, plannedSets: e.sets }));
}

export function describeSets(ex, sets) {
  if (!sets || !sets.length) return "";
  if (ex.fields[0] === "reps") return sets.map((s) => `${s.reps ?? 0}${s.weight_kg ? ` (+${fmtKg(s.weight_kg)} kg)` : ""}`).join(", ");
  if (ex.fields.includes("kg") && ex.fields.includes("reps")) {
    const w = sets.map((s) => s.weight_kg);
    const sameW = w.every((x) => x === w[0]);
    return sameW ? `${fmtKg(w[0]) || 0} kg × ${sets.map((s) => s.reps ?? 0).join(", ")}` : sets.map((s) => `${fmtKg(s.weight_kg) || 0}×${s.reps ?? 0}`).join(", ");
  }
  if (ex.fields.includes("seconds")) return sets.map((s) => `${s.seconds ?? 0} s`).join(", ");
  if (ex.fields.includes("meters")) return sets.map((s) => `${fmtKg(s.weight_kg) || 0} kg × ${s.distance_m ?? 0} m`).join(", ");
  return "";
}

function progressionHint(ex, e, last) {
  if (!last) return e.startKg ? `First session: start around ${e.startKg} kg.` : null;
  if (!(ex.fields.includes("kg") && ex.fields.includes("reps")) || !e.repsMax) return null;
  const sets = last.sets.filter((s) => s.reps != null);
  if (sets.length < Math.max(1, (e.plannedSets || e.sets) - 0)) return null;
  const topW = Math.max(...sets.map((s) => s.weight_kg || 0));
  const allTop = sets.every((s) => (s.reps || 0) >= e.repsMax && (s.weight_kg || 0) >= topW);
  if (allTop && topW > 0) return `Last time you hit ${e.repsMax} on every set. Try ${fmtKg(topW + (ex.increment || 2.5))} kg today.`;
  return null;
}

export async function showActivity(id) {
  let a;
  try { a = await api.get(`/api/activities/${id}`); } catch (e) { toast(e.message, true); return; }
  const rows = (a.splits && a.splits.length ? a.splits : (a.laps || []).map((l) => ({ km: l.index, seconds: l.duration_s, pace_s_per_km: l.pace_s_per_km, avg_hr: l.avg_hr, distance_m: l.distance_m })));
  const table = h("table", null,
    h("thead", null, h("tr", null, h("th", null, a.splits && a.splits.length ? "km" : "lap"), h("th", { class: "num" }, "time"), h("th", { class: "num" }, "pace"), h("th", { class: "num" }, "HR"))),
    h("tbody", null, rows.map((r) => h("tr", null, h("td", null, `${r.km}${r.partial ? ` (${(r.distance_m / 1000).toFixed(2)} km)` : ""}`), h("td", { class: "num" }, secondsToHms(r.seconds)), h("td", { class: "num" }, r.pace_s_per_km ? fmtPace(r.pace_s_per_km) : ""), h("td", { class: "num" }, r.avg_hr ?? "")))));
  const zones = a.hr_zones && a.hr_zones.seconds ? h("div", { class: "small muted", style: { marginTop: ".6rem" } }, "Time in HR zones (max " + a.hr_zones.max_hr_used + "): " + a.hr_zones.seconds.map((s, i) => `Z${i + 1} ${secondsToHms(s)}`).join(" · ")) : null;
  const canvas = h("canvas");
  const content = h("div", null,
    h("p", { class: "muted small" }, [a.start_time ? new Date(a.start_time).toLocaleString() : null, a.sport, a.name, a.calories ? `${Math.round(a.calories)} kcal` : null, a.avg_cadence ? `${a.avg_cadence} spm` : null].filter(Boolean).join(" · ")),
    h("div", { class: "tiles" },
      tile("Distance", a.distance_m ? (a.distance_m / 1000).toFixed(2) + " km" : ""), tile("Time", fmtTime(a.duration_s)), tile("Pace", a.avg_pace_s_per_km ? fmtPace(a.avg_pace_s_per_km) : ""), tile("Avg HR", a.avg_hr ? `${a.avg_hr} (max ${a.max_hr || "?"})` : "")),
    a.track && a.track.length > 5 ? h("div", { class: "chart-box", style: { height: "200px" } }, canvas) : null,
    h("div", { class: "table-wrap" }, table), zones);
  modal({ title: "Garmin activity", content, actions: [{ label: "Close", class: "ghost" }] });
  if (a.track && a.track.length > 5) {
    const { lineChart, dataset } = await import("../charts.js");
    const labels = a.track.map((p) => (p.d).toFixed(1));
    lineChart(canvas, { labels, yReverse: false, datasets: [
      dataset("Heart rate", a.track.map((p) => p.hr), 1, { pointRadius: 0, yAxisID: "y" }),
    ], xLabels: (v) => v + " km" });
  }
}
function tile(label, value) { return h("div", { class: "tile", style: { background: "var(--fill-2)" } }, h("div", { class: "label" }, label), h("div", { class: "value", style: { fontSize: "1.05rem" } }, value || "–")); }
