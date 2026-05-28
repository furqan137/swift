import { Request, Response } from 'express';
import { themeService } from '../services/theme.service.js';

export const themeController = {
  /**
   * GET /theme/current?tz=America/New_York
   *
   * Public — no auth, no user context.
   * The `tz` query param is an IANA timezone name; missing or invalid
   * values fall back to UTC so the endpoint can't 500 on bad input.
   *
   * Response `mode` reflects the caller's LOCAL time of day so every
   * user sees dark at night and light during the day regardless of
   * where they are.
   */
  getCurrent(req: Request, res: Response) {
    try {
      const tzParam = req.query.tz;
      const tz = typeof tzParam === 'string' ? tzParam : undefined;

      const snapshot = themeService.getCurrent(tz);

      // Snapshots are valid until `nextSwitchAt` but we cap at 60s so a
      // fresh deploy rolls out quickly and per-user tz doesn't pollute
      // a shared cache.
      res.set('Cache-Control', 'private, max-age=60');
      res.json(snapshot);
    } catch (error) {
      console.error('[theme] Error:', error);
      res.status(500).json({ error: 'Failed to compute theme' });
    }
  },
};
