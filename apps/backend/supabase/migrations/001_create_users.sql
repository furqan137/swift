-- Create users table for BeeClean
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  name TEXT,
  picture TEXT,
  google_id TEXT UNIQUE,
  google_access_token TEXT,
  google_refresh_token TEXT,
  subscription_status TEXT DEFAULT 'free', -- free, trial, premium
  subscription_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_google_id ON users(google_id);

-- Create user_settings table
CREATE TABLE IF NOT EXISTS user_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  notifications_enabled BOOLEAN DEFAULT true,
  auto_scan_enabled BOOLEAN DEFAULT false,
  scan_frequency TEXT DEFAULT 'weekly', -- daily, weekly, monthly
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);

-- Create scan_history table
CREATE TABLE IF NOT EXISTS scan_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  scan_type TEXT NOT NULL, -- photos, videos, contacts, emails
  items_found INTEGER DEFAULT 0,
  items_cleaned INTEGER DEFAULT 0,
  space_freed_bytes BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scan_history_user ON scan_history(user_id);

-- Create vault_items table (for Secret Space)
CREATE TABLE IF NOT EXISTS vault_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_type TEXT NOT NULL, -- image, video, document
  file_size BIGINT,
  encrypted_path TEXT NOT NULL,
  thumbnail_path TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vault_items_user ON vault_items(user_id);

-- Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE scan_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE vault_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies (service role bypasses these)
CREATE POLICY "Users can view own data" ON users
  FOR SELECT USING (auth.uid()::text = id::text);

CREATE POLICY "Users can update own data" ON users
  FOR UPDATE USING (auth.uid()::text = id::text);

CREATE POLICY "Users can view own settings" ON user_settings
  FOR ALL USING (user_id IN (SELECT id FROM users WHERE auth.uid()::text = id::text));

CREATE POLICY "Users can view own scan history" ON scan_history
  FOR ALL USING (user_id IN (SELECT id FROM users WHERE auth.uid()::text = id::text));

CREATE POLICY "Users can manage own vault" ON vault_items
  FOR ALL USING (user_id IN (SELECT id FROM users WHERE auth.uid()::text = id::text));
