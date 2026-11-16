-- Heart rate and Body Battery through one day, as fetched from Garmin, kept so a day is asked for once.
CREATE TABLE IF NOT EXISTS day_timeline (
  date TEXT PRIMARY KEY,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
