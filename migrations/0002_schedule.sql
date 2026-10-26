-- Per-day overrides of the planned session, so sessions can be moved between days.
CREATE TABLE IF NOT EXISTS schedule_overrides (
  date TEXT PRIMARY KEY,
  template_key TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
