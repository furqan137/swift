-- Contacts sync: upsert device contacts to the backend for pagination / backup
-- Upsert key is (user_id, device_contact_id) so re-syncing is idempotent.
--
-- Referenced by: apps/backend/src/services/contacts.service.ts
--   - syncContactsBatch()
--   - getContacts()
--   - getContactCount()

CREATE TABLE IF NOT EXISTS contacts_sync (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_contact_id TEXT NOT NULL,
  full_name TEXT NOT NULL,
  phones TEXT[] NOT NULL DEFAULT '{}',
  emails TEXT[] NOT NULL DEFAULT '{}',
  organization TEXT,
  synced_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),

  -- Idempotent re-sync: same device contact from the same user replaces, doesn't dup
  UNIQUE (user_id, device_contact_id)
);

-- Fast per-user scan (list + count + pagination)
CREATE INDEX IF NOT EXISTS idx_contacts_sync_user ON contacts_sync (user_id);

-- Name index supports the default ORDER BY full_name ASC used in getContacts()
CREATE INDEX IF NOT EXISTS idx_contacts_sync_user_name ON contacts_sync (user_id, full_name);

-- Fresh-first reads (recent syncs)
CREATE INDEX IF NOT EXISTS idx_contacts_sync_user_synced ON contacts_sync (user_id, synced_at DESC);
