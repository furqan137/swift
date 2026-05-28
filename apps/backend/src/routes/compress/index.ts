import { Router } from 'express';
import { authenticateToken } from '../../middleware/auth.js';
import { compressController } from '../../controllers/compress.controller.js';

const router = Router();

router.post('/stats', authenticateToken, compressController.logStats);
router.get('/stats', authenticateToken, compressController.getStats);

export default router;
