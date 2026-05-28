import { supabaseService } from '../supabase.service.js';
import type { BackupMetadata } from './types.js';

const supabaseAdmin = supabaseService.getAdminClient();

/**
 * Log a backup event (metadata only — actual data stored on device).
 * **Never throws** — iOS writes the backup to local Documents regardless
 * of whether the metadata record makes it to the server. Returns a
 * placeholder record with code=BACKUP_TABLE_MISSING when the table
 * isn't provisioned so the client can detect degraded mode.
 */
export async function logBackup(userId: string, contactCount: number): Promise<BackupMetadata & { logged: boolean; code?: string }> {
  try {
    const { data, error } = await supabaseAdmin
      .from('contact_backups')
      .insert({
        user_id: userId,
        contact_count: contactCount,
      })
      .select('id, contact_count, created_at')
      .single();

    if (error) {
      const pgCode = (error as any).code;
      console.warn(`[contacts/backups] Insert skipped (${pgCode}):`, error.message);
      return {
        id: `local-${Date.now()}`,
        contactCount,
        createdAt: new Date().toISOString(),
        logged: false,
        code: pgCode === '42P01' ? 'BACKUP_TABLE_MISSING' : (pgCode || 'BACKUP_INSERT_FAILED'),
      };
    }

    return {
      id: data.id,
      contactCount: data.contact_count,
      createdAt: data.created_at,
      logged: true,
    };
  } catch (e: any) {
    console.error('[contacts/backups] Unexpected error:', e?.message || e);
    return {
      id: `local-${Date.now()}`,
      contactCount,
      createdAt: new Date().toISOString(),
      logged: false,
      code: 'BACKUP_UNEXPECTED',
    };
  }
}

/**
 * List all backups for a user (newest first). **Never throws** — returns
 * an empty list if the table is missing so iOS can fall back to the
 * local index.
 */
export async function listBackups(userId: string): Promise<{ backups: BackupMetadata[]; code?: string }> {
  try {
    const { data, error } = await supabaseAdmin
      .from('contact_backups')
      .select('id, contact_count, created_at')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(100);

    if (error) {
      const pgCode = (error as any).code;
      console.warn(`[contacts/backups] List skipped (${pgCode}):`, error.message);
      return {
        backups: [],
        code: pgCode === '42P01' ? 'BACKUP_TABLE_MISSING' : (pgCode || 'BACKUP_LIST_FAILED'),
      };
    }

    return {
      backups: (data || []).map(b => ({
        id: b.id,
        contactCount: b.contact_count,
        createdAt: b.created_at,
      })),
    };
  } catch (e: any) {
    console.error('[contacts/backups] Unexpected error:', e?.message || e);
    return { backups: [], code: 'BACKUP_UNEXPECTED' };
  }
}

/**
 * Delete a backup record. **Never throws** — iOS has already deleted
 * the local file by the time this is called; a missing server record
 * is fine.
 */
export async function deleteBackup(userId: string, backupId: string): Promise<{ deleted: boolean; code?: string }> {
  try {
    const { error } = await supabaseAdmin
      .from('contact_backups')
      .delete()
      .eq('id', backupId)
      .eq('user_id', userId);

    if (error) {
      const pgCode = (error as any).code;
      console.warn(`[contacts/backups] Delete skipped (${pgCode}):`, error.message);
      return {
        deleted: false,
        code: pgCode === '42P01' ? 'BACKUP_TABLE_MISSING' : (pgCode || 'BACKUP_DELETE_FAILED'),
      };
    }
    return { deleted: true };
  } catch (e: any) {
    console.error('[contacts/backups] Unexpected error:', e?.message || e);
    return { deleted: false, code: 'BACKUP_UNEXPECTED' };
  }
}
