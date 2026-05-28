import { Response } from 'express';
import { contactsService } from '../services/contacts.service.js';
import { AuthenticatedRequest } from '../types/index.js';

// ── Limits / sanity bounds ─────────────────────────────────────────────
// Defensive caps. Anything over these almost certainly means a client
// bug or a replay attack — we reject instead of storing junk.
const LIMITS = {
  maxPhoneLength: 40,          // E.164 max is 15 digits; give room for formatting
  maxNameLength: 200,
  maxOrgLength: 200,
  maxContactId: 200,
  maxPhonesPerContact: 30,
  maxEmailsPerContact: 30,
  maxEmailLength: 320,         // RFC 5321 max
  maxContactsPerBatch: 500,
  maxContactCount: 500_000,    // upper bound for a backup record
};

const VALID_ACTIONS = new Set(['merge', 'delete', 'export', 'backup', 'restore']);

// Validates an IPv4/IPv6/generic UUID v4 shape (same pattern Supabase uses)
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isStringWithin(value: unknown, max: number): value is string {
  return typeof value === 'string' && value.length > 0 && value.length <= max;
}

export const contactsController = {
  // POST /contacts/lookup — Phone number enrichment
  async lookup(req: AuthenticatedRequest, res: Response) {
    try {
      const { phone } = req.body;

      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ error: 'phone string required' });
      }

      const trimmed = phone.trim();
      if (trimmed.length === 0) {
        return res.status(400).json({ error: 'phone cannot be empty' });
      }
      if (trimmed.length > LIMITS.maxPhoneLength) {
        return res.status(400).json({ error: `phone too long (max ${LIMITS.maxPhoneLength})` });
      }

      const result = await contactsService.lookupPhone(trimmed);
      res.json(result);
    } catch (error: any) {
      if (error.status) {
        return res.status(error.status).json({ error: error.message });
      }
      console.error('[contacts/lookup] Error:', error);
      res.status(500).json({ error: 'Phone lookup failed' });
    }
  },

  // GET /contacts/health — Sanity check used by iOS to confirm the
  // contacts backend is provisioned. Returns 200 with table status so
  // the client can decide whether to fall back to local-only mode.
  async health(_req: AuthenticatedRequest, res: Response) {
    try {
      const status = await contactsService.health();
      res.json(status);
    } catch (error) {
      console.error('[contacts/health] Error:', error);
      res.status(503).json({
        ok: false,
        tables: {},
        message: 'Contacts backend unavailable',
      });
    }
  },

  // GET /contacts/selftest — Deep pipeline self-test. Authenticated so
  // it can verify the user's row exists + per-table R/W access. Use this
  // from a TestFlight build when something "feels broken" — the response
  // tells you exactly which step of the pipeline is actually failing.
  async selftest(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await contactsService.selftest(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[contacts/selftest] Unexpected error:', error);
      // Even self-test errors are returned structured, never 5xx.
      res.json({
        ok: false,
        userId: req.user?.id || null,
        steps: {},
        error: 'selftest harness crashed',
      });
    }
  },

  // POST /contacts/stats — Log a contact cleanup action
  async logStats(req: AuthenticatedRequest, res: Response) {
    try {
      const { action, contactCount, duplicateGroupsMerged, metadata } = req.body;

      if (!action || typeof action !== 'string') {
        return res.status(400).json({
          error: `action is required (one of: ${[...VALID_ACTIONS].join(', ')})`,
        });
      }

      const normalizedAction = action.trim().toLowerCase();
      if (!VALID_ACTIONS.has(normalizedAction)) {
        return res.status(400).json({
          error: `invalid action; must be one of: ${[...VALID_ACTIONS].join(', ')}`,
        });
      }

      const safeCount = Math.min(
        LIMITS.maxContactCount,
        Math.max(0, Math.floor(Number(contactCount) || 1))
      );
      const safeGroupsMerged = duplicateGroupsMerged != null
        ? Math.min(LIMITS.maxContactCount, Math.max(0, Math.floor(Number(duplicateGroupsMerged))))
        : null;

      // logAction never throws — it returns a result. Stats failures
      // must NOT surface as 5xx because iOS calls this fire-and-forget
      // and the core action already succeeded locally on the device.
      const result = await contactsService.logAction(
        req.user!.id,
        normalizedAction,
        safeCount,
        safeGroupsMerged,
        metadata
      );
      res.json(result);
    } catch (error: any) {
      // Defense-in-depth: if something truly unexpected reaches here,
      // still return 200 with a reason so the client doesn't retry-storm.
      console.error('[contacts/stats] Unexpected controller error:', error);
      res.json({
        logged: false,
        reason: error?.message || 'unexpected error',
        code: 'STATS_CONTROLLER_ERROR',
      });
    }
  },

  // GET /contacts/stats — Get user's contact cleanup summary
  async getStats(req: AuthenticatedRequest, res: Response) {
    try {
      const stats = await contactsService.getStats(req.user!.id);
      res.json(stats);
    } catch (error) {
      console.error('[contacts/stats] Error:', error);
      res.status(500).json({ error: 'Failed to fetch stats' });
    }
  },

  // POST /contacts/backups — Log a new backup (never 5xx)
  async createBackup(req: AuthenticatedRequest, res: Response) {
    try {
      const { contactCount } = req.body;

      if (contactCount == null || typeof contactCount !== 'number' || !Number.isFinite(contactCount)) {
        return res.status(400).json({ error: 'contactCount (number) required' });
      }

      const safeCount = Math.floor(contactCount);
      if (safeCount < 0) {
        return res.status(400).json({ error: 'contactCount must be non-negative' });
      }
      if (safeCount > LIMITS.maxContactCount) {
        return res.status(400).json({
          error: `contactCount exceeds max of ${LIMITS.maxContactCount}`,
        });
      }

      // Never throws — returns { logged, id, contactCount, createdAt, code? }
      const backup = await contactsService.logBackup(req.user!.id, safeCount);
      res.json(backup);
    } catch (error: any) {
      console.error('[contacts/backups] Unexpected controller error:', error);
      res.json({
        logged: false,
        id: `local-${Date.now()}`,
        contactCount: 0,
        createdAt: new Date().toISOString(),
        code: 'BACKUP_CONTROLLER_ERROR',
      });
    }
  },

  // GET /contacts/backups — List all backups for user (never 5xx)
  async listBackups(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await contactsService.listBackups(req.user!.id);
      res.json(result);
    } catch (error) {
      console.error('[contacts/backups] Unexpected controller error:', error);
      res.json({ backups: [], code: 'BACKUP_CONTROLLER_ERROR' });
    }
  },

  // DELETE /contacts/backups/:id — Delete a backup record (never 5xx)
  async deleteBackup(req: AuthenticatedRequest, res: Response) {
    try {
      const { id } = req.params;
      if (!id) {
        return res.status(400).json({ error: 'backup id required' });
      }
      if (!UUID_REGEX.test(id)) {
        return res.status(400).json({ error: 'backup id must be a valid UUID' });
      }

      const result = await contactsService.deleteBackup(req.user!.id, id);
      res.json(result);
    } catch (error) {
      console.error('[contacts/backups] Unexpected controller error:', error);
      res.json({ deleted: false, code: 'BACKUP_CONTROLLER_ERROR' });
    }
  },

  // POST /contacts/sync — Upload a batch of contacts from device
  async syncContacts(req: AuthenticatedRequest, res: Response) {
    try {
      const { contacts } = req.body;

      if (!Array.isArray(contacts) || contacts.length === 0) {
        return res.status(400).json({ error: 'contacts array required (non-empty)' });
      }

      if (contacts.length > LIMITS.maxContactsPerBatch) {
        return res.status(400).json({
          error: `Maximum ${LIMITS.maxContactsPerBatch} contacts per batch`,
        });
      }

      // Validate each contact — defensive per-field sanitation
      const sanitized: {
        deviceContactId: string;
        fullName: string;
        phones: string[];
        emails: string[];
        organization?: string;
      }[] = [];

      for (let i = 0; i < contacts.length; i++) {
        const c = contacts[i];
        if (!c || typeof c !== 'object') {
          return res.status(400).json({ error: `contact[${i}] must be an object` });
        }
        if (!isStringWithin(c.deviceContactId, LIMITS.maxContactId)) {
          return res.status(400).json({
            error: `contact[${i}].deviceContactId must be a string (1..${LIMITS.maxContactId} chars)`,
          });
        }
        if (!isStringWithin(c.fullName, LIMITS.maxNameLength)) {
          return res.status(400).json({
            error: `contact[${i}].fullName must be a string (1..${LIMITS.maxNameLength} chars)`,
          });
        }

        const phones = Array.isArray(c.phones) ? c.phones : [];
        if (phones.length > LIMITS.maxPhonesPerContact) {
          return res.status(400).json({
            error: `contact[${i}] has too many phones (max ${LIMITS.maxPhonesPerContact})`,
          });
        }
        const cleanPhones = phones
          .filter((p: unknown): p is string =>
            typeof p === 'string' && p.length > 0 && p.length <= LIMITS.maxPhoneLength
          )
          .map((p: string) => p.trim());

        const emails = Array.isArray(c.emails) ? c.emails : [];
        if (emails.length > LIMITS.maxEmailsPerContact) {
          return res.status(400).json({
            error: `contact[${i}] has too many emails (max ${LIMITS.maxEmailsPerContact})`,
          });
        }
        const cleanEmails = emails
          .filter((e: unknown): e is string =>
            typeof e === 'string' && e.length > 0 && e.length <= LIMITS.maxEmailLength
          )
          .map((e: string) => e.trim().toLowerCase());

        let organization: string | undefined;
        if (c.organization != null) {
          if (typeof c.organization !== 'string') {
            return res.status(400).json({
              error: `contact[${i}].organization must be a string`,
            });
          }
          const trimmed = c.organization.trim();
          if (trimmed.length > LIMITS.maxOrgLength) {
            return res.status(400).json({
              error: `contact[${i}].organization too long (max ${LIMITS.maxOrgLength})`,
            });
          }
          organization = trimmed.length > 0 ? trimmed : undefined;
        }

        sanitized.push({
          deviceContactId: c.deviceContactId.trim(),
          fullName: c.fullName.trim(),
          phones: cleanPhones,
          emails: cleanEmails,
          organization,
        });
      }

      const result = await contactsService.syncContactsBatch(req.user!.id, sanitized);
      res.json(result);
    } catch (error: any) {
      console.error('[contacts/sync] Error:', error);
      // Distinguish "backend not provisioned" from real server errors so the
      // iOS client can gracefully fall back to local-only mode.
      if (error?.message?.includes('relation') && error?.message?.includes('does not exist')) {
        return res.status(503).json({
          error: 'Contacts sync not provisioned on this backend',
          code: 'SYNC_TABLE_MISSING',
        });
      }
      res.status(500).json({ error: 'Failed to sync contacts' });
    }
  },

  // GET /contacts/sync?page=1&pageSize=500 — Get paginated contacts
  async getContacts(req: AuthenticatedRequest, res: Response) {
    try {
      const page = Math.max(1, parseInt(req.query.page as string) || 1);
      const pageSize = Math.min(
        LIMITS.maxContactsPerBatch,
        Math.max(1, parseInt(req.query.pageSize as string) || LIMITS.maxContactsPerBatch)
      );

      const result = await contactsService.getContacts(req.user!.id, page, pageSize);
      res.json(result);
    } catch (error: any) {
      console.error('[contacts/sync] Get error:', error);
      if (error?.message?.includes('relation') && error?.message?.includes('does not exist')) {
        return res.status(503).json({
          error: 'Contacts sync not provisioned on this backend',
          code: 'SYNC_TABLE_MISSING',
          contacts: [],
          page: 1,
          pageSize: LIMITS.maxContactsPerBatch,
          total: 0,
          totalPages: 0,
        });
      }
      res.status(500).json({ error: 'Failed to fetch contacts' });
    }
  },

  // GET /contacts/sync/count — Get total synced contact count
  async getContactCount(req: AuthenticatedRequest, res: Response) {
    try {
      const result = await contactsService.getContactCount(req.user!.id);
      res.json(result);
    } catch (error: any) {
      console.error('[contacts/sync] Count error:', error);
      if (error?.message?.includes('relation') && error?.message?.includes('does not exist')) {
        // Safe zero-fallback for iOS — "no synced contacts yet"
        return res.json({ total: 0, code: 'SYNC_TABLE_MISSING' });
      }
      res.status(500).json({ error: 'Failed to count contacts' });
    }
  },
};
