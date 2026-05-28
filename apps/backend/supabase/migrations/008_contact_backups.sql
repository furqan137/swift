-- Contact backups: track backup metadata for analytics
-- Actual backup data is stored on-device for privacy and performance
CREATE TABLE IF NOT EXISTS contact_backups (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  contact_count INT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_contact_backups_user ON contact_backups(user_id);
CREATE INDEX idx_contact_backups_created ON contact_backups(created_at);
