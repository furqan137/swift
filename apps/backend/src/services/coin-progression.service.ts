import { supabaseService } from './supabase.service.js';

// ── Tuning constants (single source of truth; mirror on client) ──────────────
// Coins are awarded for REVIEW alone — deleting a photo must never change the
// payout, so the client estimate (badge) and this award stay identical.
// SELECTION_WEIGHT / STORAGE_WEIGHT are zeroed (kept for the client contract).
// If levels feel too fast, drop REVIEW_WEIGHT→0.15.
export const REVIEW_WEIGHT = 0.25;
export const SELECTION_WEIGHT = 0.0;
export const STORAGE_WEIGHT = 0.0;
export const STORAGE_MB_UNIT = 250; // MB that maps to one storage unit
export const COINS_PER_ASSET = 10;
export const MAX_LEVELS = 1000;
export const CHECKPOINT_COIN_MIN = 1;
export const CHECKPOINT_COIN_MAX = 12;

export const CATEGORY_MULTIPLIERS: Record<string, number> = {
  duplicates: 1.15,
  large_videos: 1.20,
  screenshots: 1.00,
  blurry: 0.90,
  similar: 1.05,
  screen_recordings: 1.15,
  other: 1.00,
};

// ── Types ────────────────────────────────────────────────────────────────────

export interface ProgressState {
  totalLifetimeCoins: number;
  maxLifetimeCoins: number;
  currentLevel: number;
  maxLevel: number;
  currentLevelCoins: number;
  coinsNeededForNextLevel: number;
  cleanBarPercent: number;
  beeStage: number;
}

export interface LevelRequirement {
  level: number;
  coinsRequired: number;
  cumulativeCoinsRequired: number;
}

/** Per-category deleted bytes + reviewed item count, keyed by coin category. */
export type CategoryBreakdown = Record<string, { bytes: number; reviewed: number }>;

interface ProgressRow {
  total_photos: number;
  total_videos: number;
  total_assets: number;
  max_lifetime_coins: number;
  total_lifetime_coins: number;
  current_level: number;
  max_level: number;
  current_level_coins: number;
  coins_needed_for_next_level: number;
  clean_bar_percent: number;
  bee_stage: number;
}

const PROGRESS_COLS =
  'total_photos, total_videos, total_assets, max_lifetime_coins, total_lifetime_coins, ' +
  'current_level, max_level, current_level_coins, coins_needed_for_next_level, ' +
  'clean_bar_percent, bee_stage';

// ── Pure math ──────────────────────────────────────────────────────────────

// Single gentle exponent. With the finite pool spread across 1000 levels, the
// old steep segmented curve (^0.75…^1.70) floored every early level to 1 coin.
// 0.48 keeps early levels meaningful and scales with library size while
// preserving sum(levelRequirements) == maxLifetimeCoins. Tunable.
export const LEVEL_CURVE_EXPONENT = 0.48;

function levelExponent(_level: number): number {
  return LEVEL_CURVE_EXPONENT;
}

/**
 * Segmented-curve level requirements. Invariant: sum(coinsRequired) ==
 * maxLifetimeCoins. Fallback: when maxLifetimeCoins < 1000, there are only
 * maxLifetimeCoins levels (each needs ≥1 coin).
 */
export function generateLevelRequirements(maxLifetimeCoins: number): LevelRequirement[] {
  const max = Math.max(0, Math.floor(maxLifetimeCoins));
  const maxLevels = Math.min(MAX_LEVELS, max);
  if (maxLevels <= 0) return [];

  const weights: number[] = [];
  for (let level = 1; level <= maxLevels; level++) {
    weights.push(Math.pow(level, levelExponent(level)));
  }
  const totalWeight = weights.reduce((s, w) => s + w, 0);

  const requirements = weights.map((w) => Math.max(1, Math.round((max * w) / totalWeight)));

  // Absorb rounding drift on the last level; if that would drop it below 1,
  // pull the remainder from earlier levels (still ≥1 each).
  let diff = max - requirements.reduce((s, r) => s + r, 0);
  let i = requirements.length - 1;
  while (diff !== 0 && i >= 0) {
    const next = requirements[i] + diff;
    if (next >= 1) {
      requirements[i] = next;
      diff = 0;
    } else {
      diff = next - 1; // negative remainder rolls to the previous level
      requirements[i] = 1;
      i--;
    }
  }

  let cumulative = 0;
  return requirements.map((coinsRequired, index) => {
    cumulative += coinsRequired;
    return { level: index + 1, coinsRequired, cumulativeCoinsRequired: cumulative };
  });
}

function beeStageForPercent(p: number): number {
  if (p <= 0.20) return 1;
  if (p <= 0.40) return 2;
  if (p <= 0.60) return 3;
  if (p <= 0.80) return 4;
  return 5;
}

/** Derive level/bar/stage from total coins + the user's level table. */
export function deriveProgress(
  totalLifetimeCoins: number,
  maxLifetimeCoins: number,
  reqs: LevelRequirement[]
): ProgressState {
  const base = {
    totalLifetimeCoins,
    maxLifetimeCoins,
  };

  if (reqs.length === 0) {
    return { ...base, currentLevel: 1, maxLevel: 1, currentLevelCoins: 0, coinsNeededForNextLevel: 1, cleanBarPercent: 0, beeStage: 1 };
  }

  const maxLevel = reqs.length;
  const total = Math.min(totalLifetimeCoins, maxLifetimeCoins);
  const lastCumulative = reqs[maxLevel - 1].cumulativeCoinsRequired;

  if (total >= lastCumulative) {
    const need = reqs[maxLevel - 1].coinsRequired;
    return { ...base, currentLevel: maxLevel, maxLevel, currentLevelCoins: need, coinsNeededForNextLevel: need, cleanBarPercent: 1, beeStage: 5 };
  }

  let level = 1;
  for (const r of reqs) {
    if (total < r.cumulativeCoinsRequired) {
      level = r.level;
      break;
    }
  }
  const cumBefore = level > 1 ? reqs[level - 2].cumulativeCoinsRequired : 0;
  const coinsNeeded = reqs[level - 1].coinsRequired;
  const currentLevelCoins = total - cumBefore;
  const pct = coinsNeeded > 0 ? currentLevelCoins / coinsNeeded : 0;
  return { ...base, currentLevel: level, maxLevel, currentLevelCoins, coinsNeededForNextLevel: coinsNeeded, cleanBarPercent: pct, beeStage: beeStageForPercent(pct) };
}

// Reviewed-count-weighted category multiplier. Deliberately NOT byte-weighted:
// the multiplier must not depend on what gets deleted, or the client badge
// estimate and the actual award could diverge.
function categoryMultiplier(breakdown: CategoryBreakdown | undefined): number {
  if (!breakdown) return 1.0;
  const entries = Object.entries(breakdown);
  if (entries.length === 0) return 1.0;

  let weightSum = 0;
  let acc = 0;
  for (const [key, v] of entries) {
    const w = v.reviewed || 0;
    if (w <= 0) continue;
    acc += (CATEGORY_MULTIPLIERS[key] ?? 1.0) * w;
    weightSum += w;
  }
  return weightSum > 0 ? acc / weightSum : 1.0;
}

/**
 * Review-only coin award for one checkpoint. `selectedItemCount` / `deletedBytes`
 * are accepted for telemetry compatibility but do not affect the payout
 * (SELECTION_WEIGHT / STORAGE_WEIGHT are 0) — deleting more never grants coins.
 */
export function computeCheckpointCoins(input: {
  reviewedItemCount: number;
  selectedItemCount: number;
  deletedBytes: number;
  categoryBreakdown?: CategoryBreakdown;
}): number {
  const raw = input.reviewedItemCount * REVIEW_WEIGHT * categoryMultiplier(input.categoryBreakdown);
  const clamped = Math.max(CHECKPOINT_COIN_MIN, Math.min(Math.round(raw), CHECKPOINT_COIN_MAX));
  return clamped;
}

// ── Service ──────────────────────────────────────────────────────────────────

class CoinProgressionService {
  private get db() {
    return supabaseService.getAdminClient();
  }

  private async fetchRow(userId: string): Promise<ProgressRow | null> {
    const { data, error } = await this.db
      .from('user_progress')
      .select(PROGRESS_COLS)
      .eq('user_id', userId)
      .single();
    if (error && error.code === 'PGRST116') return null;
    if (error) {
      console.error('[progress] row fetch error:', error.message);
      throw new Error('Failed to fetch progress');
    }
    return data as unknown as ProgressRow;
  }

  private async fetchRequirements(userId: string): Promise<LevelRequirement[]> {
    const { data, error } = await this.db
      .from('level_requirements')
      .select('level, coins_required, cumulative_coins_required')
      .eq('user_id', userId)
      .order('level', { ascending: true });
    if (error) {
      console.error('[progress] requirements fetch error:', error.message);
      throw new Error('Failed to fetch level requirements');
    }
    return (data ?? []).map((r: any) => ({
      level: r.level,
      coinsRequired: r.coins_required,
      cumulativeCoinsRequired: r.cumulative_coins_required,
    }));
  }

  /** Read the row or create an empty one (max=0) so GET never 404s. */
  private async ensureRow(userId: string): Promise<ProgressRow> {
    const existing = await this.fetchRow(userId);
    if (existing) return existing;

    const { data: inserted } = await this.db
      .from('user_progress')
      .upsert(
        { user_id: userId, updated_at: new Date().toISOString() },
        { onConflict: 'user_id', ignoreDuplicates: true }
      )
      .select(PROGRESS_COLS);

    if (!inserted || inserted.length === 0) {
      return (await this.fetchRow(userId)) as ProgressRow;
    }
    return inserted[0] as unknown as ProgressRow;
  }

  private rowToState(row: ProgressRow): ProgressState {
    return {
      totalLifetimeCoins: row.total_lifetime_coins,
      maxLifetimeCoins: row.max_lifetime_coins,
      currentLevel: row.current_level,
      maxLevel: row.max_level,
      currentLevelCoins: row.current_level_coins,
      coinsNeededForNextLevel: row.coins_needed_for_next_level,
      cleanBarPercent: Number(row.clean_bar_percent),
      beeStage: row.bee_stage,
    };
  }

  /** GET /progress */
  async getProgress(userId: string): Promise<ProgressState> {
    return this.rowToState(await this.ensureRow(userId));
  }

  /**
   * POST /progress/sync — recompute maxLifetimeCoins from the library counts,
   * regenerate level_requirements, preserve total_lifetime_coins, re-derive
   * level/bar/stage. Idempotent.
   */
  async syncLibrary(userId: string, input: { totalPhotos: number; totalVideos: number }): Promise<ProgressState> {
    await this.ensureRow(userId);

    const totalPhotos = Math.max(0, Math.floor(input.totalPhotos));
    const totalVideos = Math.max(0, Math.floor(input.totalVideos));
    const totalAssets = totalPhotos + totalVideos;
    const maxLifetimeCoins = totalAssets * COINS_PER_ASSET;

    // A 0-count sync is garbage (permission/timing) — never let it clamp the
    // total to 0 or drop the level table. Lifetime coins are monotonic.
    if (maxLifetimeCoins <= 0) {
      return this.rowToState(await this.ensureRow(userId));
    }

    const reqs = generateLevelRequirements(maxLifetimeCoins);

    // Replace the level table.
    await this.db.from('level_requirements').delete().eq('user_id', userId);
    if (reqs.length > 0) {
      const now = new Date().toISOString();
      const rows = reqs.map((r) => ({
        user_id: userId,
        level: r.level,
        coins_required: r.coinsRequired,
        cumulative_coins_required: r.cumulativeCoinsRequired,
        updated_at: now,
      }));
      // Chunk to stay well under any payload limits.
      for (let i = 0; i < rows.length; i += 500) {
        await this.db.from('level_requirements').insert(rows.slice(i, i + 500));
      }
    }

    const row = await this.fetchRow(userId);
    const preservedTotal = Math.min(row?.total_lifetime_coins ?? 0, maxLifetimeCoins);
    const state = deriveProgress(preservedTotal, maxLifetimeCoins, reqs);

    await this.db
      .from('user_progress')
      .update({
        total_photos: totalPhotos,
        total_videos: totalVideos,
        total_assets: totalAssets,
        max_lifetime_coins: maxLifetimeCoins,
        total_lifetime_coins: preservedTotal,
        current_level: state.currentLevel,
        max_level: state.maxLevel,
        current_level_coins: state.currentLevelCoins,
        coins_needed_for_next_level: state.coinsNeededForNextLevel,
        clean_bar_percent: state.cleanBarPercent,
        bee_stage: state.beeStage,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);

    return state;
  }

  /** POST /progress/checkpoint — idempotent, immediate coin award. */
  async recordCheckpoint(input: {
    userId: string;
    eventId: string;
    planId: string;
    taskId: string;
    checkpointId: string;
    reviewedItemCount: number;
    selectedItemCount: number;
    deletedBytes: number;
    categoryBreakdown?: CategoryBreakdown;
    // Client's authoritative derived progress (display source of truth). When
    // provided, persisted directly so the DB's clean bar % + level always
    // match what the user sees, instead of the server re-deriving from a
    // possibly-stale pool/ladder.
    clientMaxLifetimeCoins?: number;
    clientTotalLifetimeCoins?: number;
    clientCurrentLevel?: number;
    clientMaxLevel?: number;
    clientCurrentLevelCoins?: number;
    clientCoinsNeededForNextLevel?: number;
    clientCleanBarPercent?: number;
    clientBeeStage?: number;
  }): Promise<ProgressState> {
    const row = await this.ensureRow(input.userId);
    const reqs = await this.fetchRequirements(input.userId);

    const max = row.max_lifetime_coins;
    const totalBefore = row.total_lifetime_coins;

    const rawCoins = computeCheckpointCoins(input);
    // When the pool isn't synced yet (max == 0) don't cap to 0 — that would
    // silently zero the award and the idempotent event would make it
    // permanent. A later /sync preserves the accrued total.
    const remaining = max > 0 ? Math.max(0, max - totalBefore) : rawCoins;
    const coinsEarned = Math.min(rawCoins, remaining);
    const totalAfter = totalBefore + coinsEarned;

    const stateAfter = deriveProgress(totalAfter, max, reqs);

    // Idempotency gate — INSERT ... ON CONFLICT DO NOTHING.
    const { data: insertedEvent } = await this.db
      .from('coin_events')
      .upsert(
        {
          user_id: input.userId,
          event_id: input.eventId,
          plan_id: input.planId,
          task_id: input.taskId,
          checkpoint_id: input.checkpointId,
          event_type: 'checkpoint',
          reviewed_item_count: input.reviewedItemCount,
          selected_item_count: input.selectedItemCount,
          deleted_bytes: input.deletedBytes,
          category_breakdown_json: input.categoryBreakdown ?? null,
          coins_earned: coinsEarned,
          total_lifetime_coins_before: totalBefore,
          total_lifetime_coins_after: totalAfter,
          level_before: row.current_level,
          level_after: stateAfter.currentLevel,
          bee_stage_before: row.bee_stage,
          bee_stage_after: stateAfter.beeStage,
        },
        { onConflict: 'user_id,event_id', ignoreDuplicates: true }
      )
      .select('id');

    if (!insertedEvent || insertedEvent.length === 0) {
      // Duplicate award (retry / double-tap / offline replay) — no-op.
      return this.rowToState(row);
    }

    // Persist the client's authoritative snapshot when provided (so the DB's
    // clean bar % + level match the displayed values exactly); otherwise fall
    // back to the server-derived state.
    const persisted: ProgressState = {
      totalLifetimeCoins:
        input.clientTotalLifetimeCoins && input.clientTotalLifetimeCoins > 0
          ? input.clientTotalLifetimeCoins
          : totalAfter,
      maxLifetimeCoins:
        input.clientMaxLifetimeCoins && input.clientMaxLifetimeCoins > 0
          ? input.clientMaxLifetimeCoins
          : max,
      currentLevel: input.clientCurrentLevel ?? stateAfter.currentLevel,
      maxLevel: input.clientMaxLevel ?? stateAfter.maxLevel,
      currentLevelCoins: input.clientCurrentLevelCoins ?? stateAfter.currentLevelCoins,
      coinsNeededForNextLevel:
        input.clientCoinsNeededForNextLevel ?? stateAfter.coinsNeededForNextLevel,
      cleanBarPercent: input.clientCleanBarPercent ?? stateAfter.cleanBarPercent,
      beeStage: input.clientBeeStage ?? stateAfter.beeStage,
    };

    await this.persistState(input.userId, persisted);
    return persisted;
  }

  /** Persist a full progress snapshot (incl. pool) to user_progress. */
  private async persistState(userId: string, state: ProgressState) {
    await this.db
      .from('user_progress')
      .update({
        total_lifetime_coins: state.totalLifetimeCoins,
        max_lifetime_coins: state.maxLifetimeCoins,
        current_level: state.currentLevel,
        max_level: state.maxLevel,
        current_level_coins: state.currentLevelCoins,
        coins_needed_for_next_level: state.coinsNeededForNextLevel,
        clean_bar_percent: state.cleanBarPercent,
        bee_stage: state.beeStage,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId);
  }
}

export const coinProgressionService = new CoinProgressionService();
