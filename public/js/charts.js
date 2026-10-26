// Chart.js helpers with a consistent palette and dark mode support.
import { fmtShort, secondsToHms } from "./util.js";

export const PALETTE = ["#007aff", "#ff9500", "#34c759", "#af52de", "#ff2d55", "#5ac8fa", "#ffcc00", "#8e8e93", "#ff3b30", "#30d158"];
function cssVar(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

export function baseOptions(extra = {}) {
  const text = cssVar("--muted") || "#666", grid = cssVar("--border") || "#ddd";
  return {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    interaction: { mode: "nearest", axis: "x", intersect: false },
    plugins: { legend: { labels: { color: text, boxWidth: 12, usePointStyle: true } }, tooltip: { padding: 8 } },
    scales: {
      x: { ticks: { color: text, maxRotation: 0, autoSkip: true, maxTicksLimit: 8 }, grid: { color: grid, drawOnChartArea: false } },
      y: { ticks: { color: text }, grid: { color: grid } },
    },
    ...extra,
  };
}

export function destroy(canvas) { const c = Chart.getChart(canvas); if (c) c.destroy(); }

export function lineChart(canvas, { labels, datasets, yTitle, yFormatter, xLabels, stacked, yReverse, yMin, yMax, annotationLines = [] }) {
  destroy(canvas);
  const opts = baseOptions();
  if (yTitle) opts.scales.y.title = { display: true, text: yTitle, color: cssVar("--muted") };
  if (yFormatter) opts.scales.y.ticks.callback = (v) => yFormatter(v);
  if (yReverse) opts.scales.y.reverse = true;
  if (yMin != null) opts.scales.y.suggestedMin = yMin;
  if (yMax != null) opts.scales.y.suggestedMax = yMax;
  if (xLabels) opts.scales.x.ticks.callback = function (v) { return xLabels(this.getLabelForValue(v)); };
  if (yFormatter) opts.plugins.tooltip.callbacks = { label: (ctx) => `${ctx.dataset.label}: ${yFormatter(ctx.parsed.y)}` };
  const annotated = datasets.concat(annotationLines.map((l) => ({ label: l.label, data: labels.map(() => l.value), borderColor: l.color || cssVar("--muted"), borderDash: [6, 4], borderWidth: 1.5, pointRadius: 0, fill: false, tension: 0 })));
  return new Chart(canvas, { type: "line", data: { labels, datasets: annotated }, options: opts });
}

export function barChart(canvas, { labels, datasets, yFormatter, xLabels, annotationLines = [], stacked = false, y1Title }) {
  destroy(canvas);
  const opts = baseOptions();
  opts.scales.x.stacked = stacked; opts.scales.y.stacked = stacked;
  if (y1Title) opts.scales.y1 = { position: "right", ticks: { color: cssVar("--muted") }, grid: { drawOnChartArea: false }, title: { display: true, text: y1Title, color: cssVar("--muted") }, suggestedMin: 0 };
  if (yFormatter) opts.scales.y.ticks.callback = (v) => yFormatter(v);
  if (xLabels) opts.scales.x.ticks.callback = function (v) { return xLabels(this.getLabelForValue(v)); };
  const mixed = datasets.map((d) => ({ type: "bar", borderWidth: 0, borderRadius: 3, ...d })).concat(
    annotationLines.map((l) => ({ type: "line", label: l.label, data: labels.map(() => l.value), borderColor: l.color || cssVar("--muted"), borderDash: [6, 4], borderWidth: 1.5, pointRadius: 0, fill: false, yAxisID: l.axis || "y" }))
  );
  return new Chart(canvas, { type: "bar", data: { labels, datasets: mixed }, options: opts });
}

export const fmtDateTick = (s) => fmtShort(String(s));
export const fmtSecTick = (v) => secondsToHms(v);
export function dataset(label, data, i, extra = {}) {
  const color = PALETTE[i % PALETTE.length];
  return { label, data, borderColor: color, backgroundColor: color + "33", pointBackgroundColor: color, pointRadius: 3, borderWidth: 2, tension: 0.25, spanGaps: true, fill: false, ...extra };
}
