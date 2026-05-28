import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { streakService } from '../services/streak.service.js';

export const streakController = {
  async getStreak(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await streakService.getStreak(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[streak] Error:', error);
      res.status(500).json({ error: 'Failed to fetch streak data' });
    }
  },

  async syncStreak(req: AuthenticatedRequest, res: Response) {
    try {
      const {
        currentStreak,
        bestStreak,
        lastActivityDate,
        lifetimeItemsCleaned,
        lifetimeBytesSaved,
        totalScansCompleted,
        cleanScore,
      } = req.body;

      if (currentStreak == null || bestStreak == null) {
        return res.status(400).json({ error: 'currentStreak and bestStreak are required' });
      }

      const result = await streakService.syncStreak({
        userId: req.user!.id,
        currentStreak,
        bestStreak,
        lastActivityDate: lastActivityDate || null,
        lifetimeItemsCleaned: lifetimeItemsCleaned || 0,
        lifetimeBytesSaved: lifetimeBytesSaved || 0,
        totalScansCompleted: totalScansCompleted || 0,
        cleanScore: cleanScore || 0,
      });

      res.json(result);
    } catch (error) {
      console.error('[streak] Sync error:', error);
      res.status(500).json({ error: 'Failed to sync streak data' });
    }
  },

  async recordActivity(req: AuthenticatedRequest, res: Response) {
    try {
      const { action, itemCount, bytesSaved, metadata } = req.body;

      if (!action || itemCount == null) {
        return res.status(400).json({ error: 'action and itemCount are required' });
      }

      const result = await streakService.recordActivity({
        userId: req.user!.id,
        action,
        itemCount: itemCount || 0,
        bytesSaved: bytesSaved || 0,
        metadata,
      });

      res.json(result);
    } catch (error: any) {
      const status = error.status || 500;
      console.error('[streak] Activity error:', error);
      res.status(status).json({ error: error.message || 'Failed to log activity' });
    }
  },

  async getActivities(req: AuthenticatedRequest, res: Response) {
    try {
      const limit = parseInt(req.query.limit as string) || 50;
      const result = await streakService.getActivities(req.user!.id, Math.min(limit, 200));
      res.json(result);
    } catch (error) {
      console.error('[streak] Activities error:', error);
      res.status(500).json({ error: 'Failed to fetch activities' });
    }
  },
};
