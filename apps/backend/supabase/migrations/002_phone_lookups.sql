-- Phone number lookup cache
-- Stores results from NumVerify API to avoid repeat lookups

CREATE TABLE IF NOT EXISTS phone_lookups (
  phone TEXT PRIMARY KEY,
  valid BOOLEAN,
  carrier TEXT,
  line_type TEXT,
  location TEXT,
  country_code TEXT,
  country_name TEXT,
  international_format TEXT,
  looked_up_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for cleanup of stale entries
CREATE INDEX IF NOT EXISTS idx_phone_lookups_looked_up_at ON phone_lookups (looked_up_at);
