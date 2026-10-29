// Drives the app in a headless browser: logs in, logs a set, checks it persisted, takes screenshots.
import { createRequire } from "node:module";
const { chromium } = createRequire(import.meta.url)(process.env.PLAYWRIGHT_PATH || "playwright");
import fs from "node:fs";

const base = process.env.BASE || "http://127.0.0.1:8787";
const out = process.env.OUT || "docs/screenshots";
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
let errors = [];

async function login(ctx) {
  const page = await ctx.newPage();
  page.on("console", (m) => { if (m.type() === "error") errors.push("console: " + m.text()); });
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
  await page.goto(base + "/login");
  await page.fill("#password", process.env.APP_PASSWORD || "changeme");
  await page.click("button[type=submit]");
  await page.waitForURL(base + "/");
  return page;
}

// Phone
const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true, colorScheme: "light" });
const p = await login(phone);
await p.waitForSelector(".session-card");
await p.screenshot({ path: `${out}/phone-today.png`, fullPage: true });

// A fresh lifting day: overview only, no inputs until Start workout. Remove leftovers from an earlier run first.
await p.evaluate(async () => {
  const d = await (await fetch("/api/day/2026-11-09", { cache: "no-store" })).json();
  for (const w of d.workouts || []) if (w.id) await fetch(`/api/workouts/${w.id}`, { method: "DELETE" });
  for (const k of Object.keys(localStorage)) if (k.includes("2026-11-09")) localStorage.removeItem(k);
});
await p.goto(base + "/day/2026-11-09");
await p.waitForSelector(".session-card");
if (await p.locator(".exercise").count() !== 0) errors.push("overview shows inputs before start");
await p.screenshot({ path: `${out}/phone-overview.png`, fullPage: true });
await p.locator("button", { hasText: "Start workout" }).click();
await p.waitForSelector(".exercise");
await p.waitForTimeout(800);
if (!(await p.locator(".timer-bar [data-tb-workout]").isVisible())) errors.push("timer bar not visible in log mode");
await p.screenshot({ path: `${out}/phone-logging.png`, fullPage: true });
// Note on an exercise
const benchBlock = p.locator('.exercise[data-key="db_bench"]');
await benchBlock.locator(".note-toggle").click();
await benchBlock.locator("textarea").fill("Right shoulder clicked on set 2");
// Countdown on a timed set: 2 seconds, then the set is ticked automatically
const plank = p.locator('.exercise[data-key="suitcase_march"]');
await plank.locator(".set-row").first().locator("input").nth(1).fill("2");
await plank.locator(".set-row").first().locator(".count-btn").click();
await p.waitForTimeout(3200);
if (!(await plank.locator(".set-row").first().locator(".tick").evaluate((el) => el.classList.contains("done")))) errors.push("countdown did not tick the set");

// Log a set: type kg and reps, tick.
const bench = p.locator('.exercise[data-key="db_bench"] .set-row').first();
await bench.locator("input").nth(0).fill("30");
await bench.locator("input").nth(1).fill("8");
await bench.locator(".tick").click();
// Tick the second set with empty fields: should take placeholders from the first set.
await p.locator('.exercise[data-key="db_bench"] .set-row').nth(1).locator(".tick").click();
// Third set: type a value but do not tick (draft), then untick the second set.
await p.locator('.exercise[data-key="db_bench"] .set-row').nth(2).locator("input").nth(0).fill("32.5");
await p.locator('.exercise[data-key="db_bench"] .set-row').nth(1).locator(".tick").click();
await p.waitForTimeout(1500);
await p.reload();
await p.waitForSelector(".exercise");
const rows = p.locator('.exercise[data-key="db_bench"] .set-row');
const kg0 = await rows.nth(0).locator("input").nth(0).inputValue();
const kg1 = await rows.nth(1).locator("input").nth(0).inputValue();
const reps1 = await rows.nth(1).locator("input").nth(1).inputValue();
const kg2 = await rows.nth(2).locator("input").nth(0).inputValue();
const done0 = await rows.nth(0).locator(".tick").evaluate((el) => el.classList.contains("done"));
const done1 = await rows.nth(1).locator(".tick").evaluate((el) => el.classList.contains("done"));
const done2 = await rows.nth(2).locator(".tick").evaluate((el) => el.classList.contains("done"));
console.log(`persisted after reload: set1 kg=${kg0} done=${done0}, set2 kg=${kg1} reps=${reps1} done=${done1}, set3 kg=${kg2} done=${done2}`);
if (kg0 !== "30" || kg1 !== "30" || reps1 !== "8" || kg2 !== "32.5") errors.push("set persistence failed");
if (!done0 || done1 || done2) errors.push("tick state wrong after untick/draft");
const noteBack = await p.locator('.exercise[data-key="db_bench"] textarea').inputValue();
if (!/shoulder/.test(noteBack)) errors.push("exercise note did not persist: " + noteBack);
const plankBack = await p.locator('.exercise[data-key="suitcase_march"] .set-row').first().locator("input").nth(1).inputValue();
if (plankBack !== "2") errors.push("countdown value did not persist: " + plankBack);
await p.screenshot({ path: `${out}/phone-today-logged.png`, fullPage: false });

// Warm-up checklist tick persists
await p.locator("details summary").first().click();
await p.locator("details .check input").first().check();
await p.waitForTimeout(1200);
await p.reload(); await p.waitForSelector(".exercise");
const checked = await p.locator("details .check input").first().isChecked();
console.log("warm-up tick persisted:", checked);
if (!checked) errors.push("checklist persistence failed");

// Finish the workout: summary with duration, then edit and back
await p.locator("button", { hasText: "Finish workout" }).click();
await p.locator(".rpe button").nth(6).click();
await p.locator(".modal .btn.primary", { hasText: "Done" }).click();
await p.waitForTimeout(800);
if (await p.locator(".exercise").count() !== 0) errors.push("summary still shows inputs");
const results = await p.locator(".card", { hasText: "Results" }).first().textContent();
console.log("summary:", results.replace(/\s+/g, " ").slice(0, 120));
if (!/30 kg × 8/.test(results) || !/RPE 7/.test(results)) errors.push("summary missing results or RPE");
await p.screenshot({ path: `${out}/phone-summary.png`, fullPage: true });
await p.locator("button", { hasText: "Edit workout" }).click();
await p.waitForSelector(".exercise");
await p.locator("button", { hasText: "Done editing" }).click();
await p.waitForTimeout(300);
if (await p.locator(".exercise").count() !== 0) errors.push("done editing did not return to summary");

// Week strip highlights the selected day, not today
await p.goto(base + "/day/2026-10-29"); await p.waitForSelector(".week-strip");
const selText = await p.locator(".week-day.selected b").textContent();
console.log("week strip selected day:", selText);
if (selText.trim() !== "29") errors.push("week strip selected day wrong: " + selText);
// Calendar: open, swap two days, check, swap back
await p.goto(base + "/calendar/2026-11"); await p.waitForSelector(".cal-cell");
await p.screenshot({ path: `${out}/phone-calendar.png`, fullPage: true });
await p.locator('.cal-cell[title^="Mon 9 Nov"]').click();
await p.waitForSelector(".modal");
await p.screenshot({ path: `${out}/phone-calendar-sheet.png`, fullPage: false });
await p.locator(".modal .list-item", { hasText: "Swap with another day" }).click();
await p.locator('.cal-cell[title^="Tue 10 Nov"]').click();
await p.locator(".modal .btn.primary", { hasText: "Swap" }).click();
await p.waitForTimeout(1200);
const tueLabel = await p.locator('.cal-cell[title^="Tue 10 Nov"] .s').textContent();
console.log("Tue 10 Nov after swap:", tueLabel);
if (!/Lift A/.test(tueLabel)) errors.push("calendar swap failed: " + tueLabel);
await p.locator('.cal-cell[title^="Tue 10 Nov"]').click();
await p.locator(".modal .list-item", { hasText: "Swap with another day" }).click();
await p.locator('.cal-cell[title^="Mon 9 Nov"]').click();
await p.locator(".modal .btn.primary", { hasText: "Swap" }).click();
await p.waitForTimeout(1200);
const monLabel = await p.locator('.cal-cell[title^="Mon 9 Nov"] .s').textContent();
if (!/Lift A/.test(monLabel)) errors.push("calendar swap back failed: " + monLabel);
// History, progress, data
await p.goto(base + "/history"); await p.waitForSelector(".list-item"); await p.screenshot({ path: `${out}/phone-history.png`, fullPage: true });
await p.goto(base + "/progress"); await p.waitForSelector(".tiles"); await p.waitForTimeout(800); await p.screenshot({ path: `${out}/phone-progress.png`, fullPage: true });
await p.goto(base + "/data"); await p.waitForSelector(".card"); await p.screenshot({ path: `${out}/phone-data.png`, fullPage: true });
await p.goto(base + "/diet"); await p.waitForSelector(".tiles"); await p.waitForTimeout(800); await p.screenshot({ path: `${out}/phone-diet.png`, fullPage: true });
await p.goto(base + "/settings"); await p.waitForSelector(".card"); await p.screenshot({ path: `${out}/phone-settings.png`, fullPage: true });
await phone.close();

// Desktop, dark mode
const desk = await browser.newContext({ viewport: { width: 1366, height: 900 }, colorScheme: "dark" });
const d = await login(desk);
await d.waitForSelector(".card");
await d.screenshot({ path: `${out}/desktop-today.png`, fullPage: false });
await d.goto(base + "/day/2026-11-09"); await d.waitForSelector(".card"); await d.waitForTimeout(400);
await d.screenshot({ path: `${out}/desktop-summary.png`, fullPage: false });
await d.goto(base + "/calendar"); await d.waitForSelector(".cal-cell"); await d.screenshot({ path: `${out}/desktop-calendar.png`, fullPage: false });
await d.goto(base + "/progress"); await d.waitForSelector(".tiles"); await d.waitForTimeout(1000);
await d.screenshot({ path: `${out}/desktop-progress.png`, fullPage: true });
await d.goto(base + "/data"); await d.waitForSelector(".card"); await d.screenshot({ path: `${out}/desktop-data.png`, fullPage: true });
await d.goto(base + "/diet"); await d.waitForSelector(".tiles"); await d.waitForTimeout(1000); await d.screenshot({ path: `${out}/desktop-diet.png`, fullPage: true });
await desk.close();
await browser.close();

if (errors.length) { console.log("ERRORS:\n" + errors.join("\n")); process.exit(1); }
console.log("UI check passed, screenshots in", out);
