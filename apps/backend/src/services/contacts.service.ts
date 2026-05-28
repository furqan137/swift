import { lookupPhone } from './contacts/lookup.js';
import { logAction, getStats } from './contacts/stats.js';
import { logBackup, listBackups, deleteBackup } from './contacts/backups.js';
import { syncContactsBatch, getContacts, getContactCount } from './contacts/sync.js';
import { selftest, health } from './contacts/diagnostics.js';

export const contactsService = {
  lookupPhone,
  logAction,
  getStats,
  logBackup,
  listBackups,
  deleteBackup,
  syncContactsBatch,
  getContacts,
  getContactCount,
  selftest,
  health,
};
