import { Response, NextFunction } from 'express';
import { authService } from '../services/auth.service.js';
import { AuthenticatedRequest } from '../types/index.js';

export const authenticateToken = (
  req: AuthenticatedRequest,
  res: Response,
  next: NextFunction
) => {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  const decoded = authService.verifyToken(token);
  if (!decoded) {
    return res.status(403).json({ error: 'Invalid or expired token' });
  }

  req.user = decoded;
  next();
};

// Re-export types for convenience
export type { AuthenticatedRequest } from '../types/index.js';
