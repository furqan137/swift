import { Router } from 'express';
import { authController } from '../../controllers/auth.controller.js';
import { authenticateToken } from '../../middleware/auth.js';

const router = Router();

// Public routes
router.get('/google/url', authController.getGoogleAuthUrl);
router.get('/google/callback', authController.handleGoogleCallback);
router.post('/google/ios', authController.handleIOSGoogleAuth);

// Protected routes
router.get('/me', authenticateToken, authController.getCurrentUser);
router.post('/update-token', authenticateToken, authController.updateToken);
router.post('/logout', authenticateToken, authController.logout);

export default router;
