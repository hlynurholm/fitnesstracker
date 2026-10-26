-- Notes per exercise or block (warmup, jumps, finisher) inside a workout, separate from the workout's general notes.
CREATE TABLE IF NOT EXISTS workout_notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workout_id INTEGER NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
  block TEXT NOT NULL,                      -- exercise key, or warmup | jumps | finisher
  note TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (workout_id, block)
);
CREATE INDEX IF NOT EXISTS workout_notes_block ON workout_notes(block);
