// Data page: uploads (Garmin, MyFitnessPal), export, reports from Claude.
import { api } from "../api.js";
import { h, clear, toast, modal, fmtDay, fmtShort, fmtDateTime, download, copyText, store } from "../util.js";
import { templateFor, fmtTime, fmtPace, todayLocal } from "../program.js";
import { showActivity } from "./today.js";

export async function renderData(container, { reportId }) {
  clear(container);
  if (reportId) return renderReport(container, reportId);
  container.appendChild(h("h1", null, "Data"));
  const [uploads, workouts, reports] = await Promise.all([api.get("/api/uploads"), api.get("/api/workouts?limit=60"), api.get("/api/reports")]);

  // Garmin upload
  const runs = workouts.filter((w) => w.kind === "run" || w.kind === "other");
  const garminCard = h("div", { class: "card" });
  garminCard.appendChild(h("div", { class: "card-title" }, h("h3", null, "Garmin"), h("span", { class: "muted small" }, "FIT, TCX, GPX or CSV")));
  garminCard.appendChild(h("p", { class: "small muted" }, "Export the activity from Garmin Connect (gear icon on the activity: Export Original gives a FIT file). Pick which run it belongs to, or leave it on automatic and it attaches to the run logged on that date, creating it if needed."));
  const attach = h("select", null, h("option", { value: "" }, "Automatic (match by date)"), runs.map((w) => h("option", { value: w.id }, `${fmtDay(w.date)} · ${templateFor(w.template_key).name}${w.distance_km ? ` · ${w.distance_km} km` : ""}`)));
  const gFile = h("input", { type: "file", multiple: true, accept: ".fit,.tcx,.gpx,.csv,application/octet-stream" });
  const gBtn = h("button", { class: "btn primary", onClick: () => doUpload(gFile, { source: "garmin", workout_id: attach.value }, gBtn) }, "Upload");
  garminCard.appendChild(h("label", { class: "field" }, h("span", null, "Attach to"), attach));
  garminCard.appendChild(h("label", { class: "field" }, h("span", null, "Files"), gFile));
  garminCard.appendChild(gBtn);
  container.appendChild(garminCard);

  // MFP upload
  const mfpCard = h("div", { class: "card" });
  mfpCard.appendChild(h("div", { class: "card-title" }, h("h3", null, "MyFitnessPal"), h("span", { class: "muted small" }, "CSV export")));
  mfpCard.appendChild(h("p", { class: "small muted" }, "In MyFitnessPal: Settings, Export Data (website or Premium app). Upload the Nutrition-Summary CSV; meals are summed per day. The Measurement-Summary CSV adds body weight."));
  const mFile = h("input", { type: "file", multiple: true, accept: ".csv,text/csv" });
  const mBtn = h("button", { class: "btn primary", onClick: () => doUpload(mFile, { source: "myfitnesspal" }, mBtn) }, "Upload");
  mfpCard.appendChild(h("label", { class: "field" }, h("span", null, "Files"), mFile));
  mfpCard.appendChild(mBtn);
  container.appendChild(mfpCard);

  async function doUpload(input, fields, btn) {
    if (!input.files.length) { toast("Choose a file first", true); return; }
    const fd = new FormData();
    for (const f of input.files) fd.append("file", f);
    for (const [k, v] of Object.entries(fields)) if (v) fd.append(k, v);
    fd.append("tz_offset_min", String(new Date().getTimezoneOffset()));
    btn.disabled = true;
    try {
      const r = await api.upload(fd);
      const lines = r.uploads.map((u) => {
        if (u.error && u.status === "failed") return `${u.filename}: stored, but could not be parsed (${u.error})`;
        const parts = [];
        if (u.activities.length) parts.push(`${u.activities.length} activit${u.activities.length === 1 ? "y" : "ies"}${u.activities[0].distance_m ? ` (${(u.activities[0].distance_m / 1000).toFixed(2)} km, ${fmtTime(u.activities[0].duration_s)})` : ""}`);
        if (u.nutrition_days) parts.push(`${u.nutrition_days} nutrition days`);
        if (u.body_metrics) parts.push(`${u.body_metrics} weigh-ins`);
        if (!parts.length) parts.push(u.status === "parsed" ? "parsed" : "stored raw for later analysis");
        return `${u.filename}: ${parts.join(", ")}`;
      });
      modal({ title: "Upload finished", content: h("ul", { class: "small" }, lines.map((l) => h("li", null, l))), actions: [{ label: "OK", class: "primary", onClick: () => renderData(container, {}) }] });
    } catch (e) { toast(e.message, true); btn.disabled = false; }
  }

  // Export
  const exportCard = h("div", { class: "card" });
  exportCard.appendChild(h("div", { class: "card-title" }, h("h3", null, "Export for Claude")));
  exportCard.appendChild(h("p", { class: "small muted" }, "Copy the summary and paste it into the Claude project, or download the full JSON and upload it there. The JSON holds every set, run, weigh-in, nutrition day and parsed Garmin activity."));
  exportCard.appendChild(h("div", { class: "row" },
    h("button", { class: "btn primary", onClick: async () => {
      try { const md = await api.get("/api/summary.md"); const ok = await copyText(md); if (ok) toast("Summary copied. Paste it to Claude."); else modal({ title: "Summary", content: h("textarea", { style: { minHeight: "50vh" }, value: md }), actions: [{ label: "Close", class: "ghost" }] }); } catch (e) { toast(e.message, true); }
    } }, "Copy summary for Claude"),
    h("a", { class: "btn", href: "/api/export.json", download: `fitness-export-${todayLocal()}.json`, "data-native": "" }, "Download JSON"),
    h("a", { class: "btn ghost", href: "/api/export.json?include=raw", download: `fitness-export-raw-${todayLocal()}.json`, "data-native": "" }, "JSON + raw files")));
  container.appendChild(exportCard);

  // Reports
  const repCard = h("div", { class: "card" });
  repCard.appendChild(h("div", { class: "card-title" }, h("h3", null, "Reports"), h("button", { class: "btn small", onClick: () => addReportDialog(container) }, "+ Paste a report")));
  if (!reports.length) repCard.appendChild(h("p", { class: "muted small" }, "Reports written by Claude show up here. Paste one in, or let Claude post it through the API (see Settings)."));
  for (const r of reports) repCard.appendChild(h("a", { class: "list-item", href: `/reports/${r.id}` }, h("div", null, h("div", { class: "title" }, r.title), h("div", { class: "sub" }, `${fmtShort(r.date || r.created_at)} · ${r.author} · ${(r.preview || "").replace(/[#*_`>\n]+/g, " ").slice(0, 100)}`)), h("span", { class: "muted" }, "›")));
  container.appendChild(repCard);

  // Uploads list
  const upCard = h("div", { class: "card" });
  upCard.appendChild(h("div", { class: "card-title" }, h("h3", null, "Uploaded files"), h("span", { class: "muted small" }, `${uploads.length}`)));
  if (!uploads.length) upCard.appendChild(h("p", { class: "muted small" }, "Nothing uploaded yet."));
  for (const u of uploads) {
    const status = u.parse_status === "parsed" ? h("span", { class: "badge ok" }, "parsed") : u.parse_status === "failed" ? h("span", { class: "badge danger" }, "not parsed") : h("span", { class: "badge" }, "raw");
    upCard.appendChild(h("div", { class: "list-item" },
      h("div", null,
        h("div", { class: "title" }, u.filename || `${u.format} file`),
        h("div", { class: "sub" }, [fmtDateTime(u.uploaded_at), u.source, u.format, u.size_bytes ? `${Math.round(u.size_bytes / 1024)} KB` : null, u.workout_date ? `attached to ${fmtShort(u.workout_date)} ${templateFor(u.template_key).name}` : u.activity_count ? "not attached" : null, u.parse_error].filter(Boolean).join(" · "))),
      h("div", { class: "row" }, status,
        h("button", { class: "btn small ghost", onClick: () => uploadMenu(u, runs, container) }, "⋯"))));
  }
  container.appendChild(upCard);
}

function uploadMenu(u, runs, container) {
  const content = h("div", { class: "stack" });
  if (u.activity_count) content.appendChild(h("button", { class: "btn wide", onClick: async () => { close(); const list = await api.get("/api/activities"); const a = list.find((x) => x.upload_id === u.id); if (a) showActivity(a.id); } }, "View activity"));
  const sel = h("select", null, h("option", { value: "" }, "Not attached"), runs.map((w) => h("option", { value: w.id, selected: w.id === u.workout_id }, `${fmtDay(w.date)} · ${templateFor(w.template_key).name}`)));
  content.appendChild(h("label", { class: "field" }, h("span", null, "Attached to"), sel));
  content.appendChild(h("button", { class: "btn wide", onClick: async () => { try { await api.patch(`/api/uploads/${u.id}`, { workout_id: sel.value ? Number(sel.value) : null }); toast("Updated"); close(); renderData(container, {}); } catch (e) { toast(e.message, true); } } }, "Save attachment"));
  content.appendChild(h("a", { class: "btn wide", href: `/api/uploads/${u.id}/raw`, download: u.filename || "file", "data-native": "" }, "Download original file"));
  content.appendChild(h("button", { class: "btn wide danger", onClick: async () => { if (!confirm("Delete this upload and its parsed activity?")) return; await api.del(`/api/uploads/${u.id}`); close(); renderData(container, {}); } }, "Delete upload"));
  const close = modal({ title: u.filename || "Upload", content, actions: [{ label: "Close", class: "ghost" }] });
}

function addReportDialog(container) {
  const title = h("input", { type: "text", placeholder: "Title, for example Week 4 review" });
  const body = h("textarea", { placeholder: "Paste Markdown here", style: { minHeight: "40vh" } });
  modal({ title: "Add a report", content: h("div", null, h("label", { class: "field" }, h("span", null, "Title"), title), h("label", { class: "field" }, h("span", null, "Report (Markdown)"), body)),
    actions: [{ label: "Cancel", class: "ghost" }, { label: "Save", class: "primary", onClick: async () => {
      if (!title.value.trim() || !body.value.trim()) { toast("Title and text are needed", true); return false; }
      try { await api.post("/api/reports", { title: title.value.trim(), body_md: body.value, author: "pasted" }); toast("Report saved"); renderData(container, {}); } catch (e) { toast(e.message, true); return false; }
    } }] });
}

async function renderReport(container, id) {
  const r = await api.get(`/api/reports/${id}`);
  container.appendChild(h("div", { class: "row between", style: { marginBottom: ".6rem" } }, h("a", { class: "btn small ghost", href: "/data" }, "‹ Data"),
    h("button", { class: "btn small ghost danger", onClick: async () => { if (!confirm("Delete this report?")) return; await api.del(`/api/reports/${id}`); history.back(); } }, "Delete")));
  const html = window.marked ? marked.parse(r.body_md) : r.body_md;
  container.appendChild(h("div", { class: "card" }, h("h1", null, r.title), h("p", { class: "muted small" }, `${fmtDay(r.date || r.created_at.slice(0, 10), true)} · ${r.author}`), h("div", { class: "md", html })));
}
