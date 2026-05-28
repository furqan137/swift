-- "Shuffling System": persist the user's current active cleanup task and a
-- forever-growing history of completed tasks. Wraps the existing client-side
-- task generator (CleanupOrchestrator) — generation/coin/level logic is
-- unchanged. task_number is a per-user, monotonically increasing counter that
-- only advances when a task is COMPLETED (never resets).

-- Exactly one active task per user (UNIQUE user_id). The client persists the
-- display snapshot of whatever the existing generator produced.
CREATE TABLE IF NOT EXISTS active_cleanup_task (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  task_number INT NOT NULL,
  task_title TEXT,
  task_type TEXT,
  category TEXT,
  estimated_mb NUMERIC NOT NULL DEFAULT 0,
  estimated_coins INT NOT NULL DEFAULT 0,
  level INT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'active',
  generated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_active_cleanup_task_user ON active_cleanup_task(user_id);

-- Append-only completion history. Persists forever unless manually cleared.
CREATE TABLE IF NOT EXISTS completed_cleanup_tasks (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  task_number INT NOT NULL,
  task_title TEXT,
  task_type TEXT,
  category TEXT,
  mb_cleaned NUMERIC NOT NULL DEFAULT 0,
  coins_earned INT NOT NULL DEFAULT 0,
  level_at_completion INT NOT NULL DEFAULT 1,
  asset_count INT NOT NULL DEFAULT 0,
  metadata_json JSONB,
  completed_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_completed_cleanup_tasks_user_completed
  ON completed_cleanup_tasks(user_id, completed_at DESC);
