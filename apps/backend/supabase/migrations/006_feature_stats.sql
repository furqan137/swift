-- Compression stats: track every compression event for TestFlight analytics
CREATE TABLE IF NOT EXISTS compression_stats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  asset_id TEXT NOT NULL,
  original_bytes BIGINT NOT NULL,
  compressed_bytes BIGINT NOT NULL,
  compression_level TEXT NOT NULL,  -- low, medium, high
  codec TEXT DEFAULT 'hevc',
  duration_seconds DOUBLE PRECISION,
  compression_time_seconds DOUBLE PRECISION,
  resolution TEXT,
  success BOOLEAN DEFAULT true,
  error_message TEXT,
  device_model TEXT,
  os_version TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_compression_stats_user ON compression_stats(user_id);
CREATE INDEX IF NOT EXISTS idx_compression_stats_created ON compression_stats(created_at);

-- Contacts stats: track cleanup actions for TestFlight analytics
CREATE TABLE IF NOT EXISTS contacts_stats (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,  -- merge, delete, export, backup
  contact_count INT NOT NULL DEFAULT 1,
  duplicate_groups_merged INT,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contacts_stats_user ON contacts_stats(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_stats_created ON contacts_stats(created_at);
