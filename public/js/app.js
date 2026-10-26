// App shell: routing, settings cache, offline handling.
import { api, flushQueue, queueLength } from "./api.js";
import { h, clear, store, toast } from "./util.js";
import { todayLocal } from "./program.js";
import { renderToday } from "./views/today.js";
import { renderHistory } from "./views/history.js";
import { renderCalendar } from "./views/calendar.js";
import { renderProgress } from "./views/progress.js";
import { renderData } from "./views/data.js";
import { renderSettings } from "./views/settings.js";

export const state = { settings: store.get("ft_settings", {}), online: navigator.onLine };
let cleanup = null;

export async function loadSettings(force = false) {
  if (!force && state.settings && state.settings.program_start_date && state.loadedOnce) return state.settings;
  try {
    const s = await api.get("/api/settings");
    state.settings = s; state.loadedOnce = true;
    store.set("ft_settings", s);
  } catch (e) {
    if (!state.settings.program_start_date) throw e;
  }
  return state.settings;
}

const routes = [
  { re: /^\/$/, name: "today", render: (c) => renderToday(c, { date: todayLocal() }) },
  { re: /^\/day\/(\d{4}-\d{2}-\d{2})$/, name: "today", render: (c, m) => renderToday(c, { date: m[1] }) },
  { re: /^\/history$/, name: "calendar", render: (c) => renderHistory(c) },
  { re: /^\/calendar$/, name: "calendar", render: (c) => renderCalendar(c, {}) },
  { re: /^\/calendar\/(\d{4}-\d{2})$/, name: "calendar", render: (c, m) => renderCalendar(c, { month: m[1] }) },
  { re: /^\/progress$/, name: "progress", render: (c) => renderProgress(c) },
  { re: /^\/data$/, name: "data", render: (c) => renderData(c, {}) },
  { re: /^\/reports\/(\d+)$/, name: "data", render: (c, m) => renderData(c, { reportId: Number(m[1]) }) },
  { re: /^\/settings$/, name: "settings", render: (c) => renderSettings(c) },
];

export function navigate(path, replace = false) {
  if (replace) history.replaceState(null, "", path); else history.pushState(null, "", path);
  render();
}

async function render() {
  const container = document.getElementById("view");
  const path = location.pathname.replace(/\/+$/, "") || "/";
  const route = routes.find((r) => r.re.test(path)) || routes[0];
  const m = path.match(route.re) || [];
  document.querySelectorAll(".nav-item").forEach((a) => a.classList.toggle("active", a.dataset.route === route.name));
  if (typeof cleanup === "function") { try { cleanup(); } catch {} }
  cleanup = null;
  clear(container);
  container.className = "view" + (route.name === "progress" ? " wide" : "");
  container.appendChild(h("div", { class: "loading" }, "Loading"));
  try {
    await loadSettings();
    cleanup = await route.render(container, m);
  } catch (e) {
    clear(container);
    container.appendChild(h("div", { class: "card" }, h("h2", null, "Could not load"), h("p", { class: "muted" }, e.message), h("button", { class: "btn", onClick: () => render() }, "Retry")));
  }
  window.scrollTo(0, 0);
}

document.addEventListener("click", (e) => {
  const a = e.target.closest("a");
  if (!a || a.target === "_blank" || a.hasAttribute("download") || a.dataset.native != null) return;
  const href = a.getAttribute("href");
  if (!href || !href.startsWith("/") || href.startsWith("/api/")) return;
  e.preventDefault();
  navigate(href);
});
window.addEventListener("popstate", render);
window.addEventListener("online", async () => { state.online = true; await flushQueue(); render(); });
window.addEventListener("offline", () => { state.online = false; toast("You are offline. Logging still works."); });
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && queueLength()) flushQueue(); });

if ("serviceWorker" in navigator && location.protocol === "https:") {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}

(async () => {
  if (queueLength()) await flushQueue();
  render();
})();
