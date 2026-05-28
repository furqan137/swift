import { supabaseService } from './supabase.service.js';

// MARK: - Quota Service
//
// Server-side deletion quota enforcement. Free users get 5 free
// photo deletes per day + can watch up to 15 rewarded ads for
// +25 deletes each. Pro subscribers have unlimited deletes.
//
// All operations are atomic (Postgres functions) to prevent
// client-side race conditions.

interface UserQuota {
  id: string;
  user_id: string;
  free_photo_deletes_remaining: number;
  free_video_deletes_remaining: number;
  free_contact_merges_remaining: number;
  free_email_deletes_remaining: number;
  free_compress_actions_remaining: number;
  ads_watched_today: number;
  total_deletes_today: number;
  total_contact_merges_today: number;
  total_email_deletes_today: number;
  total_compress_actions_today: number;
  quota_reset_at: string;
  is_pro: boolean;
  pro_expires_at: string | null;
  created_at: string;
  updated_at: string;
}

const VALID_SECTIONS = ['photos', 'videos', 'contacts', 'email', 'compress'] as const;
type Section = typeof VALID_SECTIONS[number];

const AD_REWARD_AMOUNTS: Record<Section, number> = {
  photos: 25,
  videos: 15,
  contacts: 0,
  email: 15,
  compress: 1,
};

class QuotaService {
  private get db() {
    return supabaseService.getAdminClient();
  }

  /**
   * Check and auto-reset the user's quota. Creates the row on first call.
   */
  async checkQuota(userId: string): Promise<UserQuota> {
    // Upsert: create row if it doesn't exist
    const { error: upsertError } = await this.db
      .from('user_quotas')
      .upsert(
        { user_id: userId },
        { onConflict: 'user_id', ignoreDuplicates: true }
      );

    if (upsertError) {
      console.error('[quota] Upsert error:', upsertError);
    }

    // Check if quota needs resetting
    const { data: existing } = await this.db
      .from('user_quotas')
      .select('*')
      .eq('user_id', userId)
      .single();

    if (existing && new Date(existing.quota_reset_at) < new Date()) {
      // Reset expired quota — resets all section columns
      const { data: reset, error: resetError } = await this.db
        .from('user_quotas')
        .update({
          free_photo_deletes_remaining: 5,
          free_video_deletes_remaining: 1,
          free_contact_merges_remaining: 2,
          free_email_deletes_remaining: 5,
          free_compress_actions_remaining: 3,
          ads_watched_today: 0,
          total_deletes_today: 0,
          total_contact_merges_today: 0,
          total_email_deletes_today: 0,
          total_compress_actions_today: 0,
          quota_reset_at: this.nextMidnightUTC(),
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', userId)
        .select()
        .single();

      if (resetError) throw new Error(`Quota reset failed: ${resetError.message}`);
      return reset as UserQuota;
    }

    if (!existing) throw new Error('Failed to create or fetch user quota');
    return existing as UserQuota;
  }

  /**
   * Atomically consume free deletes.
   */
  async consumeFreeDeletes(userId: string, count: number): Promise<UserQuota> {
    if (count <= 0) throw new Error('count must be positive');

    const { data: current } = await this.db
      .from('user_quotas')
      .select('free_photo_deletes_remaining')
      .eq('user_id', userId)
      .single();

    if (!current) throw new Error('User quota not found');

    const newRemaining = Math.max(0, current.free_photo_deletes_remaining - count);

    // Use RPC for atomic increment of total_deletes_today
    const { data: updated, error: rpcError } = await this.db.rpc(
      'consume_free_deletes',
      { p_user_id: userId, p_count: count }
    );

    if (rpcError) {
      // Fallback: do a non-atomic update if the RPC function isn't deployed yet
      console.error('[quota] RPC fallback:', rpcError.message);
      const { data: fallback, error: fbError } = await this.db
        .from('user_quotas')
        .update({
          free_photo_deletes_remaining: newRemaining,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', userId)
        .select()
        .single();

      if (fbError) throw new Error(`Consume failed: ${fbError.message}`);
      return fallback as UserQuota;
    }

    return updated as UserQuota;
  }

  /**
   * Grant +25 deletes after a rewarded ad. Enforces 15 ads/day cap.
   */
  async grantAdReward(userId: string): Promise<{ quota: UserQuota; deletesGranted: number }> {
    // Try RPC first (atomic)
    const { data: rpcResult, error: rpcError } = await this.db.rpc(
      'grant_ad_reward',
      { p_user_id: userId }
    );

    if (rpcError) {
      // If the RPC error is about the ad cap, throw a specific error
      if (rpcError.message.includes('Daily ad cap reached')) {
        const err = new Error('Daily ad cap reached') as any;
        err.status = 429;
        throw err;
      }

      // Fallback: non-atomic update if RPC not deployed
      console.error('[quota] grant_ad_reward RPC fallback:', rpcError.message);

      const { data: current } = await this.db
        .from('user_quotas')
        .select('*')
        .eq('user_id', userId)
        .single();

      if (!current) throw new Error('User quota not found');
      if (current.ads_watched_today >= 15) {
        const err = new Error('Daily ad cap reached') as any;
        err.status = 429;
        throw err;
      }

      const { data: updated, error: updateErr } = await this.db
        .from('user_quotas')
        .update({
          free_photo_deletes_remaining: current.free_photo_deletes_remaining + 25,
          ads_watched_today: current.ads_watched_today + 1,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', userId)
        .select()
        .single();

      if (updateErr) throw new Error(`Grant failed: ${updateErr.message}`);
      return { quota: updated as UserQuota, deletesGranted: 25 };
    }

    return { quota: rpcResult as UserQuota, deletesGranted: 25 };
  }

  /**
   * Consume quota for a specific section. Calls consume_section_quota RPC.
   */
  async consumeSectionQuota(userId: string, section: string, count: number): Promise<UserQuota> {
    if (count <= 0) throw new Error('count must be positive');
    if (!VALID_SECTIONS.includes(section as Section)) {
      throw new Error(`Invalid section: ${section}`);
    }

    const { data, error } = await this.db.rpc(
      'consume_section_quota',
      { p_user_id: userId, p_section: section, p_count: count }
    );

    if (error) {
      console.error('[quota] consume_section_quota RPC error:', error.message);
      throw new Error(`Consume failed: ${error.message}`);
    }

    return data as UserQuota;
  }

  /**
   * Grant ad reward for a specific section. Returns reward amount.
   * Rejects 'contacts' section (no ads allowed). Enforces 15/day global cap.
   */
  async grantSectionAdReward(userId: string, section: string): Promise<{ quota: UserQuota; rewardAmount: number }> {
    if (!VALID_SECTIONS.includes(section as Section)) {
      throw new Error(`Invalid section: ${section}`);
    }
    if (section === 'contacts') {
      throw new Error('Contacts section does not support ad rewards');
    }

    const rewardAmount = AD_REWARD_AMOUNTS[section as Section];

    const { data, error } = await this.db.rpc(
      'grant_section_ad_reward',
      { p_user_id: userId, p_section: section }
    );

    if (error) {
      if (error.message.includes('Daily ad cap reached')) {
        const err = new Error('Daily ad cap reached') as any;
        err.status = 429;
        throw err;
      }
      console.error('[quota] grant_section_ad_reward RPC error:', error.message);
      throw new Error(`Grant failed: ${error.message}`);
    }

    return { quota: data as UserQuota, rewardAmount };
  }

  private nextMidnightUTC(): string {
    const now = new Date();
    const tomorrow = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate() + 1,
      0, 0, 0, 0
    ));
    return tomorrow.toISOString();
  }
}

export const quotaService = new QuotaService();
