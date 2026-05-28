-- User streaks: track daily cleaning streaks with server-side persistence
CREATE TABLE IF NOT EXISTS user_streaks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  current_streak INT NOT NULL DEFAULT 0,
  best_streak INT NOT NULL DEFAULT 0,
  last_activity_date DATE,
  lifetime_items_cleaned INT NOT NULL DEFAULT 0,
  lifetime_bytes_saved BIGINT NOT NULL DEFAULT 0,
  total_scans_completed INT NOT NULL DEFAULT 0,
  clean_score INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

CREATE INDEX idx_user_streaks_user ON user_streaks(user_id);

-- Activity log: individual streak-eligible actions for history/analytics
CREATE TABLE IF NOT EXISTS streak_activities (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,  -- deletion, scan, compression, email_cleanup, contact_cleanup
  item_count INT NOT NULL DEFAULT 0,
  bytes_saved BIGINT NOT NULL DEFAULT 0,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_streak_activities_user ON streak_activities(user_id);
CREATE INDEX idx_streak_activities_created ON streak_activities(created_at);
