-- Coin-based 1000-level progression. Replaces the daily Clean Bar momentum
-- score (clean_bar_daily / clean_bar_events). Coins are the only currency:
-- the Clean Bar is now progress within the current level, the bee stage is
-- derived from the Clean Bar %, and there is NO decay of any kind.

DROP TABLE IF EXISTS clean_bar_events;
DROP TABLE IF EXISTS clean_bar_daily;

-- One row per user. Source of truth is total_lifetime_coins; everything else
-- (level, clean_bar_percent, bee_stage) is derived and cached here.
-- max_lifetime_coins = (total_photos + total_videos) * 10, recomputed on each
-- full rescan (see coin-progression.service.ts syncLibrary).
CREATE TABLE IF NOT EXISTS user_progress (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  total_photos INT NOT NULL DEFAULT 0,
  total_videos INT NOT NULL DEFAULT 0,
  total_assets INT NOT NULL DEFAULT 0,
  max_lifetime_coins INT NOT NULL DEFAULT 0,
  total_lifetime_coins INT NOT NULL DEFAULT 0,
  current_level INT NOT NULL DEFAULT 1,
  max_level INT NOT NULL DEFAULT 1,
  current_level_coins INT NOT NULL DEFAULT 0,
  coins_needed_for_next_level INT NOT NULL DEFAULT 1,
  clean_bar_percent NUMERIC NOT NULL DEFAULT 0,
  bee_stage INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_progress_user ON user_progress(user_id);

-- Generated per user from max_lifetime_coins. Regenerated on rescan.
-- sum(coins_required) == max_lifetime_coins (invariant).
CREATE TABLE IF NOT EXISTS level_requirements (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level INT NOT NULL,
  coins_required INT NOT NULL,
  cumulative_coins_required INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, level)
);

CREATE INDEX idx_level_requirements_user ON level_requirements(user_id);

-- Append-only coin award ledger. `event_id` is a client-generated composite
-- ("{planId}:{taskId}:{checkpointId}") — UNIQUE(user_id, event_id) makes
-- award POSTs idempotent (retries / double-taps / offline replay no-op).
CREATE TABLE IF NOT EXISTS coin_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id TEXT NOT NULL,
  plan_id TEXT,
  task_id TEXT,
  checkpoint_id TEXT,
  event_type TEXT NOT NULL DEFAULT 'checkpoint',
  reviewed_item_count INT NOT NULL DEFAULT 0,
  selected_item_count INT NOT NULL DEFAULT 0,
  deleted_bytes BIGINT NOT NULL DEFAULT 0,
  category_breakdown_json JSONB,
  coins_earned INT NOT NULL DEFAULT 0,
  total_lifetime_coins_before INT NOT NULL DEFAULT 0,
  total_lifetime_coins_after INT NOT NULL DEFAULT 0,
  level_before INT NOT NULL DEFAULT 1,
  level_after INT NOT NULL DEFAULT 1,
  bee_stage_before INT NOT NULL DEFAULT 1,
  bee_stage_after INT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, event_id)
);

CREATE INDEX idx_coin_events_user ON coin_events(user_id);

-- Analytics: one row per guided task session.
CREATE TABLE IF NOT EXISTS task_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id TEXT,
  task_id TEXT,
  checkpoint_count INT NOT NULL DEFAULT 0,
  estimated_bytes BIGINT NOT NULL DEFAULT 0,
  total_deleted_bytes BIGINT NOT NULL DEFAULT 0,
  total_coins_earned INT NOT NULL DEFAULT 0,
  completed_checkpoint_count INT NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

CREATE INDEX idx_task_sessions_user ON task_sessions(user_id);

-- Analytics: one row per completed checkpoint within a task session.
CREATE TABLE IF NOT EXISTS checkpoint_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  task_session_id UUID NOT NULL REFERENCES task_sessions(id) ON DELETE CASCADE,
  checkpoint_id TEXT,
  estimated_bytes BIGINT NOT NULL DEFAULT 0,
  deleted_bytes BIGINT NOT NULL DEFAULT 0,
  deleted_item_count INT NOT NULL DEFAULT 0,
  coins_earned INT NOT NULL DEFAULT 0,
  completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_checkpoint_sessions_task ON checkpoint_sessions(task_session_id);
