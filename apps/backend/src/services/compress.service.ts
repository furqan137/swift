import { supabaseService } from './supabase.service.js';

interface LogCompressionInput {
  userId: string;
  assetId: string;
  originalBytes: number;
  compressedBytes: number;
  compressionLevel: string;
  codec?: string;
  durationSeconds?: number;
  compressionTimeSeconds?: number;
  resolution?: string;
  success?: boolean;
  errorMessage?: string;
  deviceModel?: string;
  osVersion?: string;
}

interface CompressionSummary {
  totalCompressed: number;
  totalBytesSaved: number;
  recentCompressions: {
    assetId: string;
    originalBytes: number;
    compressedBytes: number;
    level: string;
    savedBytes: number;
    createdAt: string;
  }[];
}

class CompressService {
  async logStats(input: LogCompressionInput): Promise<{ logged: true }> {
    const db = supabaseService.getAdminClient();

    const { error } = await db.from('compression_stats').insert({
      user_id: input.userId,
      asset_id: input.assetId,
      original_bytes: input.originalBytes,
      compressed_bytes: input.compressedBytes,
      compression_level: input.compressionLevel,
      // Don't silently default photo entries to a video codec — preserves
      // analytics fidelity. Frontend always sends `codec` for both paths;
      // store null when truly absent so it's distinguishable.
      codec: input.codec ?? null,
      duration_seconds: input.durationSeconds || null,
      compression_time_seconds: input.compressionTimeSeconds || null,
      resolution: input.resolution || null,
      success: input.success ?? true,
      error_message: input.errorMessage || null,
      device_model: input.deviceModel || null,
      os_version: input.osVersion || null,
    });

    if (error) {
      console.error('[compress/stats] Insert error:', error.message);
      throw new Error('Failed to log compression stats');
    }

    console.log(`[compress/stats] Logged: ${input.compressionLevel} ${input.originalBytes} → ${input.compressedBytes} (${input.success !== false ? 'ok' : 'fail'})`);
    return { logged: true };
  }

  async getStats(userId: string): Promise<CompressionSummary> {
    const db = supabaseService.getAdminClient();

    // Fetch all successful compressions — no limit so totals are accurate
    const { data, error } = await db
      .from('compression_stats')
      .select('asset_id, original_bytes, compressed_bytes, compression_level, created_at, success')
      .eq('user_id', userId)
      .eq('success', true)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[compress/stats] Query error:', error.message);
      throw new Error('Failed to fetch stats');
    }

    interface CompressionStatRow {
      asset_id: string;
      original_bytes: number | null;
      compressed_bytes: number | null;
      compression_level: string;
      created_at: string;
      success: boolean | null;
    }
    const stats: CompressionStatRow[] = (data ?? []) as CompressionStatRow[];
    const totalSaved = stats.reduce((sum, s) => {
      const saved = (s.original_bytes ?? 0) - (s.compressed_bytes ?? 0);
      return sum + Math.max(0, saved); // Guard against negative savings
    }, 0);
    const totalCompressed = stats.length;

    return {
      totalCompressed,
      totalBytesSaved: totalSaved,
      recentCompressions: stats.slice(0, 20).map(s => ({
        assetId: s.asset_id,
        originalBytes: s.original_bytes ?? 0,
        compressedBytes: s.compressed_bytes ?? 0,
        level: s.compression_level,
        savedBytes: Math.max(0, (s.original_bytes ?? 0) - (s.compressed_bytes ?? 0)),
        createdAt: s.created_at,
      })),
    };
  }
}

export const compressService = new CompressService();
