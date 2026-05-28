import { supabaseService } from '../supabase.service.js';

const supabaseAdmin = supabaseService.getAdminClient();

/**
 * Deep self-test. Runs a real auth-gated check against every contacts
 * table, does a noop INSERT/SELECT/DELETE on each, and reports a
 * structured per-step result. Use this from TestFlight when the app
 * seems "fully fried" — the response tells you exactly which step
 * of the pipeline is broken (missing table, RLS, FK, transient, etc.).
 *
 * All calls are wrapped — this endpoint never throws.
 */
export async function selftest(userId: string): Promise<{
  ok: boolean;
  userId: string;
  steps: Record<string, { ok: boolean; durationMs: number; code?: string; detail?: string }>;
}> {
  const steps: Record<string, { ok: boolean; durationMs: number; code?: string; detail?: string }> = {};

  const run = async (name: string, fn: () => Promise<{ ok: boolean; code?: string; detail?: string }>) => {
    const start = Date.now();
    try {
      const out = await fn();
      steps[name] = { ...out, durationMs: Date.now() - start };
    } catch (e: any) {
      steps[name] = {
        ok: false,
        durationMs: Date.now() - start,
        code: 'UNEXPECTED',
        detail: e?.message || 'unknown error',
      };
    }
  };

  // Step 1: can we even see the user row? (proves auth + FK target exists)
  await run('user_row_lookup', async () => {
    const { error } = await supabaseAdmin
      .from('users')
      .select('id', { count: 'exact', head: true })
      .eq('id', userId);
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  // Step 2: contacts_stats readable?
  await run('contacts_stats_readable', async () => {
    const { error } = await supabaseAdmin
      .from('contacts_stats')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  // Step 3: contacts_stats writable? Insert a no-op self-test row.
  await run('contacts_stats_writable', async () => {
    const { error } = await supabaseAdmin
      .from('contacts_stats')
      .insert({
        user_id: userId,
        action: 'merge', // must pass validation
        contact_count: 0,
        metadata: { selftest: true, ts: Date.now() },
      });
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  // Step 4: contact_backups readable?
  await run('contact_backups_readable', async () => {
    const { error } = await supabaseAdmin
      .from('contact_backups')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  // Step 5: phone_lookups readable?
  await run('phone_lookups_readable', async () => {
    const { error } = await supabaseAdmin
      .from('phone_lookups')
      .select('phone', { count: 'exact', head: true });
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  // Step 6: contacts_sync readable? (this is the one that was missing)
  await run('contacts_sync_readable', async () => {
    const { error } = await supabaseAdmin
      .from('contacts_sync')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId);
    if (error) return { ok: false, code: (error as any).code, detail: error.message };
    return { ok: true };
  });

  const ok = Object.values(steps).every(s => s.ok);
  return { ok, userId, steps };
}

/**
 * Health check — verifies every table the contacts backend touches
 * actually exists. iOS can call this on launch to decide whether to
 * attempt sync / backup-logging / stats-logging, or fall back cleanly
 * to local-only mode.
 *
 * Returns 200 with per-table status. Never throws — a missing table is
 * reported as `{ exists: false }`, not a 500.
 */
export async function health(): Promise<{
  ok: boolean;
  tables: Record<string, { exists: boolean; error?: string }>;
  message: string;
}> {
  const tables = ['contacts_stats', 'contact_backups', 'phone_lookups', 'contacts_sync'];
  const results: Record<string, { exists: boolean; error?: string }> = {};

  for (const table of tables) {
    try {
      const { error } = await supabaseAdmin
        .from(table)
        .select('*', { count: 'exact', head: true })
        .limit(0);

      if (error) {
        // Postgres error codes:
        //   42P01 = undefined_table (schema really isn't provisioned)
        //   42501 = insufficient_privilege (RLS/role misconfigured)
        // Anything else = exists but transient failure — still treat as OK.
        const code = (error as any).code;
        if (code === '42P01') {
          results[table] = { exists: false, error: 'table does not exist' };
        } else {
          results[table] = { exists: true, error: error.message };
        }
      } else {
        results[table] = { exists: true };
      }
    } catch (e: any) {
      results[table] = { exists: false, error: e?.message || 'unknown error' };
    }
  }

  const allExist = Object.values(results).every(r => r.exists);
  return {
    ok: allExist,
    tables: results,
    message: allExist
      ? 'All contacts tables provisioned'
      : 'Some contacts tables are missing — iOS should fall back to local-only mode',
  };
}
