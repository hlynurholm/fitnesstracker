-- Reports get a section so the app can show the latest diet or training note in the right tab.
-- A future scheduled Claude task posts to /api/reports with section 'diet' or 'training'.
ALTER TABLE reports ADD COLUMN section TEXT NOT NULL DEFAULT 'general';
CREATE INDEX IF NOT EXISTS reports_section ON reports(section, date);
