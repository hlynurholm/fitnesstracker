// The training program. Shared by the Worker (server) and the browser (client).
// Source: "Hlynur's plan to 85 kg" (Oct 2026). Edit here to change the plan; logs are keyed by exercise key, so renaming is safe.

export const PROGRAM = {
  name: "Plan to 85 kg",
  startDateDefault: "2026-10-26", // Monday of week 1
  plannedWeeks: 16,
  body: { startWeightKg: 93, goalWeightKg: 85, heightCm: 188 },
  nutrition: {
    calories: 2450, proteinG: 170, funBudgetWeekKcal: 2500, maintenanceEstimate: 3000, lossPerWeekKg: [0.4, 0.6],
    note: "Maintenance is a formula estimate; the scale gives the real number after 3 weeks. If the weekly average does not move for 2 weeks, cut 200 kcal a day, starting with the fun budget or bread.",
    // A day that lands on the targets. The fun budget (about 350 kcal a day) sits inside the 2,450.
    dayTemplate: [
      { when: "Lunch", what: "Big protein portion (chicken, fish, eggs, mince) + carbs + veg", kcal: 700, protein: 50 },
      { when: "Afternoon", what: "500 g skyr or Greek yogurt + fruit, or a shake + a sandwich with chicken or tuna", kcal: 450, protein: 45 },
      { when: "Dinner", what: "Your usual dinners with a slightly bigger protein portion", kcal: 800, protein: 50 },
      { when: "Evening", what: "Fun budget (daily average)", kcal: 350, protein: 0 },
      { when: "Anywhere", what: "Fruit, milk, a bit of bread", kcal: 150, protein: 25 },
    ],
  },
  running: { fiveKTargetSec: 23 * 60, fiveKPbSec: 25 * 60 + 37, fiveKStretchSec: 22 * 60 },
  stepsNote: "8,000 to 10,000 steps every day. Pram walks count.",
  deloadEveryWeeks: 6,
  testWeeks: [1, 8, 16],

  phases: [
    { id: 1, name: "Tune-up", weekFrom: 1, weekTo: 2, contacts: "about 60 contacts" },
    { id: 2, name: "Power", weekFrom: 3, weekTo: 6, contacts: "about 80 contacts" },
    { id: 3, name: "Reactive", weekFrom: 7, weekTo: 999, contacts: "80 to 100 contacts" },
  ],

  warmup: {
    title: "Warm-up",
    minutes: 10,
    note: "Based on the FIFA 11+ programme, which has good evidence for cutting knee and ACL injuries.",
    items: [
      { id: "bike", text: "Bike: 3 min" },
      { id: "swings", text: "Leg swings, front to back and side to side: 10 per leg each way" },
      { id: "lunge_rot", text: "Walking lunge with rotation: 6 per leg" },
      { id: "band_walk", text: "Banded lateral walk: 2 × 10 steps each way" },
      { id: "bridge", text: "Glute bridge: 10" },
      { id: "balance", text: "Single leg balance, reaching front, side and back: 5 per leg" },
    ],
  },

  jumps: {
    title: "Jumps and agility",
    minutes: "15 to 20",
    note: "Rest 60 to 90 seconds between sets. Count every foot contact. Stop a set the moment landings get loud or your knees cave in.",
    byPhase: {
      1: [
        { id: "pogo", name: "Pogo hops", sets: "2 × 10", note: "Small and quick, stiff ankles" },
        { id: "broad", name: "Broad jump", sets: "3 × 3", note: "Stick each landing" },
        { id: "slh_fwd", name: "Single leg hop forward", sets: "2 × 4 per leg", note: "Hold the landing 2 s" },
        { id: "lat_bound", name: "Lateral bound", sets: "2 × 4 per side", note: "Stick each landing" },
        { id: "split_step", name: "Split step + first step", sets: "3 × 6", note: "80% effort. Small padel ready hop, then one explosive step in any direction and stick. Needs about 2 m" },
      ],
      2: [
        { id: "cmj", name: "Countermovement jump", sets: "3 × 5", note: "Max height, reset between reps" },
        { id: "broad", name: "Broad jump", sets: "3 × 4", note: "Max distance" },
        { id: "slh_fwd", name: "Single leg hop forward", sets: "2 × 4 per leg", note: "Stick 2 s" },
        { id: "slh_side", name: "Single leg hop sideways", sets: "2 × 4 per leg", note: "Stick 2 s" },
        { id: "lat_bound", name: "Lateral bound", sets: "2 × 5 per side", note: "" },
        { id: "split_step", name: "Split step + first step", sets: "4 × 6", note: "Full speed" },
        { id: "tuck", name: "Tuck jump", sets: "3 × 5", note: "Knees to chest, soft landing" },
      ],
      3: [
        { id: "depth", name: "Depth jump from 30 to 45 cm box", sets: "4 × 4", note: "Off the ground as fast as possible" },
        { id: "broad3", name: "Broad jump, 3 in a row", sets: "4 sets", note: "No pause between jumps" },
        { id: "slh3", name: "Single leg hop, 3 in a row", sets: "3 per leg", note: "" },
        { id: "lat_cont", name: "Continuous lateral bound", sets: "3 × 6 per side", note: "" },
        { id: "reaction", name: "Reaction drill", sets: "6 × 5 s", note: "Partner points a direction or drops a ball" },
        { id: "sl_pogo", name: "Single leg pogo hops", sets: "3 × 10 per leg", note: "Quick and stiff, on the spot" },
      ],
    },
    phaseNotes: {
      1: "The tune-up is just two weeks of getting used to jumping again. If it feels easy in week 1, move on to phase 2 (Settings).",
      2: "If your legs feel flat at Monday badminton after the morning jump session, keep the badminton light.",
      3: "Landing quality is still the thing to watch. One leg hopping less than 90% of the other is the warning sign.",
    },
  },

  kneeRoutine: {
    title: "Knee and back routine",
    minutes: 10,
    note: "2 to 3 non-lifting days a week. Fine at home while the baby naps.",
    items: [
      { id: "spanish", text: "Spanish squat or wall sit hold: 4 × 45 s" },
      { id: "stepdown", text: "Slow step-down off a step: 2 × 10 per leg, 3 seconds down" },
      { id: "birddog", text: "Bird dog: 2 × 8 per side" },
      { id: "backext", text: "Back extension: 2 × 12" },
      { id: "hipflexor", text: "Kneeling hip flexor stretch: 2 × 45 s per side" },
    ],
  },

  // fields: which inputs a set row shows. kg = load per hand/bar, reps, seconds, meters.
  exercises: {
    back_squat: { name: "Back squat", fields: ["kg", "reps"], load: "barbell", increment: 2.5, group: "legs", e1rm: true },
    db_bench: { name: "DB bench press", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "push", e1rm: true, kgHint: "per hand" },
    db_single_leg_rdl: { name: "DB single leg RDL", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", perSide: true, e1rm: true, kgHint: "per hand" },
    pull_up: { name: "Pull-ups", fields: ["reps", "kg"], load: "bodyweight", increment: 2.5, group: "pull", kgHint: "added kg", kgOptional: true },
    copenhagen_plank: { name: "Copenhagen side plank", fields: ["seconds"], load: "bodyweight", group: "core", perSide: true },
    suitcase_march: { name: "Suitcase march on the spot", short: "Suitcase march", fields: ["kg", "seconds"], load: "dumbbell", increment: 2, group: "core", perSide: true, kgHint: "one hand" },
    suitcase_carry: { name: "Suitcase carry", fields: ["kg", "meters"], load: "dumbbell", increment: 2, group: "core", perSide: true },

    deadlift: { name: "Deadlift (trap bar if available)", short: "Deadlift", fields: ["kg", "reps"], load: "barbell", increment: 5, group: "legs", e1rm: true },
    db_ohp: { name: "Standing DB overhead press", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "push", e1rm: true, kgHint: "per hand" },
    db_reverse_lunge: { name: "DB reverse lunge", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", perSide: true, e1rm: true, kgHint: "per hand" },
    chest_supported_row: { name: "Chest-supported DB row", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "pull", e1rm: true, kgHint: "per hand" },
    nordic_curl: { name: "Nordic hamstring curl", fields: ["reps"], load: "bodyweight", group: "legs" },
    side_plank: { name: "Side plank", fields: ["seconds"], load: "bodyweight", group: "core", perSide: true },

    bulgarian_split_squat: { name: "DB Bulgarian split squat", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", perSide: true, e1rm: true, kgHint: "per hand" },
    incline_db_press: { name: "Incline DB press", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "push", e1rm: true, kgHint: "per hand" },
    lat_pulldown: { name: "Lat pulldown", fields: ["kg", "reps"], load: "machine", increment: 2.5, group: "pull", e1rm: true },
    hip_thrust: { name: "DB hip thrust or single leg hip thrust", short: "Hip thrust", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", e1rm: true },
    tib_calf: { name: "Tibialis raise + single leg calf raise", short: "Tib + calf raise", fields: ["reps", "kg"], load: "bodyweight", group: "legs", kgOptional: true, kgHint: "optional kg" },
    ab_wheel: { name: "Ab wheel rollout", fields: ["reps"], load: "bodyweight", group: "core" },
    pallof_press: { name: "Pallof press", fields: ["kg", "reps"], load: "cable", increment: 2.5, group: "core", perSide: true },

    // Alternatives and extras that can be swapped in.
    barbell_bench: { name: "Barbell bench press", fields: ["kg", "reps"], load: "barbell", increment: 2.5, group: "push", e1rm: true },
    front_squat: { name: "Front squat", fields: ["kg", "reps"], load: "barbell", increment: 2.5, group: "legs", e1rm: true },
    goblet_squat: { name: "Goblet squat", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", e1rm: true },
    rdl: { name: "Romanian deadlift", fields: ["kg", "reps"], load: "barbell", increment: 2.5, group: "legs", e1rm: true },
    barbell_ohp: { name: "Barbell overhead press", fields: ["kg", "reps"], load: "barbell", increment: 2.5, group: "push", e1rm: true },
    db_row: { name: "One arm DB row", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "pull", perSide: true, e1rm: true },
    cable_row: { name: "Seated cable row", fields: ["kg", "reps"], load: "cable", increment: 2.5, group: "pull", e1rm: true },
    step_up: { name: "DB step-up", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", perSide: true },
    walking_lunge: { name: "DB walking lunge", fields: ["kg", "reps"], load: "dumbbell", increment: 2, group: "legs", perSide: true },
    leg_curl: { name: "Leg curl", fields: ["kg", "reps"], load: "machine", increment: 2.5, group: "legs" },
    dip: { name: "Dips", fields: ["reps", "kg"], load: "bodyweight", group: "push", kgOptional: true, kgHint: "added kg" },
    push_up: { name: "Push-ups", fields: ["reps"], load: "bodyweight", group: "push" },
    plank: { name: "Plank", fields: ["seconds"], load: "bodyweight", group: "core" },
    dead_bug: { name: "Dead bug", fields: ["reps"], load: "bodyweight", group: "core" },
    farmer_carry: { name: "Farmer carry", fields: ["kg", "meters"], load: "dumbbell", increment: 2, group: "core" },
    kb_swing: { name: "Kettlebell swing", fields: ["kg", "reps"], load: "kettlebell", increment: 4, group: "legs" },
    hanging_knee_raise: { name: "Hanging knee raise", fields: ["reps"], load: "bodyweight", group: "core" },
  },

  templates: {
    lift_a: {
      key: "lift_a", name: "Lift A", kind: "lift", subtitle: "Full body + jumps and agility", duration: "75 to 90 min",
      blocks: ["warmup", "jumps", "main"],
      tips: ["Lift earlier in the day than badminton.", "Order: warm-up (10 min), jumps and agility (15 to 20 min), lifting (45 to 60 min)."],
      exercises: [
        { key: "back_squat", sets: 4, reps: "5", repsMin: 5, repsMax: 5, note: "2 reps in reserve. Start around 75 kg", startKg: 75 },
        { key: "db_bench", sets: 4, reps: "6 to 8", repsMin: 6, repsMax: 8 },
        { key: "db_single_leg_rdl", sets: 3, reps: "8 per leg", repsMin: 8, repsMax: 8, note: "Slow, hips square" },
        { key: "pull_up", sets: 4, reps: "as many as you can minus 1", amrap: true, note: "Add weight once you reach 10" },
        { key: "copenhagen_plank", sets: 3, reps: "20 s per side", seconds: 20, note: "Adductors, good for knees and cutting" },
        { key: "suitcase_march", sets: 3, reps: "40 s per side", seconds: 40, note: "For the lower back. Heavy DB in one hand, knees up slowly, don't lean" },
      ],
    },
    lift_b: {
      key: "lift_b", name: "Lift B", kind: "lift", subtitle: "Full body + jumps and agility", duration: "75 to 90 min",
      blocks: ["warmup", "jumps", "main"],
      tips: ["Order: warm-up (10 min), jumps and agility (15 to 20 min), lifting (45 to 60 min)."],
      exercises: [
        { key: "deadlift", sets: 4, reps: "4", repsMin: 4, repsMax: 4, note: "2 reps in reserve. Start around 120 kg", startKg: 120 },
        { key: "db_ohp", sets: 3, reps: "8", repsMin: 8, repsMax: 8 },
        { key: "db_reverse_lunge", sets: 3, reps: "8 per leg", repsMin: 8, repsMax: 8, note: "Trains the exact lunge-holding-the-baby movement" },
        { key: "chest_supported_row", sets: 3, reps: "10", repsMin: 10, repsMax: 10 },
        { key: "nordic_curl", sets: 3, reps: "4 to 6", repsMin: 4, repsMax: 6, note: "Feet under a pad or held by a partner. Lower slowly" },
        { key: "side_plank", sets: 3, reps: "30 s per side", seconds: 30 },
      ],
    },
    lift_c: {
      key: "lift_c", name: "Lift C", kind: "lift", subtitle: "Full body + conditioning finisher", duration: "75 to 90 min",
      blocks: ["warmup", "main", "finisher"],
      tips: ["No jumps today. Warm-up (10 min), lifting (45 to 60 min), then the finisher."],
      exercises: [
        { key: "bulgarian_split_squat", sets: 4, reps: "8 per leg", repsMin: 8, repsMax: 8 },
        { key: "incline_db_press", sets: 3, reps: "8 to 10", repsMin: 8, repsMax: 10 },
        { key: "lat_pulldown", sets: 3, reps: "10 to 12", repsMin: 10, repsMax: 12 },
        { key: "hip_thrust", sets: 3, reps: "10", repsMin: 10, repsMax: 10 },
        { key: "tib_calf", sets: 2, reps: "15 each", repsMin: 15, repsMax: 15, note: "Ankles and knees for jumping" },
        { key: "ab_wheel", sets: 3, reps: "8 to 10", repsMin: 8, repsMax: 10, note: "From the knees. Stop before your lower back sags" },
      ],
      finisher: { title: "Conditioning finisher", text: "8 rounds of 20 s all out and 40 s easy on a bike or rower. Swap in kettlebell swings if those are free.", minutes: 8 },
    },
    intervals_6x2: {
      key: "intervals_6x2", name: "Intervals", kind: "run", subtitle: "6 × 2 min hard, 2 min walk or jog", duration: "30 to 45 min",
      detail: "After a 10 min easy jog, run 6 × 2 min hard with 2 min walk or jog between. Hard means talking is difficult but you can keep the pace steady across every rep.",
      intervals: { reps: 6, workSec: 120, restSec: 120 },
    },
    intervals_5x3: {
      key: "intervals_5x3", name: "Intervals", kind: "run", subtitle: "5 × 3 min hard, 2 min easy jog", duration: "30 to 45 min",
      detail: "After a 10 min easy jog, run 5 × 3 min hard with 2 min easy jog between. Keep the pace steady across every rep.",
      intervals: { reps: 5, workSec: 180, restSec: 120 },
    },
    intervals_4x4: {
      key: "intervals_4x4", name: "Intervals", kind: "run", subtitle: "4 × 4 min hard, 3 min easy jog", duration: "30 to 45 min",
      detail: "After a 10 min easy jog, run the classic Norwegian 4 × 4: 4 min hard, 3 min easy jog, four times. Keep the pace steady across every rep.",
      intervals: { reps: 4, workSec: 240, restSec: 180 },
    },
    time_trial_5k: {
      key: "time_trial_5k", name: "5 km time trial", kind: "run", subtitle: "Timed 5 km, flat out", duration: "30 to 40 min",
      detail: "Warm up 10 min easy, then run 5 km as fast as you can hold evenly. Log the time here. Target by week 16: under 23:00 (4:36 per km). PB: 25:37.",
      timeTrial: true,
    },
    easy_run: {
      key: "easy_run", name: "Easy zone 2 run", kind: "run", subtitle: "30 to 40 min, conversational pace", duration: "30 to 40 min",
      detail: "30 to 40 min at a pace where you can talk in full sentences. It will feel embarrassingly slow. That is correct, and it is what makes the hard sessions and padel feel easy.",
      fromWeek3: "From week 3, end it with 4 to 6 × 20 m sprints outdoors, walking back between them. That covers the sprinting the gym has no room for.",
      easy: true,
    },
    rest_walk: {
      key: "rest_walk", name: "Off", kind: "rest", subtitle: "Or a long walk or hike with the baby in a carrier", duration: "Any",
      detail: "Steps still count today: 8,000 to 10,000. The knee and back routine fits well here.",
    },
    rest_padel: {
      key: "rest_padel", name: "Rest day", kind: "rest", subtitle: "Padel is today (extra, not counted)", duration: "",
      detail: "Padel does not count as a training day. Steps still count: 8,000 to 10,000.",
    },
    other: {
      key: "other", name: "Other workout", kind: "other", subtitle: "Anything not in the plan", duration: "",
      detail: "Log distance, time and notes. Attach a Garmin file if you have one.",
    },
  },

  tests: [
    { key: "five_k_sec", name: "5 km time", unit: "mm:ss", input: "time" },
    { key: "broad_jump_cm", name: "Broad jump", unit: "cm", input: "number" },
    { key: "slh_left_cm", name: "Single leg hop, left", unit: "cm", input: "number" },
    { key: "slh_right_cm", name: "Single leg hop, right", unit: "cm", input: "number" },
    { key: "shuttle_sec", name: "5-10-5 shuttle", unit: "s", input: "number", step: 0.01 },
    { key: "squat_3rm_kg", name: "Squat 3RM", unit: "kg", input: "number" },
    { key: "bench_3rm_kg", name: "Bench 3RM", unit: "kg", input: "number" },
    { key: "deadlift_3rm_kg", name: "Deadlift 3RM", unit: "kg", input: "number" },
  ],
};

export const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
export const WEEKDAYS_LONG = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

// ---- date helpers (all on YYYY-MM-DD strings, no timezone surprises) ----
export function parseDate(s) {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}
export function fmtDate(d) {
  return d.toISOString().slice(0, 10);
}
export function addDays(s, n) {
  const d = parseDate(s);
  d.setUTCDate(d.getUTCDate() + n);
  return fmtDate(d);
}
export function daysBetween(a, b) {
  return Math.round((parseDate(b) - parseDate(a)) / 86400000);
}
export function isoWeekday(s) {
  // 1 = Monday ... 7 = Sunday
  const d = parseDate(s).getUTCDay();
  return d === 0 ? 7 : d;
}
export function mondayOf(s) {
  return addDays(s, -(isoWeekday(s) - 1));
}
export function todayLocal() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

export function weekNumber(dateStr, startDate) {
  const start = mondayOf(startDate);
  return Math.floor(daysBetween(start, dateStr) / 7) + 1; // can be 0 or negative before the start
}

export function phaseForWeek(week, settings = {}) {
  const override = Number(settings.phase_override || 0);
  if (override >= 1 && override <= 3) return override;
  if (week < 1) return 1;
  const p = PROGRAM.phases.find((p) => week >= p.weekFrom && week <= p.weekTo);
  return p ? p.id : 3;
}

export function isDeloadWeek(week) {
  return week >= 1 && week % PROGRAM.deloadEveryWeeks === 0;
}
export function isTestWeek(week) {
  if (week < 1) return false;
  if (PROGRAM.testWeeks.includes(week)) return true;
  return week > 16 && (week - 16) % 8 === 0;
}

export function scheduledTemplateKey(dateStr, week) {
  const wd = isoWeekday(dateStr);
  switch (wd) {
    case 1: return "lift_a";
    case 2:
      if (isTestWeek(week)) return "time_trial_5k";
      if (week <= 4) return "intervals_6x2";
      if (week <= 8) return "intervals_5x3";
      return "intervals_4x4";
    case 3: return "lift_b";
    case 4: return "easy_run";
    case 5: return "lift_c";
    case 6: return "rest_walk";
    default: return "rest_padel";
  }
}

export function templateFor(key) {
  return PROGRAM.templates[key] || PROGRAM.templates.other;
}

export function exerciseFor(key) {
  const ex = PROGRAM.exercises[key];
  if (ex) return { key, ...ex };
  if (key && key.startsWith("custom:")) {
    const name = key.slice(7).replace(/_/g, " ");
    return { key, name: name.charAt(0).toUpperCase() + name.slice(1), fields: ["kg", "reps"], load: "other", increment: 2.5, group: "other", e1rm: true, custom: true };
  }
  return { key, name: key || "Unknown", fields: ["kg", "reps"], load: "other", increment: 2.5, group: "other" };
}

// Build the exercise plan for a template on a given week (deload halves the sets).
export function buildPlan(templateKey, week) {
  const t = templateFor(templateKey);
  if (!t.exercises) return [];
  const deload = isDeloadWeek(week);
  return t.exercises.map((e) => ({
    ...e,
    sets: deload ? Math.max(1, Math.ceil(e.sets / 2)) : e.sets,
    plannedSets: e.sets,
  }));
}

// Resolve everything the UI needs to know about a date.
export function resolveDay(dateStr, settings = {}) {
  const startDate = settings.program_start_date || PROGRAM.startDateDefault;
  const week = weekNumber(dateStr, startDate);
  const phase = phaseForWeek(week, settings);
  const defaultTemplateKey = scheduledTemplateKey(dateStr, Math.max(week, 1));
  const override = settings.overrides ? settings.overrides[dateStr] : null;
  const templateKey = override && PROGRAM.templates[override] ? override : defaultTemplateKey;
  const template = templateFor(templateKey);
  const phaseInfo = PROGRAM.phases.find((p) => p.id === phase);
  return {
    date: dateStr,
    defaultTemplateKey,
    moved: templateKey !== defaultTemplateKey,
    weekday: isoWeekday(dateStr),
    weekdayName: WEEKDAYS_LONG[isoWeekday(dateStr) - 1],
    week,
    beforeStart: week < 1,
    beyondPlan: week > PROGRAM.plannedWeeks,
    phase,
    phaseName: phaseInfo ? phaseInfo.name : "",
    deload: isDeloadWeek(week),
    testWeek: isTestWeek(week),
    templateKey,
    template,
    plan: buildPlan(templateKey, week),
    jumps: template.blocks && template.blocks.includes("jumps") ? PROGRAM.jumps.byPhase[phase] : null,
    extras: [
      ...(templateKey === "easy_run" && week >= 3 && template.fromWeek3 ? [template.fromWeek3] : []),
      ...(isoWeekday(dateStr) === 7 ? ["Padel (extra, not counted)"] : isoWeekday(dateStr) === 1 ? ["Badminton in the evening (extra, not counted)"] : []),
    ],
    startDate,
  };
}

// Epley estimated one-rep max. Only meaningful for 1 to 12 reps.
export function e1rm(kg, reps) {
  if (!kg || !reps || reps < 1) return null;
  if (reps === 1) return kg;
  return kg * (1 + reps / 30);
}

export function fmtTime(sec) {
  if (sec == null || isNaN(sec)) return "";
  sec = Math.round(sec);
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}` : `${m}:${String(s).padStart(2, "0")}`;
}

export function parseTime(str) {
  // "25:37" or "1:02:11" or "25.5" (minutes) -> seconds
  if (str == null) return null;
  str = String(str).trim();
  if (!str) return null;
  if (/^\d+(\.\d+)?$/.test(str)) return Math.round(parseFloat(str) * 60);
  const parts = str.split(":").map((p) => parseFloat(p));
  if (parts.some((p) => isNaN(p))) return null;
  if (parts.length === 2) return Math.round(parts[0] * 60 + parts[1]);
  if (parts.length === 3) return Math.round(parts[0] * 3600 + parts[1] * 60 + parts[2]);
  return null;
}

export function fmtPace(secPerKm) {
  if (!secPerKm || !isFinite(secPerKm)) return "";
  return fmtTime(secPerKm) + "/km";
}
