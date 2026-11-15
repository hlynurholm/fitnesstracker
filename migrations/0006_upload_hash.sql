-- Content hash of each uploaded file, so the same file uploaded twice (by hand or by the Garmin sync) is recognised
-- and not ingested again. Rows from before this migration have NULL and are matched by filename and size on demand.
ALTER TABLE uploads ADD COLUMN content_sha256 TEXT;
CREATE INDEX IF NOT EXISTS uploads_sha ON uploads(content_sha256);
