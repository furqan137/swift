import { supabaseService } from './supabase.service.js';

// ── Types ────────────────────────────────────────────────────────────────────

export interface ActiveCleanupTask {
  taskNumber: number;
  taskTitle: string;
  taskType: string;
  category: string;
  estimatedMB: number;
  estimatedCoins: number;
  level: number;
  status: string;
  generatedAt: string;
}

export interface CompletedCleanupTask {
  taskNumber: number;
  taskTitle: string;
  taskType: string;
  category: string;
  mbReviewed: number;
  coinsEarned: number;
  levelAtCompletion: number;
  assetCount: number;
  completedAt: string;
}

/** Display snapshot of the active task the client generated. */
export interface ActiveTaskInput {
  taskNumber?: number;
  taskTitle: string;
  taskType: string;
  category: string;
  estimatedMB: number;
  estimatedCoins: number;
  level: number;
}

/** Outcome of a finished guided session. */
export interface CompleteTaskInput {
  taskNumber?: number;
  taskTitle: string;
  taskType: string;
  category: string;
  mbReviewed: number;
  coinsEarned: number;
  levelAtCompletion: number;
  assetCount: number;
}

interface ActiveRow {
  task_number: number;
  task_title: string | null;
  task_type: string | null;
  category: string | null;
  estimated_mb: number | string;
  estimated_coins: number;
  level: number;
  status: string;
  generated_at: string;
}

interface CompletedRow {
  task_number: number;
  task_title: string | null;
  task_type: string | null;
  category: string | null;
  mb_reviewed: number | string;
  coins_earned: number;
  level_at_completion: number;
  asset_count: number;
  completed_at: string;
}

const ACTIVE_COLS =
  'task_number, task_title, task_type, category, estimated_mb, estimated_coins, level, status, generated_at';
const COMPLETED_COLS =
  'task_number, task_title, task_type, category, mb_reviewed, coins_earned, level_at_completion, asset_count, completed_at';

// ── Service ──────────────────────────────────────────────────────────────────

class CleanupTaskService {
  private get db() {
    return supabaseService.getAdminClient();
  }

  private rowToActive(row: ActiveRow): ActiveCleanupTask {
    return {
      taskNumber: row.task_number,
      taskTitle: row.task_title ?? '',
      taskType: row.task_type ?? '',
      category: row.category ?? '',
      estimatedMB: Number(row.estimated_mb),
      estimatedCoins: row.estimated_coins,
      level: row.level,
      status: row.status,
      generatedAt: row.generated_at,
    };
  }

  private rowToCompleted(row: CompletedRow): CompletedCleanupTask {
    return {
      taskNumber: row.task_number,
      taskTitle: row.task_title ?? '',
      taskType: row.task_type ?? '',
      category: row.category ?? '',
      mbReviewed: Number(row.mb_reviewed),
      coinsEarned: row.coins_earned,
      levelAtCompletion: row.level_at_completion,
      assetCount: row.asset_count,
      completedAt: row.completed_at,
    };
  }

  /** Highest completed task_number + 1 (1 when the user has no history). */
  private async nextActiveNumber(userId: string): Promise<number> {
    const { data, error } = await this.db
      .from('completed_cleanup_tasks')
      .select('task_number')
      .eq('user_id', userId)
      .order('task_number', { ascending: false })
      .limit(1);
    if (error) {
      console.error('[cleanup-task] nextActiveNumber error:', error.message);
      throw new Error('Failed to compute task number');
    }
    const max = data && data.length > 0 ? data[0].task_number : 0;
    return max + 1;
  }

  /** GET /cleanup-task/active */
  async getActiveTask(userId: string): Promise<ActiveCleanupTask | null> {
    const { data, error } = await this.db
      .from('active_cleanup_task')
      .select(ACTIVE_COLS)
      .eq('user_id', userId)
      .single();
    if (error && error.code === 'PGRST116') return null;
    if (error) {
      console.error('[cleanup-task] getActiveTask error:', error.message);
      throw new Error('Failed to fetch active task');
    }
    return this.rowToActive(data as unknown as ActiveRow);
  }

  /**
   * POST /cleanup-task/active — upsert the single active task. The backend is
   * authoritative for task_number: it stays the same until a completion is
   * recorded (which raises max(completed.task_number)).
   */
  async upsertActiveTask(userId: string, input: ActiveTaskInput): Promise<ActiveCleanupTask> {
    // Client owns the rolling number; fall back to a server-computed one only
    // when it isn't supplied.
    const taskNumber =
      input.taskNumber && input.taskNumber > 0 ? input.taskNumber : await this.nextActiveNumber(userId);
    const now = new Date().toISOString();
    const { data, error } = await this.db
      .from('active_cleanup_task')
      .upsert(
        {
          user_id: userId,
          task_number: taskNumber,
          task_title: input.taskTitle,
          task_type: input.taskType,
          category: input.category,
          estimated_mb: input.estimatedMB,
          estimated_coins: input.estimatedCoins,
          level: input.level,
          status: 'active',
          generated_at: now,
          updated_at: now,
        },
        { onConflict: 'user_id' }
      )
      .select(ACTIVE_COLS)
      .single();
    if (error) {
      console.error('[cleanup-task] upsertActiveTask error:', error.message);
      throw new Error('Failed to persist active task');
    }
    return this.rowToActive(data as unknown as ActiveRow);
  }

  /**
   * POST /cleanup-task/complete — store the finished task in history (reusing
   * the active task's number), then clear the active row. The next
   * upsertActiveTask will yield number+1.
   */
  async completeTask(userId: string, input: CompleteTaskInput): Promise<CompletedCleanupTask> {
    const active = await this.getActiveTask(userId);
    const taskNumber =
      input.taskNumber && input.taskNumber > 0
        ? input.taskNumber
        : active
          ? active.taskNumber
          : await this.nextActiveNumber(userId);

    const { data, error } = await this.db
      .from('completed_cleanup_tasks')
      .insert({
        user_id: userId,
        task_number: taskNumber,
        task_title: input.taskTitle,
        task_type: input.taskType,
        category: input.category,
        mb_reviewed: input.mbReviewed,
        coins_earned: input.coinsEarned,
        level_at_completion: input.levelAtCompletion,
        asset_count: input.assetCount,
      })
      .select(COMPLETED_COLS)
      .single();
    if (error) {
      console.error('[cleanup-task] completeTask error:', error.message);
      throw new Error('Failed to record completed task');
    }

    await this.db.from('active_cleanup_task').delete().eq('user_id', userId);

    return this.rowToCompleted(data as unknown as CompletedRow);
  }

  /** GET /cleanup-task/history — flat, newest first. Client groups by day. */
  async getHistory(userId: string, limit = 500): Promise<CompletedCleanupTask[]> {
    const { data, error } = await this.db
      .from('completed_cleanup_tasks')
      .select(COMPLETED_COLS)
      .eq('user_id', userId)
      .order('completed_at', { ascending: false })
      .limit(limit);
    if (error) {
      console.error('[cleanup-task] getHistory error:', error.message);
      throw new Error('Failed to fetch cleanup history');
    }
    return (data ?? []).map((r) => this.rowToCompleted(r as unknown as CompletedRow));
  }
}

export const cleanupTaskService = new CleanupTaskService();
