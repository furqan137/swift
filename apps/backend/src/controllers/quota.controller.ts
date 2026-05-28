import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { quotaService } from '../services/quota.service.js';

const VALID_SECTIONS = ['photos', 'videos', 'contacts', 'email', 'compress'];

export const quotaController = {
  async checkQuota(req: AuthenticatedRequest, res: Response) {
    try {
      const quota = await quotaService.checkQuota(req.user!.id);
      res.json(quota);
    } catch (error: any) {
      console.error('[quota] Check error:', error);
      res.status(500).json({ error: error.message || 'Failed to check quota' });
    }
  },

  async consumeFreeDeletes(req: AuthenticatedRequest, res: Response) {
    try {
      const { count } = req.body;

      if (!count || typeof count !== 'number' || count <= 0) {
        return res.status(400).json({ error: 'count must be a positive integer' });
      }

      const quota = await quotaService.consumeFreeDeletes(req.user!.id, count);
      res.json({ success: true, quota });
    } catch (error: any) {
      console.error('[quota] Consume error:', error);
      res.status(500).json({ error: error.message || 'Failed to consume deletes' });
    }
  },

  async grantAdReward(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await quotaService.grantAdReward(req.user!.id);
      res.json({
        success: true,
        deletes_granted: result.deletesGranted,
        quota: result.quota,
      });
    } catch (error: any) {
      const status = error.status || 500;
      console.error('[quota] Grant error:', error);
      res.status(status).json({
        error: error.message || 'Failed to grant ad reward',
        code: status === 429 ? 'AD_CAP_REACHED' : undefined,
      });
    }
  },

  async consumeSectionQuota(req: AuthenticatedRequest, res: Response) {
    try {
      const { section, count } = req.body;

      if (!section || !VALID_SECTIONS.includes(section)) {
        return res.status(400).json({ error: `section must be one of: ${VALID_SECTIONS.join(', ')}` });
      }
      if (!count || typeof count !== 'number' || count <= 0) {
        return res.status(400).json({ error: 'count must be a positive integer' });
      }

      const quota = await quotaService.consumeSectionQuota(req.user!.id, section, count);
      res.json({ success: true, quota });
    } catch (error: any) {
      console.error('[quota] Consume section error:', error);
      res.status(500).json({ error: error.message || 'Failed to consume section quota' });
    }
  },

  async grantSectionAdReward(req: AuthenticatedRequest, res: Response) {
    try {
      const { section } = req.body;

      if (!section || !VALID_SECTIONS.includes(section)) {
        return res.status(400).json({ error: `section must be one of: ${VALID_SECTIONS.join(', ')}` });
      }
      if (section === 'contacts') {
        return res.status(400).json({ error: 'Contacts section does not support ad rewards' });
      }

      const result = await quotaService.grantSectionAdReward(req.user!.id, section);
      res.json({
        success: true,
        reward_amount: result.rewardAmount,
        quota: result.quota,
      });
    } catch (error: any) {
      const status = error.status || 500;
      console.error('[quota] Grant section error:', error);
      res.status(status).json({
        error: error.message || 'Failed to grant section ad reward',
        code: status === 429 ? 'AD_CAP_REACHED' : undefined,
      });
    }
  },
};
