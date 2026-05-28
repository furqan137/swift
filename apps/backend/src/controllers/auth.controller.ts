import { Request, Response } from 'express';
import { authService } from '../services/auth.service.js';
import { AuthenticatedRequest } from '../types/index.js';

export const authController = {
  // Generate Google OAuth URL (for web-based sign-in)
  getGoogleAuthUrl(req: Request, res: Response) {
    try {
      const state = req.query.state as string | undefined;
      const url = authService.getGoogleAuthUrl(state);
      res.json({ url });
    } catch (error) {
      console.error('Error generating Google auth URL:', error);
      res.status(500).json({ error: 'Failed to generate auth URL' });
    }
  },

  // Google OAuth callback (for web flow)
  async handleGoogleCallback(req: Request, res: Response) {
    try {
      const { code, state } = req.query;

      if (!code) {
        return res.status(400).json({ error: 'Authorization code required' });
      }

      const result = await authService.handleGoogleCallback(code as string);

      if (!result) {
        return res.status(400).json({ error: 'Authentication failed' });
      }

      // Redirect back to app with token
      if (state) {
        res.redirect(`${state}?token=${result.token}`);
      } else {
        res.json({
          token: result.token,
          user: result.user
        });
      }
    } catch (error) {
      console.error('Google callback error:', error);
      res.status(500).json({ error: 'Authentication failed' });
    }
  },

  // iOS Google Sign-In (receives ID token from iOS app)
  async handleIOSGoogleAuth(req: Request, res: Response) {
    try {
      const { idToken, accessToken } = req.body;

      if (!idToken) {
        return res.status(400).json({ error: 'ID token required' });
      }

      const result = await authService.handleIOSGoogleAuth(idToken, accessToken);

      if (!result) {
        return res.status(400).json({ error: 'Invalid Google token' });
      }

      res.json({
        token: result.token,
        isNewUser: result.isNewUser,
        user: result.user
      });
    } catch (error) {
      console.error('iOS Google sign-in error:', error);
      res.status(500).json({ error: 'Authentication failed' });
    }
  },

  // Get current user
  async getCurrentUser(req: AuthenticatedRequest, res: Response) {
    try {
      const user = await authService.getCurrentUser(req.user!.id);

      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      res.json({ user });
    } catch (error) {
      console.error('Get user error:', error);
      res.status(500).json({ error: 'Failed to get user' });
    }
  },

  // Update user display name
  async updateName(req: AuthenticatedRequest, res: Response) {
    try {
      const { name } = req.body;

      if (typeof name !== 'string') {
        return res.status(400).json({ error: 'name is required' });
      }

      const trimmed = name.trim();
      const success = await authService.updateName(req.user!.id, trimmed);

      if (!success) {
        return res.status(500).json({ error: 'Failed to update name' });
      }

      res.json({ success: true, name: trimmed });
    } catch (error) {
      console.error('Update name error:', error);
      res.status(500).json({ error: 'Failed to update name' });
    }
  },

  // Update Google access token (called by iOS after token refresh)
  async updateToken(req: AuthenticatedRequest, res: Response) {
    try {
      const { accessToken } = req.body;

      if (!accessToken) {
        return res.status(400).json({ error: 'Access token required' });
      }

      const updated = await authService.updateGoogleToken(req.user!.id, accessToken);

      if (!updated) {
        return res.status(500).json({ error: 'Failed to update token' });
      }

      res.json({ message: 'Token updated successfully' });
    } catch (error) {
      console.error('Update token error:', error);
      res.status(500).json({ error: 'Failed to update token' });
    }
  },

  // Logout
  logout(_req: AuthenticatedRequest, res: Response) {
    res.json({ message: 'Logged out successfully' });
  }
};
