import { Router } from 'express';
import categoryRoutes from './categories.js';
import messageRoutes from './messages.js';
import senderRoutes from './senders.js';
import actionRoutes from './actions.js';

const router = Router();

// Mount sub-routers — each handles its own subset of /email/* endpoints
//   categories:  GET /profile, GET /categories
//   messages:    GET /messages/:category, GET /message/:messageId
//   senders:     GET /senders
//   actions:     POST /trash, POST /untrash, POST /delete, POST /unsubscribe, GET /labels
router.use('/', categoryRoutes);
router.use('/', messageRoutes);
router.use('/', senderRoutes);
router.use('/', actionRoutes);

export default router;
