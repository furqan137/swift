import { supabaseService } from '../supabase.service.js';

const supabaseAdmin = supabaseService.getAdminClient();

/**
 * Sync a batch of contacts from the device to the server.
 * Upserts by (user_id, device_contact_id) so re-syncing is idempotent.
 */
export async function syncContactsBatch(
  userId: string,
  contacts: { deviceContactId: string; fullName: string; phones: string[]; emails: string[]; organization?: string }[]
): Promise<{ synced: number }> {
  if (!contacts.length) return { synced: 0 };

  const rows = contacts.map(c => ({
    user_id: userId,
    device_contact_id: c.deviceContactId,
    full_name: c.fullName,
    phones: c.phones,
    emails: c.emails,
    organization: c.organization || null,
    synced_at: new Date().toISOString(),
  }));

  const { error } = await supabaseAdmin
    .from('contacts_sync')
    .upsert(rows, { onConflict: 'user_id,device_contact_id' });

  if (error) {
    console.error('[contacts/sync] Upsert error:', error.message);
    throw new Error('Failed to sync contacts batch');
  }

  return { synced: rows.length };
}

/**
 * Get paginated contacts for a user.
 * @param page 1-indexed page number
 * @param pageSize contacts per page (max 500)
 */
export async function getContacts(
  userId: string,
  page: number,
  pageSize: number
): Promise<{ contacts: any[]; page: number; pageSize: number; total: number; totalPages: number }> {
  const safePageSize = Math.min(Math.max(1, pageSize), 500);
  const safePage = Math.max(1, page);
  const offset = (safePage - 1) * safePageSize;

  // Get total count
  const { count, error: countError } = await supabaseAdmin
    .from('contacts_sync')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId);

  if (countError) {
    console.error('[contacts/sync] Count error:', countError.message);
    throw new Error('Failed to count contacts');
  }

  const total = count || 0;
  const totalPages = Math.ceil(total / safePageSize);

  // Get page
  const { data, error } = await supabaseAdmin
    .from('contacts_sync')
    .select('device_contact_id, full_name, phones, emails, organization, synced_at')
    .eq('user_id', userId)
    .order('full_name', { ascending: true })
    .range(offset, offset + safePageSize - 1);

  if (error) {
    console.error('[contacts/sync] Query error:', error.message);
    throw new Error('Failed to fetch contacts');
  }

  return {
    contacts: (data || []).map(c => ({
      deviceContactId: c.device_contact_id,
      fullName: c.full_name,
      phones: c.phones,
      emails: c.emails,
      organization: c.organization,
      syncedAt: c.synced_at,
    })),
    page: safePage,
    pageSize: safePageSize,
    total,
    totalPages,
  };
}

/**
 * Get total synced contact count for a user.
 */
export async function getContactCount(userId: string): Promise<{ total: number }> {
  const { count, error } = await supabaseAdmin
    .from('contacts_sync')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId);

  if (error) {
    console.error('[contacts/sync] Count error:', error.message);
    throw new Error('Failed to count contacts');
  }

  return { total: count || 0 };
}
