import { Router } from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { streakController } from '../controllers/streak.controller.js';

const router = Router();

router.get('/', authenticateToken, streakController.getStreak);
router.post('/sync', authenticateToken, streakController.syncStreak);
router.post('/activity', authenticateToken, streakController.recordActivity);
router.get('/activities', authenticateToken, streakController.getActivities);

export default router;
