import { Router, Response } from 'express';
import { AuthenticatedRequest, authenticateToken } from '../../middleware/auth.js';
import {
  GMAIL_CATEGORIES,
  GmailTokenExpiredError,
  getValidAccessToken,
  gmailFetch,
  delay,
  invalidateTokenCache,
  invalidatePageCache
} from './helpers.js';
import { invalidateSenderCaches } from './senders.js';
import { invalidateCategoryCache } from './categories.js';

const router = Router();

// Trash specific message IDs
//
// Soft delete: moves messages to Gmail's Trash label. Messages are
// recoverable via /untrash and auto-purged by Gmail after 30 days. We never
// call Gmail's `messages.delete` (permanent removal) here; that's a
// deliberate product decision — permanent deletion must be a separate,
// higher-friction action.
//
// Implementation: one `batchModify` call per 1000-id chunk (Gmail API limit)
// instead of the previous per-message loop. This is ~10x faster for bulk
// selections and consumes fewer Gmail quota units. We fall back to
// single-message /trash calls for any chunk that fails wholesale, so one bad
// id doesn't take down the rest of the batch.
router.post('/trash', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { messageIds } = req.body;
    if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) {
      return res.status(400).json({ error: 'messageIds array required' });
    }
    const validIds = messageIds.filter((id: any) => typeof id === 'string' && id.length > 0);
    if (validIds.length === 0) {
      return res.status(400).json({ error: 'No valid message IDs provided' });
    }

    const accessToken = await getValidAccessToken(req.user!.id);

    const succeededIds: string[] = [];
    const failed: Array<{ messageId: string; reason: string }> = [];

    // Gmail batchModify accepts up to 1000 ids per call.
    const CHUNK_SIZE = 1000;
    for (let i = 0; i < validIds.length; i += CHUNK_SIZE) {
      const chunk = validIds.slice(i, i + CHUNK_SIZE);
      try {
        await gmailFetch('/messages/batchModify', accessToken, {
          method: 'POST',
          body: JSON.stringify({
            ids: chunk,
            addLabelIds: ['TRASH'],
            removeLabelIds: ['INBOX']
          })
        });
        succeededIds.push(...chunk);
      } catch (batchErr) {
        // Batch failed as a whole — retry per-message so one bad id doesn't
        // block the rest of the chunk. Each miss lands in `failed` with a
        // reason so the client can surface partial-failure UX.
        console.error('Batch trash failed, falling back to per-message:', batchErr);
        for (const msgId of chunk) {
          try {
            await gmailFetch(`/messages/${msgId}/trash`, accessToken, { method: 'POST' });
            succeededIds.push(msgId);
          } catch (err: any) {
            failed.push({
              messageId: msgId,
              reason: err?.message ?? 'Trash request failed'
            });
          }
          await delay(50);
        }
      }
      if (i + CHUNK_SIZE < validIds.length) await delay(200);
    }

    if (succeededIds.length > 0) {
      invalidateSenderCaches(req.user!.id);
      invalidatePageCache(req.user!.id);
      invalidateCategoryCache(req.user!.id);
    }

    res.json({
      success: failed.length === 0,
      deletedCount: succeededIds.length,
      failed
    });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Trash messages error:', error);
    res.status(500).json({ error: 'Failed to trash messages' });
  }
});

// Recover emails from trash (untrash)
//
// Reverse of /trash. Uses `batchModify` with `removeLabelIds: ['TRASH']` +
// `addLabelIds: ['INBOX']` so messages show up in the inbox again, not just
// in All Mail. Same per-chunk-then-per-message fallback as trash.
router.post('/untrash', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { messageIds } = req.body;
    if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) {
      return res.status(400).json({ error: 'messageIds array required' });
    }
    const validIds = messageIds.filter((id: any) => typeof id === 'string' && id.length > 0);
    if (validIds.length === 0) {
      return res.status(400).json({ error: 'No valid message IDs provided' });
    }

    const accessToken = await getValidAccessToken(req.user!.id);

    const succeededIds: string[] = [];
    const failed: Array<{ messageId: string; reason: string }> = [];

    const CHUNK_SIZE = 1000;
    for (let i = 0; i < validIds.length; i += CHUNK_SIZE) {
      const chunk = validIds.slice(i, i + CHUNK_SIZE);
      try {
        await gmailFetch('/messages/batchModify', accessToken, {
          method: 'POST',
          body: JSON.stringify({
            ids: chunk,
            addLabelIds: ['INBOX'],
            removeLabelIds: ['TRASH']
          })
        });
        succeededIds.push(...chunk);
      } catch (batchErr) {
        console.error('Batch untrash failed, falling back to per-message:', batchErr);
        for (const msgId of chunk) {
          try {
            await gmailFetch(`/messages/${msgId}/untrash`, accessToken, { method: 'POST' });
            succeededIds.push(msgId);
          } catch (err: any) {
            failed.push({
              messageId: msgId,
              reason: err?.message ?? 'Untrash request failed'
            });
          }
          await delay(50);
        }
      }
      if (i + CHUNK_SIZE < validIds.length) await delay(200);
    }

    if (succeededIds.length > 0) invalidatePageCache(req.user!.id);

    res.json({
      success: failed.length === 0,
      recoveredCount: succeededIds.length,
      failed
    });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Untrash messages error:', error);
    res.status(500).json({ error: 'Failed to recover messages' });
  }
});

// Batch delete emails with filters
router.post('/delete', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const {
      categories,
      scope: scopeParam,
      olderThan,
      readOnly,
      unreadOnly,
      excludeStarred,
      senderContains,
      subjectContains,
      hasAttachments,
      sizeFilter: sizeFilterParam,
      excludeKeywords,
      targetKeywords
    } = req.body;

    const scope = scopeParam || 'all';

    if (!categories || !Array.isArray(categories) || categories.length === 0) {
      return res.status(400).json({ error: 'categories array required' });
    }

    // Validate filter inputs
    if (olderThan !== undefined && (!Number.isInteger(olderThan) || olderThan < 1 || olderThan > 3650)) {
      return res.status(400).json({ error: 'olderThan must be integer 1-3650' });
    }
    if (categories.some((c: any) => typeof c !== 'string' || !GMAIL_CATEGORIES[c as keyof typeof GMAIL_CATEGORIES])) {
      return res.status(400).json({ error: `Invalid category. Valid: ${Object.keys(GMAIL_CATEGORIES).join(', ')}` });
    }

    const accessToken = await getValidAccessToken(req.user!.id);

    let totalDeleted = 0;

    for (const category of categories) {
      const labelId = GMAIL_CATEGORIES[category as keyof typeof GMAIL_CATEGORIES];
      if (!labelId) continue;

      // Build Gmail query matching the same logic as /messages/:category
      // Always exclude already-trashed and draft emails
      let query = '-in:trash -in:draft ';
      if (olderThan) query += `older_than:${olderThan}d `;
      if (readOnly) query += 'is:read ';
      else if (unreadOnly) query += 'is:unread ';
      if (excludeStarred) query += '-is:starred ';
      if (senderContains) query += `from:(${senderContains}) `;
      if (subjectContains) query += `subject:(${subjectContains}) `;
      if (hasAttachments === true) query += 'has:attachment ';
      else if (hasAttachments === false) query += '-has:attachment ';
      if (sizeFilterParam) query += `${sizeFilterParam} `;
      if (excludeKeywords && Array.isArray(excludeKeywords)) {
        for (const kw of excludeKeywords) {
          if (kw.trim()) query += `-"${kw.trim()}" `;
        }
      }
      if (targetKeywords && Array.isArray(targetKeywords)) {
        const kws = targetKeywords.filter((k: string) => k.trim());
        if (kws.length > 0) {
          query += `{${kws.map((k: string) => `"${k.trim()}"`).join(' ')}} `;
        }
      }

      // For primary category, use query-based approach
      if (labelId === 'CATEGORY_PERSONAL') {
        query += 'category:primary ';
      }

      try {
        // Paginate through ALL matching emails (not just first 500)
        let pageToken: string | undefined = undefined;
        let pages = 0;
        const maxPages = 20; // Safety cap: 20 pages × 500 = 10,000 emails max

        do {
          const params = new URLSearchParams();
          if (labelId !== 'CATEGORY_PERSONAL') {
            params.append('labelIds', labelId);
          } else {
            params.append('labelIds', 'INBOX');
          }
          if (scope === 'inbox' && labelId !== 'SPAM' && labelId !== 'CATEGORY_PERSONAL') {
            params.append('labelIds', 'INBOX');
          }
          params.append('maxResults', '500');
          if (query.trim()) params.append('q', query.trim());
          if (pageToken) params.append('pageToken', pageToken);

          const listData = await gmailFetch(`/messages?${params}`, accessToken);

          if (listData.messages && listData.messages.length > 0) {
            const messageIds = listData.messages.map((m: any) => m.id);

            // Batch modify in chunks of 100 (Gmail API limit)
            const removeLabelIds = ['INBOX'];
            if (labelId !== 'CATEGORY_PERSONAL') {
              removeLabelIds.push(labelId);
            }
            for (let i = 0; i < messageIds.length; i += 100) {
              const chunk = messageIds.slice(i, i + 100);
              await gmailFetch('/messages/batchModify', accessToken, {
                method: 'POST',
                body: JSON.stringify({
                  ids: chunk,
                  addLabelIds: ['TRASH'],
                  removeLabelIds
                })
              });
              if (i + 100 < messageIds.length) {
                await delay(500);
              }
            }

            totalDeleted += messageIds.length;
          }

          pageToken = listData.nextPageToken;
          pages++;
          if (pageToken && pages < maxPages) await delay(300);
        } while (pageToken && pages < maxPages);

        if (pages >= maxPages) {
          console.warn(`[delete] Hit page limit (${maxPages}) for ${category}, some emails may remain`);
        }
      } catch (error) {
        console.error(`Error deleting from ${category}:`, error);
      }

      await delay(300);
    }

    // Invalidate caches since email counts changed
    invalidateSenderCaches(req.user!.id);
    invalidatePageCache(req.user!.id);
    invalidateCategoryCache(req.user!.id);

    res.json({ success: true, deletedCount: totalDeleted });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Delete emails error:', error);
    res.status(500).json({ error: 'Failed to delete emails' });
  }
});

// Unsubscribe from sender
router.post('/unsubscribe', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { senderEmail, deleteExisting = true } = req.body;

    if (!senderEmail || typeof senderEmail !== 'string') {
      return res.status(400).json({ error: 'senderEmail required' });
    }
    // Basic email format check
    if (!senderEmail.includes('@') || senderEmail.length > 254) {
      return res.status(400).json({ error: 'Invalid email format' });
    }

    const accessToken = await getValidAccessToken(req.user!.id);

    let deletedCount = 0;

    // Trash all existing emails from this sender (paginate to get ALL)
    if (deleteExisting) {
      let pageToken: string | undefined = undefined;
      let pages = 0;
      const maxPages = 10; // Safety cap

      do {
        try {
          const params = new URLSearchParams();
          params.append('q', `from:${senderEmail} -in:trash -in:draft`);
          params.append('maxResults', '500');
          if (pageToken) params.append('pageToken', pageToken);

          const listData = await gmailFetch(`/messages?${params}`, accessToken);

          if (listData.messages && listData.messages.length > 0) {
            const messageIds = listData.messages.map((m: any) => m.id);

            // Batch modify in chunks of 100 (Gmail limit)
            for (let i = 0; i < messageIds.length; i += 100) {
              const chunk = messageIds.slice(i, i + 100);
              await gmailFetch('/messages/batchModify', accessToken, {
                method: 'POST',
                body: JSON.stringify({
                  ids: chunk,
                  addLabelIds: ['TRASH'],
                  removeLabelIds: ['INBOX']
                })
              });
              if (i + 100 < messageIds.length) await delay(200);
            }

            deletedCount += messageIds.length;
          }

          pageToken = listData.nextPageToken;
          pages++;
          if (pageToken && pages < maxPages) await delay(300);
        } catch (error) {
          console.error('Delete existing error:', error);
          break;
        }
      } while (pageToken && pages < maxPages);
    }

    // Try to create a Gmail filter to auto-trash future emails
    // This requires gmail.settings.basic scope — if we don't have it, that's OK,
    // the existing emails are already trashed above
    try {
      await gmailFetch('/settings/filters', accessToken, {
        method: 'POST',
        body: JSON.stringify({
          criteria: { from: senderEmail },
          action: {
            removeLabelIds: ['INBOX'],
            addLabelIds: ['TRASH']
          }
        })
      });
      console.log(`[unsubscribe] Filter created for ${senderEmail}`);
    } catch (error: any) {
      // 403 = insufficient scopes, expected if we only have gmail.modify
      // Just log and continue — existing emails were already trashed
      if (error?.message?.includes('403')) {
        console.log(`[unsubscribe] Filter creation skipped (no gmail.settings.basic scope) for ${senderEmail}`);
      } else {
        console.error('[unsubscribe] Filter creation error:', error);
      }
    }

    // Invalidate caches since email counts changed
    invalidateSenderCaches(req.user!.id);
    invalidatePageCache(req.user!.id);
    invalidateCategoryCache(req.user!.id);

    res.json({
      success: true,
      message: `Unsubscribed from ${senderEmail}`,
      deletedCount
    });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Unsubscribe error:', error);
    res.status(500).json({ error: 'Failed to unsubscribe' });
  }
});

// Legacy endpoint for compatibility
router.get('/labels', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const accessToken = await getValidAccessToken(req.user!.id);
    const data = await gmailFetch('/labels', accessToken);
    res.json({ labels: data.labels });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get labels error:', error);
    res.status(500).json({ error: 'Failed to fetch email labels' });
  }
});

export default router;
