import { supabaseService } from '../supabase.service.js';
import type { StatsSummary } from './types.js';

const supabaseAdmin = supabaseService.getAdminClient();

/**
 * Log a contact cleanup action (merge, delete, export, backup, restore).
 *
 * **Never throws.** iOS calls this fire-and-forget from `StatsService` —
 * it must never surface as a 5xx because the user is doing real work
 * locally and a stats-log failure shouldn't block anything. Returns a
 * result object so the controller can still report structured status
 * back to the client for observability.
 */
export async function logAction(
  userId: string,
  action: string,
  contactCount?: number,
  duplicateGroupsMerged?: number | null,
  metadata?: any
): Promise<{ logged: boolean; reason?: string; code?: string }> {
  const validActions = ['merge', 'delete', 'export', 'backup', 'restore'];
  if (!validActions.includes(action)) {
    return {
      logged: false,
      reason: `invalid action (must be one of: ${validActions.join(', ')})`,
      code: 'INVALID_ACTION',
    };
  }

  try {
    const { error } = await supabaseAdmin.from('contacts_stats').insert({
      user_id: userId,
      action,
      contact_count: contactCount || 1,
      duplicate_groups_merged: duplicateGroupsMerged || null,
      metadata: metadata || null,
    });

    if (error) {
      const pgCode = (error as any).code;
      // Table missing (42P01) — iOS should still see success because
      // the core contacts action already happened on the device.
      if (pgCode === '42P01') {
        console.warn(`[contacts/stats] Table missing (skipped): ${action}`);
        return { logged: false, reason: 'contacts_stats table missing', code: 'STATS_TABLE_MISSING' };
      }
      // RLS / permissions (42501)
      if (pgCode === '42501') {
        console.warn(`[contacts/stats] RLS denied (skipped): ${action}`);
        return { logged: false, reason: 'RLS policy denied insert', code: 'STATS_RLS_DENIED' };
      }
      // Foreign-key / no-matching-user row (23503)
      if (pgCode === '23503') {
        console.warn(`[contacts/stats] User row missing (skipped): ${userId}`);
        return { logged: false, reason: 'user row does not exist', code: 'STATS_USER_MISSING' };
      }
      console.error('[contacts/stats] Insert error:', error.message, 'code:', pgCode);
      return { logged: false, reason: error.message, code: pgCode || 'STATS_INSERT_FAILED' };
    }

    console.log(`[contacts/stats] Logged: ${action} × ${contactCount || 1}`);
    return { logged: true };
  } catch (e: any) {
    // Network / timeout / driver error — still never throw
    console.error('[contacts/stats] Unexpected error:', e?.message || e);
    return { logged: false, reason: e?.message || 'unknown error', code: 'STATS_UNEXPECTED' };
  }
}

/**
 * Get aggregated cleanup stats for a user.
 */
export async function getStats(userId: string): Promise<StatsSummary> {
  // Use Supabase RPC or fetch all rows — no limit, so totals are accurate for any user
  const { data, error } = await supabaseAdmin
    .from('contacts_stats')
    .select('action, contact_count, created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false });

  if (error) {
    console.error('[contacts/stats] Query error:', error.message);
    throw new Error('Failed to fetch stats');
  }

  const stats = data || [];
  const totalMerged = stats.filter(s => s.action === 'merge').reduce((sum: number, s: any) => sum + (s.contact_count || 0), 0);
  const totalDeleted = stats.filter(s => s.action === 'delete').reduce((sum: number, s: any) => sum + (s.contact_count || 0), 0);
  const totalExported = stats.filter(s => s.action === 'export').reduce((sum: number, s: any) => sum + (s.contact_count || 0), 0);
  const totalBackups = stats.filter(s => s.action === 'backup').length;
  const totalRestored = stats.filter(s => s.action === 'restore').reduce((sum: number, s: any) => sum + (s.contact_count || 0), 0);

  return {
    totalMerged,
    totalDeleted,
    totalExported,
    totalBackups,
    totalRestored,
    recentActions: stats.slice(0, 20).map(s => ({
      action: s.action,
      contactCount: s.contact_count,
      createdAt: s.created_at,
    })),
  };
}
