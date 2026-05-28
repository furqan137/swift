import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { cleanupTaskService } from '../services/cleanup-task.service.js';

export const cleanupTaskController = {
  async getActive(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await cleanupTaskService.getActiveTask(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[cleanup-task] get active error:', error);
      res.status(500).json({ error: 'Failed to fetch active task' });
    }
  },

  async upsertActive(req: AuthenticatedRequest, res: Response) {
    try {
      const { taskNumber, taskTitle, taskType, category, estimatedMB, estimatedCoins, level } = req.body;
      const result = await cleanupTaskService.upsertActiveTask(req.user!.id, {
        taskNumber: Math.max(0, Number(taskNumber) || 0),
        taskTitle: String(taskTitle ?? ''),
        taskType: String(taskType ?? 'quick_cleanup'),
        category: String(category ?? ''),
        estimatedMB: Math.max(0, Number(estimatedMB) || 0),
        estimatedCoins: Math.max(0, Number(estimatedCoins) || 0),
        level: Math.max(1, Number(level) || 1),
      });
      res.json(result);
    } catch (error) {
      console.error('[cleanup-task] upsert active error:', error);
      res.status(500).json({ error: 'Failed to persist active task' });
    }
  },

  async complete(req: AuthenticatedRequest, res: Response) {
    try {
      const { taskNumber, taskTitle, taskType, category, mbReviewed, coinsEarned, levelAtCompletion, assetCount } = req.body;
      const result = await cleanupTaskService.completeTask(req.user!.id, {
        taskNumber: Math.max(0, Number(taskNumber) || 0),
        taskTitle: String(taskTitle ?? ''),
        taskType: String(taskType ?? 'quick_cleanup'),
        category: String(category ?? ''),
        mbReviewed: Math.max(0, Number(mbReviewed) || 0),
        coinsEarned: Math.max(0, Number(coinsEarned) || 0),
        levelAtCompletion: Math.max(1, Number(levelAtCompletion) || 1),
        assetCount: Math.max(0, Number(assetCount) || 0),
      });
      res.json(result);
    } catch (error) {
      console.error('[cleanup-task] complete error:', error);
      res.status(500).json({ error: 'Failed to record completed task' });
    }
  },

  async history(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await cleanupTaskService.getHistory(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[cleanup-task] history error:', error);
      res.status(500).json({ error: 'Failed to fetch cleanup history' });
    }
  },
};
