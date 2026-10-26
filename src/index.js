// Cloudflare Worker entry: auth gate, API routes, static assets.
import { isAuthed, loginHandler, logoutHandler, isConfigured } from "./auth.js";
import { handleApi } from "./api.js";

const PUBLIC_PREFIXES = ["/css/", "/icons/", "/vendor/"];
const PUBLIC_FILES = new Set(["/manifest.webmanifest", "/favicon.ico", "/favicon.svg", "/login.html", "/sw.js", "/js/login.js"]);

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json; charset=utf-8", ...headers } });
}

function notConfiguredPage(env) {
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Setup needed</title>
<style>body{font-family:system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem;line-height:1.5;color:#222}code{background:#eee;padding:.1em .3em;border-radius:3px}pre{background:#eee;padding:.8rem;border-radius:6px;overflow:auto}</style></head>
<body><h1>${env.APP_NAME || "Fitness tracker"}: one step left</h1>
<p>The app is deployed but no password is set, so it is locked. Set the two secrets, then reload:</p>
<pre>npx wrangler secret put APP_PASSWORD
npx wrangler secret put API_TOKEN</pre>
<p>For local development put them in <code>.dev.vars</code> (see <code>.dev.vars.example</code>).</p></body></html>`;
  return new Response(html, { status: 503, headers: { "Content-Type": "text/html; charset=utf-8" } });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    try {
      if (path === "/api/health") return json({ ok: true, configured: isConfigured(env), time: new Date().toISOString() });
      if (path === "/api/login" && request.method === "POST") return loginHandler(request, env);
      if (path === "/api/logout" && request.method === "POST") return logoutHandler();

      const auth = await isAuthed(request, env);

      if (path.startsWith("/api/")) {
        if (!auth.ok) return json({ error: auth.reason === "not_configured" ? "APP_PASSWORD not set" : "Not logged in", reason: auth.reason }, 401);
        return await handleApi(request, env, ctx, url);
      }

      if (path === "/login") {
        if (auth.ok) return Response.redirect(url.origin + "/", 302);
        if (auth.reason === "not_configured") return notConfiguredPage(env);
        return env.ASSETS.fetch(new Request(url.origin + "/login.html", request));
      }

      if (!auth.ok) {
        if (auth.reason === "not_configured") return notConfiguredPage(env);
        if (PUBLIC_FILES.has(path) || PUBLIC_PREFIXES.some((p) => path.startsWith(p))) return env.ASSETS.fetch(request);
        const next = path !== "/" ? `?next=${encodeURIComponent(path + url.search)}` : "";
        return Response.redirect(url.origin + "/login" + next, 302);
      }

      // Authenticated: serve the asset, or the app shell for client-side routes.
      const assetPath = path === "/" ? "/index.html" : path;
      const res = await env.ASSETS.fetch(new Request(url.origin + assetPath, request));
      if (res.status === 404 && request.method === "GET" && !path.includes(".")) {
        return env.ASSETS.fetch(new Request(url.origin + "/index.html", request));
      }
      return res;
    } catch (err) {
      console.error(err);
      return json({ error: err.message || String(err) }, 500);
    }
  },
};
