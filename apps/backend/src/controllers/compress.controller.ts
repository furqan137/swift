import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { compressService } from '../services/compress.service.js';

export const compressController = {
  async logStats(req: AuthenticatedRequest, res: Response) {
    try {
      const {
        assetId,
        originalBytes,
        compressedBytes,
        compressionLevel,
        codec,
        durationSeconds,
        compressionTimeSeconds,
        resolution,
        success,
        errorMessage,
        deviceModel,
        osVersion,
      } = req.body;

      if (!assetId || typeof assetId !== 'string') {
        return res.status(400).json({ error: 'assetId (string) is required' });
      }
      if (originalBytes == null || typeof originalBytes !== 'number' || originalBytes < 0) {
        return res.status(400).json({ error: 'originalBytes (non-negative number) is required' });
      }
      if (compressedBytes == null || typeof compressedBytes !== 'number' || compressedBytes < 0) {
        return res.status(400).json({ error: 'compressedBytes (non-negative number) is required' });
      }
      if (!compressionLevel || typeof compressionLevel !== 'string') {
        return res.status(400).json({ error: 'compressionLevel (string) is required' });
      }
      const validLevels = ['low', 'medium', 'high'];
      if (!validLevels.includes(compressionLevel.toLowerCase())) {
        return res.status(400).json({ error: `compressionLevel must be one of: ${validLevels.join(', ')}` });
      }

      // Codec is optional, but if provided it must be one we recognise.
      // Prevents typos like "HEEC" silently polluting analytics.
      if (codec != null) {
        if (typeof codec !== 'string') {
          return res.status(400).json({ error: 'codec must be a string' });
        }
        const validCodecs = ['hevc', 'h.264', 'h264', 'heic', 'jpeg', 'png', 'unknown'];
        if (!validCodecs.includes(codec.toLowerCase())) {
          return res.status(400).json({
            error: `codec must be one of: ${validCodecs.join(', ')}`,
          });
        }
      }

      // On success, compressed must not exceed original. (The frontend will
      // log success: false in the rare grow-on-recompress case.)
      if (success !== false && compressedBytes > originalBytes) {
        return res.status(400).json({
          error: 'compressedBytes must be <= originalBytes when success=true',
        });
      }

      const result = await compressService.logStats({
        userId: req.user!.id,
        assetId,
        originalBytes,
        compressedBytes,
        compressionLevel,
        codec,
        durationSeconds,
        compressionTimeSeconds,
        resolution,
        success,
        errorMessage,
        deviceModel,
        osVersion,
      });

      res.json(result);
    } catch (error) {
      console.error('[compress/stats] Error:', error);
      res.status(500).json({ error: 'Failed to log compression stats' });
    }
  },

  async getStats(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await compressService.getStats(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[compress/stats] Error:', error);
      res.status(500).json({ error: 'Failed to fetch stats' });
    }
  },
};
