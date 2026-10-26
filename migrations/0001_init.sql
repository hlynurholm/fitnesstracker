-- Fitness tracker schema. SQLite (Cloudflare D1).
-- Dates are stored as local calendar dates (YYYY-MM-DD) as seen on the phone.

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- One row per training session. A date can have more than one (for example a swapped session plus an extra run).
CREATE TABLE IF NOT EXISTS workouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  template_key TEXT NOT NULL,
  kind TEXT NOT NULL,                       -- lift | run | rest | other
  status TEXT NOT NULL DEFAULT 'in_progress', -- in_progress | done | skipped
  week_no INTEGER,
  phase INTEGER,
  plan_json TEXT,                           -- snapshot of the exercise plan for this session (swaps, added exercises)
  checklist_json TEXT,                      -- ticked warm-up, jump and finisher items
  started_at TEXT,
  finished_at TEXT,
  duration_min REAL,
  distance_km REAL,
  time_sec INTEGER,
  avg_hr INTEGER,
  rpe INTEGER,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (date, template_key)
);
CREATE INDEX IF NOT EXISTS workouts_date ON workouts(date);

-- Every logged set. client_id is generated on the phone so sets can be saved offline and synced later.
CREATE TABLE IF NOT EXISTS sets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_id TEXT NOT NULL UNIQUE,
  workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  exercise_key TEXT NOT NULL,
  set_index INTEGER NOT NULL,
  weight_kg REAL,
  reps INTEGER,
  seconds INTEGER,
  distance_m REAL,
  rpe REAL,
  done INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS sets_workout ON sets(workout_id);
CREATE INDEX IF NOT EXISTS sets_exercise ON sets(exercise_key);

-- Body weight (and anything else measured on a date).
CREATE TABLE IF NOT EXISTS body_metrics (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  weight_kg REAL,
  notes TEXT,
  source TEXT NOT NULL DEFAULT 'manual',    -- manual | myfitnesspal | garmin
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (date, source)
);

-- Performance tests (weeks 1, 8, 16): 5 km time, broad jump, single leg hops, shuttle, 3RMs.
CREATE TABLE IF NOT EXISTS tests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,
  week_no INTEGER,
  test_key TEXT NOT NULL,
  value REAL,
  notes TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (date, test_key)
);

-- Uploaded files (Garmin FIT/TCX/GPX/CSV, MyFitnessPal CSV). Raw bytes are kept gzipped so Claude can re-analyse later.
CREATE TABLE IF NOT EXISTS uploads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workout_id INTEGER REFERENCES workouts(id) ON DELETE SET NULL,
  source TEXT NOT NULL,                     -- garmin | myfitnesspal | other
  format TEXT NOT NULL,                     -- fit | tcx | gpx | csv | json | unknown
  filename TEXT,
  content_type TEXT,
  size_bytes INTEGER,
  raw BLOB,
  raw_encoding TEXT,                        -- gzip | NULL
  parsed_json TEXT,
  parse_status TEXT NOT NULL DEFAULT 'pending', -- parsed | stored_raw | failed
  parse_error TEXT,
  uploaded_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS uploads_workout ON uploads(workout_id);

-- Parsed activity summaries from Garmin files (one per activity).
CREATE TABLE IF NOT EXISTS activities (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  upload_id INTEGER REFERENCES uploads(id) ON DELETE CASCADE,
  workout_id INTEGER REFERENCES workouts(id) ON DELETE SET NULL,
  start_time TEXT,
  date TEXT,
  sport TEXT,
  name TEXT,
  distance_m REAL,
  duration_s REAL,
  elapsed_s REAL,
  avg_hr INTEGER,
  max_hr INTEGER,
  calories REAL,
  elevation_gain_m REAL,
  avg_cadence REAL,
  avg_pace_s_per_km REAL,
  best_5k_s REAL,
  best_1k_s REAL,
  laps_json TEXT,
  splits_json TEXT,
  hr_zones_json TEXT,
  track_json TEXT,                          -- downsampled time series for charts
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS activities_date ON activities(date);

-- One row per day of nutrition, aggregated from MyFitnessPal exports.
CREATE TABLE IF NOT EXISTS nutrition_days (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL UNIQUE,
  calories REAL,
  protein_g REAL,
  carbs_g REAL,
  fat_g REAL,
  fiber_g REAL,
  sugar_g REAL,
  sodium_mg REAL,
  meals_json TEXT,
  source TEXT NOT NULL DEFAULT 'myfitnesspal',
  upload_id INTEGER REFERENCES uploads(id) ON DELETE SET NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Reports written by Claude (or pasted in), shown in the app.
CREATE TABLE IF NOT EXISTS reports (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date TEXT,
  body_md TEXT NOT NULL,
  author TEXT NOT NULL DEFAULT 'claude',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Login throttling.
CREATE TABLE IF NOT EXISTS login_attempts (
  ip TEXT PRIMARY KEY,
  failures INTEGER NOT NULL DEFAULT 0,
  window_start TEXT NOT NULL DEFAULT (datetime('now'))
);
