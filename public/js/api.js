// Fetch wrapper with an offline queue for writes. Writes that fail with a network error are stored on the phone and replayed later.
import { store, toast } from "./util.js";

const QUEUE_KEY = "ft_queue_v1";
export class NetworkError extends Error {}

async function request(method, path, body, opts = {}) {
  let res;
  try {
    res = await fetch(path, {
      method,
      headers: body && !(body instanceof FormData) ? { "Content-Type": "application/json" } : undefined,
      body: body instanceof FormData ? body : body != null ? JSON.stringify(body) : undefined,
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch (e) {
    throw new NetworkError(e.message || "Network error");
  }
  if (res.status === 401) {
    if (!opts.silent) location.href = "/login?next=" + encodeURIComponent(location.pathname + location.search);
    throw new Error("Not logged in");
  }
  const ct = res.headers.get("Content-Type") || "";
  const data = ct.includes("json") ? await res.json().catch(() => ({})) : await res.text();
  if (!res.ok) throw new Error((data && data.error) || `Request failed (${res.status})`);
  return data;
}

export const api = {
  get: (p, opts) => request("GET", p, null, opts),
  post: (p, b, opts) => request("POST", p, b, opts),
  put: (p, b, opts) => request("PUT", p, b, opts),
  patch: (p, b, opts) => request("PATCH", p, b, opts),
  del: (p, opts) => request("DELETE", p, null, opts),
  upload: (formData) => request("POST", "/api/uploads", formData),
};

// Queued write: same path + key dedupes, newest body wins.
export async function queuedWrite(method, path, body, key) {
  try {
    const r = await request(method, path, body);
    return { ok: true, data: r };
  } catch (e) {
    if (e instanceof NetworkError) {
      const q = store.get(QUEUE_KEY, []).filter((x) => x.key !== key);
      q.push({ key, method, path, body, at: Date.now() });
      store.set(QUEUE_KEY, q);
      toast("Offline. Saved on this phone, will sync later.");
      return { ok: false, queued: true };
    }
    throw e;
  }
}

export function queueLength() { return store.get(QUEUE_KEY, []).length; }

let flushing = false;
export async function flushQueue() {
  if (flushing) return 0;
  flushing = true;
  let sent = 0;
  try {
    let q = store.get(QUEUE_KEY, []);
    while (q.length) {
      const item = q[0];
      try {
        await request(item.method, item.path, item.body, { silent: true });
        q.shift(); sent++;
        store.set(QUEUE_KEY, q);
      } catch (e) {
        if (e instanceof NetworkError) break;
        // Server rejected it: drop it so the queue does not block forever.
        console.warn("Dropping queued write", item, e);
        q.shift();
        store.set(QUEUE_KEY, q);
      }
    }
  } finally { flushing = false; }
  if (sent) toast(`Synced ${sent} saved change${sent === 1 ? "" : "s"}.`);
  return sent;
}
