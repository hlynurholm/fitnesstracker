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
await p.waitForSelector(".exercise");
await p.screenshot({ path: `${out}/phone-today.png`, fullPage: true });

// Log a set: type kg and reps, tick.
const bench = p.locator('.exercise[data-key="db_bench"] .set-row').first();
await bench.locator("input").nth(0).fill("30");
await bench.locator("input").nth(1).fill("8");
await bench.locator(".tick").click();
// Tick the second set with empty fields: should take placeholders from the first set.
await p.locator('.exercise[data-key="db_bench"] .set-row').nth(1).locator(".tick").click();
await p.waitForTimeout(1500);
await p.reload();
await p.waitForSelector(".exercise");
const rows = p.locator('.exercise[data-key="db_bench"] .set-row');
const kg0 = await rows.nth(0).locator("input").nth(0).inputValue();
const kg1 = await rows.nth(1).locator("input").nth(0).inputValue();
const reps1 = await rows.nth(1).locator("input").nth(1).inputValue();
console.log(`persisted after reload: set1 kg=${kg0}, set2 kg=${kg1} reps=${reps1}`);
if (kg0 !== "30" || kg1 !== "30" || reps1 !== "8") errors.push("set persistence failed");
await p.screenshot({ path: `${out}/phone-today-logged.png`, fullPage: false });

// Warm-up checklist tick persists
await p.locator("details summary").first().click();
await p.locator("details .check input").first().check();
await p.waitForTimeout(1200);
await p.reload(); await p.waitForSelector(".exercise");
const checked = await p.locator("details .check input").first().isChecked();
console.log("warm-up tick persisted:", checked);
if (!checked) errors.push("checklist persistence failed");

// Run day, week 1 Tuesday
await p.goto(base + "/day/2026-10-27");
await p.waitForSelector(".card.accent");
await p.screenshot({ path: `${out}/phone-run-day.png`, fullPage: true });
// Rest day
await p.goto(base + "/day/2026-10-31");
await p.waitForSelector(".card.accent");
await p.screenshot({ path: `${out}/phone-rest-day.png`, fullPage: true });
// History, progress, data
await p.goto(base + "/history"); await p.waitForSelector(".list-item"); await p.screenshot({ path: `${out}/phone-history.png`, fullPage: true });
await p.goto(base + "/progress"); await p.waitForSelector(".tiles"); await p.waitForTimeout(800); await p.screenshot({ path: `${out}/phone-progress.png`, fullPage: true });
await p.goto(base + "/data"); await p.waitForSelector(".card"); await p.screenshot({ path: `${out}/phone-data.png`, fullPage: true });
await p.goto(base + "/settings"); await p.waitForSelector(".card"); await p.screenshot({ path: `${out}/phone-settings.png`, fullPage: true });
await phone.close();

// Desktop, dark mode
const desk = await browser.newContext({ viewport: { width: 1366, height: 900 }, colorScheme: "dark" });
const d = await login(desk);
await d.waitForSelector(".exercise");
await d.screenshot({ path: `${out}/desktop-today.png`, fullPage: false });
await d.goto(base + "/progress"); await d.waitForSelector(".tiles"); await d.waitForTimeout(1000);
await d.screenshot({ path: `${out}/desktop-progress.png`, fullPage: true });
await d.goto(base + "/data"); await d.waitForSelector(".card"); await d.screenshot({ path: `${out}/desktop-data.png`, fullPage: true });
await desk.close();
await browser.close();

if (errors.length) { console.log("ERRORS:\n" + errors.join("\n")); process.exit(1); }
console.log("UI check passed, screenshots in", out);
