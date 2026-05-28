import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { coinProgressionService, CategoryBreakdown } from '../services/coin-progression.service.js';

export const coinProgressionController = {
  async getProgress(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await coinProgressionService.getProgress(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[progress] get error:', error);
      res.status(500).json({ error: 'Failed to fetch progress' });
    }
  },

  async syncLibrary(req: AuthenticatedRequest, res: Response) {
    try {
      const { totalPhotos, totalVideos } = req.body;
      if (totalPhotos == null || totalVideos == null) {
        return res.status(400).json({ error: 'totalPhotos and totalVideos are required' });
      }
      const result = await coinProgressionService.syncLibrary(req.user!.id, {
        totalPhotos: Number(totalPhotos) || 0,
        totalVideos: Number(totalVideos) || 0,
      });
      res.json(result);
    } catch (error) {
      console.error('[progress] sync error:', error);
      res.status(500).json({ error: 'Failed to sync library' });
    }
  },

  async recordCheckpoint(req: AuthenticatedRequest, res: Response) {
    try {
      const {
        eventId, planId, taskId, checkpointId,
        reviewedItemCount, selectedItemCount, deletedBytes, categoryBreakdown,
        maxLifetimeCoins, totalLifetimeCoins, currentLevel, maxLevel,
        currentLevelCoins, coinsNeededForNextLevel, cleanBarPercent, beeStage,
      } = req.body;

      if (!eventId) {
        return res.status(400).json({ error: 'eventId is required' });
      }

      const num = (v: unknown) => (v == null ? undefined : Math.max(0, Number(v) || 0));

      const result = await coinProgressionService.recordCheckpoint({
        userId: req.user!.id,
        eventId,
        planId: planId || '',
        taskId: taskId || '',
        checkpointId: checkpointId || '',
        reviewedItemCount: Math.max(0, Number(reviewedItemCount) || 0),
        selectedItemCount: Math.max(0, Number(selectedItemCount) || 0),
        deletedBytes: Math.max(0, Number(deletedBytes) || 0),
        categoryBreakdown: (categoryBreakdown ?? undefined) as CategoryBreakdown | undefined,
        // Client's authoritative derived progress (display source of truth).
        clientMaxLifetimeCoins: num(maxLifetimeCoins),
        clientTotalLifetimeCoins: num(totalLifetimeCoins),
        clientCurrentLevel: num(currentLevel),
        clientMaxLevel: num(maxLevel),
        clientCurrentLevelCoins: num(currentLevelCoins),
        clientCoinsNeededForNextLevel: num(coinsNeededForNextLevel),
        clientCleanBarPercent: cleanBarPercent == null ? undefined : Number(cleanBarPercent),
        clientBeeStage: num(beeStage),
      });

      res.json(result);
    } catch (error) {
      console.error('[progress] checkpoint error:', error);
      res.status(500).json({ error: 'Failed to record checkpoint' });
    }
  },
};
