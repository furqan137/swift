import { Router } from 'express';
import { authenticateToken } from '../middleware/auth.js';
import { cleanupTaskController } from '../controllers/cleanup-task.controller.js';

const router = Router();

router.get('/active', authenticateToken, cleanupTaskController.getActive);
router.post('/active', authenticateToken, cleanupTaskController.upsertActive);
router.post('/complete', authenticateToken, cleanupTaskController.complete);
router.get('/history', authenticateToken, cleanupTaskController.history);

export default router;
