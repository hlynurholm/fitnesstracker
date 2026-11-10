-- Daily health metrics from the watch (steps, resting heart rate, sleep, HRV, stress, Body Battery and so on),
-- imported from Garmin. One row per day; data is a flat JSON object of metric name to value, so a metric Garmin
-- adds later needs no schema change. Names follow Garmin's own fields, for example "movement.steps.value".
CREATE TABLE IF NOT EXISTS daily_metrics (
  date TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
