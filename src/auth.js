// Single-user auth: a password gate that sets a signed cookie, plus an optional bearer token for scripts and Claude.

const COOKIE = "ft_session";
const enc = new TextEncoder();

function b64url(bytes) {
  let s = btoa(String.fromCharCode(...new Uint8Array(bytes)));
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function hmacKey(env) {
  const material = `${env.APP_PASSWORD || ""}|${env.SESSION_SECRET || "fitness-tracker"}`;
  const digest = await crypto.subtle.digest("SHA-256", enc.encode(material));
  return crypto.subtle.importKey("raw", digest, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

async function sign(env, payload) {
  const key = await hmacKey(env);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(payload));
  return b64url(sig);
}

function constantTimeEqual(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const ab = enc.encode(a), bb = enc.encode(b);
  if (ab.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ab.length; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}

function parseCookies(request) {
  const out = {};
  const header = request.headers.get("Cookie") || "";
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

export function isConfigured(env) {
  return typeof env.APP_PASSWORD === "string" && env.APP_PASSWORD.length > 0;
}

// Returns { ok, reason, via }
export async function isAuthed(request, env) {
  if (!isConfigured(env)) return { ok: false, reason: "not_configured" };
  const auth = request.headers.get("Authorization") || "";
  if (auth.startsWith("Bearer ")) {
    const token = auth.slice(7).trim();
    if (env.API_TOKEN && constantTimeEqual(token, env.API_TOKEN)) return { ok: true, via: "token" };
    return { ok: false, reason: "bad_token" };
  }
  const cookie = parseCookies(request)[COOKIE];
  if (!cookie) return { ok: false, reason: "no_session" };
  const [exp, sig] = cookie.split(".");
  if (!exp || !sig) return { ok: false, reason: "bad_session" };
  if (Number(exp) < Date.now() / 1000) return { ok: false, reason: "expired" };
  const expected = await sign(env, exp);
  if (!constantTimeEqual(sig, expected)) return { ok: false, reason: "bad_session" };
  return { ok: true, via: "cookie" };
}

export async function sessionCookie(env) {
  const days = Number(env.SESSION_DAYS || 180);
  const exp = Math.floor(Date.now() / 1000) + days * 86400;
  const sig = await sign(env, String(exp));
  return `${COOKIE}=${exp}.${sig}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${days * 86400}`;
}

export function clearCookie() {
  return `${COOKIE}=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0`;
}

// Login throttling: 8 failures per 15 minutes per IP.
async function throttle(env, ip) {
  try {
    const row = await env.DB.prepare("SELECT failures, window_start FROM login_attempts WHERE ip = ?").bind(ip).first();
    if (!row) return { blocked: false };
    const age = (Date.now() - Date.parse(row.window_start + "Z")) / 1000;
    if (age > 900) return { blocked: false };
    return { blocked: row.failures >= 8 };
  } catch {
    return { blocked: false };
  }
}

async function recordFailure(env, ip) {
  try {
    await env.DB.prepare(
      `INSERT INTO login_attempts (ip, failures, window_start) VALUES (?, 1, datetime('now'))
       ON CONFLICT(ip) DO UPDATE SET
         failures = CASE WHEN (julianday('now') - julianday(window_start)) * 86400 > 900 THEN 1 ELSE failures + 1 END,
         window_start = CASE WHEN (julianday('now') - julianday(window_start)) * 86400 > 900 THEN datetime('now') ELSE window_start END`
    ).bind(ip).run();
  } catch {}
}

export async function loginHandler(request, env) {
  if (!isConfigured(env)) {
    return Response.json({ error: "APP_PASSWORD is not set. See README: Secrets." }, { status: 500 });
  }
  const ip = request.headers.get("CF-Connecting-IP") || "local";
  if ((await throttle(env, ip)).blocked) {
    return Response.json({ error: "Too many attempts. Wait 15 minutes." }, { status: 429 });
  }
  let password = "";
  const ct = request.headers.get("Content-Type") || "";
  if (ct.includes("application/json")) {
    const body = await request.json().catch(() => ({}));
    password = String(body.password || "");
  } else {
    const form = await request.formData().catch(() => null);
    password = form ? String(form.get("password") || "") : "";
  }
  if (!constantTimeEqual(password, env.APP_PASSWORD)) {
    await recordFailure(env, ip);
    return Response.json({ error: "Wrong password." }, { status: 401 });
  }
  try { await env.DB.prepare("DELETE FROM login_attempts WHERE ip = ?").bind(ip).run(); } catch {}
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", "Set-Cookie": await sessionCookie(env) },
  });
}

export function logoutHandler() {
  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json", "Set-Cookie": clearCookie() },
  });
}
