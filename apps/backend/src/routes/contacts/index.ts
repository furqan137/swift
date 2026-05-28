import { Router } from 'express';
import { contactsController } from '../../controllers/contacts.controller.js';
import { authenticateToken } from '../../middleware/auth.js';

const router = Router();

// Health check — auth-gated so only signed-in clients probe it, but
// it never throws: missing tables are reported inline instead of 500ing.
router.get('/health', authenticateToken, contactsController.health);

// Deep self-test — verifies each table is readable AND writable for
// the caller's user row. Use this from a TestFlight build when the
// contacts feature "feels broken" — the response surfaces which
// exact Supabase step is failing (missing table / RLS / FK / etc).
router.get('/selftest', authenticateToken, contactsController.selftest);

router.post('/lookup', authenticateToken, contactsController.lookup);
router.post('/stats', authenticateToken, contactsController.logStats);
router.get('/stats', authenticateToken, contactsController.getStats);

// Backup metadata endpoints
router.post('/backups', authenticateToken, contactsController.createBackup);
router.get('/backups', authenticateToken, contactsController.listBackups);
router.delete('/backups/:id', authenticateToken, contactsController.deleteBackup);

// Paginated contacts sync — upload batches from device, retrieve paginated
router.post('/sync', authenticateToken, contactsController.syncContacts);
router.get('/sync', authenticateToken, contactsController.getContacts);
router.get('/sync/count', authenticateToken, contactsController.getContactCount);

export default router;
