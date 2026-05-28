import { Router } from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { coinProgressionController } from '../controllers/coin-progression.controller.js';

const router = Router();

router.get('/', authenticateToken, coinProgressionController.getProgress);
router.post('/sync', authenticateToken, coinProgressionController.syncLibrary);
router.post('/checkpoint', authenticateToken, coinProgressionController.recordCheckpoint);

export default router;
