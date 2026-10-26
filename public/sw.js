// Network-first service worker: keeps the app shell available offline, never caches API calls.
const CACHE = "training-shell-v2";
const SHELL = ["/", "/index.html", "/css/app.css", "/js/app.js", "/js/api.js", "/js/util.js", "/js/charts.js", "/js/program.js",
  "/js/views/today.js", "/js/views/history.js", "/js/views/calendar.js", "/js/views/progress.js", "/js/views/data.js", "/js/views/settings.js",
  "/vendor/chart.umd.js", "/vendor/marked.umd.js", "/manifest.webmanifest", "/favicon.svg"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL).catch(() => {})).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.startsWith("/api/")) return;
  e.respondWith(
    fetch(e.request).then((res) => {
      if (res.ok && res.type === "basic") { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); }
      return res;
    }).catch(async () => {
      const cached = await caches.match(e.request);
      if (cached) return cached;
      if (e.request.mode === "navigate") return caches.match("/index.html");
      return new Response("Offline", { status: 503 });
    })
  );
});
