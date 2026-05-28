import { Response } from 'express';
import { AuthenticatedRequest } from '../types/index.js';
import { chatService } from '../services/chat.service.js';

const UUID_REGEX = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

export const chatController = {
  async list(req: AuthenticatedRequest, res: Response) {
    try {
      const sessions = await chatService.listSessions(req.user!.id);
      res.json({ sessions });
    } catch (error) {
      console.error('[chat] List error:', error);
      res.status(500).json({ error: 'Failed to fetch chat sessions' });
    }
  },

  async upsert(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params;
      const { title, messages, isPinned } = req.body;

      if (!id || !UUID_REGEX.test(id)) {
        return res.status(400).json({ error: 'Invalid session id' });
      }
      if (typeof title !== 'string' || title.length === 0) {
        return res.status(400).json({ error: 'title is required' });
      }
      if (!Array.isArray(messages)) {
        return res.status(400).json({ error: 'messages must be an array' });
      }

      const session = await chatService.upsertSession({
        userId: req.user!.id,
        id,
        title: title.slice(0, 200),
        messages,
        isPinned: Boolean(isPinned),
      });

      res.json({ session });
    } catch (error) {
      console.error('[chat] Upsert error:', error);
      res.status(500).json({ error: 'Failed to save chat session' });
    }
  },

  async remove(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params;
      if (!id || !UUID_REGEX.test(id)) {
        return res.status(400).json({ error: 'Invalid session id' });
      }

      await chatService.deleteSession(req.user!.id, id);
      res.json({ deleted: true });
    } catch (error) {
      console.error('[chat] Delete error:', error);
      res.status(500).json({ error: 'Failed to delete chat session' });
    }
  },
};
