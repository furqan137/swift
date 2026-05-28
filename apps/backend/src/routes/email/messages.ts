import { Router, Response } from 'express';
import { AuthenticatedRequest, authenticateToken } from '../../middleware/auth.js';
import {
  GMAIL_CATEGORIES,
  GmailTokenExpiredError,
  getValidAccessToken,
  gmailFetch,
  fetchMessageBatch,
  decodeHtmlEntities,
  invalidateTokenCache,
  countAllMessages,
  getPageCache,
  setPageCache,
  isPageCacheFresh
} from './helpers.js';

const router = Router();

// Per-query locks so we don't spawn 5 concurrent background refreshes for the
// same user/category while one is already running.
const revalidating = new Set<string>();

function pageCacheRevalKey(userId: string, category: string, scope: string, maxResults: number, query: string): string {
  return `${userId}:${category}:${scope}:${maxResults}:${query}`;
}

// Fire-and-forget: refresh the page cache in the background while the client
// got served stale data. On failure we just leave the stale cache in place —
// the next request will either hit fresh data or trigger another revalidation.
//
// Wave-based: writes partial results to the cache as each batch of message
// headers comes back, so polling clients see the list grow in near-real-time
// instead of jumping from stale → fresh in one step.
function revalidateInBackground(
  userId: string,
  category: string,
  scope: string,
  maxResults: number,
  queryStr: string,
  params: URLSearchParams,
  accessToken: string,
  hasFiltersApplied: boolean,
  sortOrder: string | undefined
) {
  const key = pageCacheRevalKey(userId, category, scope, maxResults, queryStr);
  revalidating.add(key);
  (async () => {
    try {
      const listData = await gmailFetch(`/messages?${params}`, accessToken);
      if (!listData.messages || listData.messages.length === 0) {
        setPageCache(userId, category, scope, maxResults, queryStr, {
          messages: [], nextPageToken: null, count: 0, filteredCount: null, fetchedAt: Date.now()
        });
        return;
      }
      const messageIds = listData.messages.map((m: any) => m.id);
      const totalEstimate = listData.resultSizeEstimate || messageIds.length;
      const filteredCountEstimate = hasFiltersApplied ? totalEstimate : null;

      // Fetch headers in waves; update cache after each wave so polling
      // clients see progressive results (matches /senders pattern).
      const WAVE_SIZE = 100;
      const collected: any[] = [];
      for (let i = 0; i < messageIds.length; i += WAVE_SIZE) {
        const slice = messageIds.slice(i, i + WAVE_SIZE);
        const waveMessages = await fetchMessageBatch(slice, accessToken);
        collected.push(...waveMessages);
        const sortedSoFar = sortOrder === 'oldest'
          ? [...collected].sort((a: any, b: any) => (a.date || '').localeCompare(b.date || ''))
          : collected;
        setPageCache(userId, category, scope, maxResults, queryStr, {
          messages: sortedSoFar,
          nextPageToken: listData.nextPageToken || null,
          count: totalEstimate,
          filteredCount: filteredCountEstimate,
          fetchedAt: Date.now()
        });
        console.log(`[messages/${category}] Progressive: ${collected.length}/${messageIds.length}`);
      }
      console.log(`[messages/${category}] Background revalidate done (${collected.length} msgs)`);
    } catch (e) {
      console.error(`[messages/${category}] Background revalidate failed:`, e);
    } finally {
      revalidating.delete(key);
    }
  })();
}

// True when a background revalidation is currently in flight for this query.
function isRevalidating(userId: string, category: string, scope: string, maxResults: number, queryStr: string): boolean {
  return revalidating.has(pageCacheRevalKey(userId, category, scope, maxResults, queryStr));
}

// Get emails for a specific category with filters
router.get('/messages/:category', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { category } = req.params;
    const {
      maxResults = '50',
      pageToken,
      scope: scopeParam,
      olderThan,
      isRead,
      isStarred,
      excludeStarred,
      from: fromFilter,
      subject: subjectFilter,
      hasAttachment,
      sizeFilter,
      excludeKeywords,
      targetKeywords,
      sortOrder
    } = req.query;

    const scope = (scopeParam as string) || 'all';
    const accessToken = await getValidAccessToken(req.user!.id);

    const labelId = GMAIL_CATEGORIES[category as keyof typeof GMAIL_CATEGORIES];
    if (!labelId) {
      return res.status(400).json({ error: `Invalid category. Valid: ${Object.keys(GMAIL_CATEGORIES).join(', ')}` });
    }

    // Clamp maxResults to safe range
    const clampedMaxResults = Math.min(Math.max(parseInt(maxResults as string, 10) || 50, 1), 500);

    // Build query from filter params
    let query = '-in:trash -in:draft ';
    if (olderThan) query += `older_than:${olderThan}d `;
    if (isRead === 'true') query += 'is:read ';
    else if (isRead === 'false') query += 'is:unread ';
    if (isStarred === 'true') query += 'is:starred ';
    if (excludeStarred === 'true') query += '-is:starred ';
    if (fromFilter) query += `from:(${fromFilter}) `;
    if (subjectFilter) query += `subject:(${subjectFilter}) `;
    if (hasAttachment === 'true') query += 'has:attachment ';
    else if (hasAttachment === 'false') query += '-has:attachment ';
    if (sizeFilter) query += `${sizeFilter} `;
    if (excludeKeywords) {
      const keywords = (excludeKeywords as string).split(',');
      for (const kw of keywords) {
        if (kw.trim()) query += `-"${kw.trim()}" `;
      }
    }
    if (targetKeywords) {
      const keywords = (targetKeywords as string).split(',').map(k => k.trim()).filter(Boolean);
      if (keywords.length > 0) {
        query += `{${keywords.map(k => `"${k}"`).join(' ')}} `;
      }
    }

    // For primary: add category:primary to query (CATEGORY_PERSONAL label may not exist)
    if (labelId === 'CATEGORY_PERSONAL') {
      query += 'category:primary ';
    }

    // Check if user has active filters beyond the base query
    const baseQuery = '-in:trash -in:draft category:primary';
    const hasFiltersApplied = query.trim() !== '-in:trash -in:draft' &&
      query.trim() !== '-in:trash -in:draft category:primary';

    const params = new URLSearchParams();

    // Use labelIds for all categories (proven reliable)
    // Primary uses query-only since CATEGORY_PERSONAL may not exist
    if (labelId !== 'CATEGORY_PERSONAL') {
      params.append('labelIds', labelId);
    }

    // For inbox scope, also require INBOX label
    if (scope === 'inbox' && labelId !== 'SPAM' && labelId !== 'CATEGORY_PERSONAL') {
      params.append('labelIds', 'INBOX');
    }
    if (scope === 'inbox' && labelId === 'CATEGORY_PERSONAL') {
      query += 'in:inbox ';
    }

    params.append('maxResults', String(clampedMaxResults));
    if (query.trim()) params.append('q', query.trim());
    if (pageToken) params.append('pageToken', pageToken as string);

    const queryStr = query.trim();
    console.log(`[messages/${category}] scope: ${scope} | Query: "${queryStr}" | maxResults: ${clampedMaxResults} | pageToken: ${pageToken || 'none'}`);

    // ── Stale-while-revalidate (first page only, no pageToken) ──
    // Any cached entry — fresh or stale — is served immediately. If it's
    // stale we kick off a background refresh so the next request lands on
    // fresh data. This is what makes revisits feel zero-lag.
    if (!pageToken) {
      const cached = getPageCache(req.user!.id, category, scope, clampedMaxResults, queryStr);
      if (cached) {
        const stale = !isPageCacheFresh(cached);
        console.log(`[messages/${category}] CACHE ${stale ? 'STALE-SERVE' : 'HIT'} (${cached.messages.length} msgs, ${Date.now() - cached.fetchedAt}ms old)`);
        if (stale && !isRevalidating(req.user!.id, category, scope, clampedMaxResults, queryStr)) {
          revalidateInBackground(req.user!.id, category, scope, clampedMaxResults, queryStr, params, accessToken, hasFiltersApplied, sortOrder as string | undefined);
        }
        return res.json({
          messages: cached.messages,
          nextPageToken: cached.nextPageToken,
          count: cached.count,
          filteredCount: cached.filteredCount,
          scanning: isRevalidating(req.user!.id, category, scope, clampedMaxResults, queryStr)
        });
      }
    }

    const listData = await gmailFetch(`/messages?${params}`, accessToken);

    console.log(`[messages/${category}] Gmail returned ${listData.messages?.length || 0} messages | nextPageToken: ${listData.nextPageToken ? 'YES' : 'NO'} | estimate: ${listData.resultSizeEstimate}`);

    if (!listData.messages || listData.messages.length === 0) {
      const emptyResult = { messages: [], nextPageToken: null, count: 0, filteredCount: 0 };
      if (!pageToken) {
        setPageCache(req.user!.id, category, scope, clampedMaxResults, queryStr, {
          ...emptyResult, filteredCount: null, fetchedAt: Date.now()
        });
      }
      return res.json({ ...emptyResult, scanning: false });
    }

    const messageIds = listData.messages.map((m: any) => m.id);
    const messages = await fetchMessageBatch(messageIds, accessToken);

    // Sort oldest-first if requested (Gmail API always returns newest first)
    const sortedMessages = sortOrder === 'oldest'
      ? [...messages].sort((a: any, b: any) => {
          const dateA = a.date || '';
          const dateB = b.date || '';
          return dateA.localeCompare(dateB);
        })
      : messages;

    const result = {
      messages: sortedMessages,
      nextPageToken: listData.nextPageToken || null,
      count: listData.resultSizeEstimate || messages.length,
      filteredCount: hasFiltersApplied ? (listData.resultSizeEstimate || messages.length) : null
    };

    // Cache first-page results
    if (!pageToken) {
      setPageCache(req.user!.id, category, scope, clampedMaxResults, queryStr, {
        ...result, fetchedAt: Date.now()
      });
    }

    res.json({ ...result, scanning: false });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get messages error:', error);
    res.status(500).json({ error: 'Failed to fetch messages' });
  }
});

// Get single email full content
router.get('/message/:messageId', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { messageId } = req.params;
    const accessToken = await getValidAccessToken(req.user!.id);

    const msg = await gmailFetch(`/messages/${messageId}?format=full`, accessToken);

    // Extract headers
    const headers = msg.payload?.headers?.reduce((acc: any, h: any) => {
      acc[h.name.toLowerCase()] = h.value;
      return acc;
    }, {}) || {};

    // Extract body content
    let bodyHtml = '';
    let bodyText = '';

    const extractBody = (part: any) => {
      if (!part) return;
      if (part.mimeType === 'text/html' && part.body?.data) {
        bodyHtml = Buffer.from(part.body.data, 'base64url').toString('utf-8');
      } else if (part.mimeType === 'text/plain' && part.body?.data) {
        bodyText = Buffer.from(part.body.data, 'base64url').toString('utf-8');
      }
      if (part.parts) {
        for (const subPart of part.parts) {
          extractBody(subPart);
        }
      }
    };

    extractBody(msg.payload);

    if (!bodyHtml && bodyText) {
      bodyHtml = `<pre style="font-family: -apple-system, sans-serif; white-space: pre-wrap; word-wrap: break-word;">${bodyText.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</pre>`;
    }

    if (!bodyHtml && !bodyText && msg.payload?.body?.data) {
      const decoded = Buffer.from(msg.payload.body.data, 'base64url').toString('utf-8');
      if (msg.payload.mimeType === 'text/html') {
        bodyHtml = decoded;
      } else {
        bodyHtml = `<pre style="font-family: -apple-system, sans-serif; white-space: pre-wrap;">${decoded.replace(/</g, '&lt;').replace(/>/g, '&gt;')}</pre>`;
      }
    }

    // Get attachments info
    const attachments: any[] = [];
    const extractAttachments = (part: any) => {
      if (!part) return;
      if (part.filename && part.filename.length > 0) {
        attachments.push({
          filename: part.filename,
          mimeType: part.mimeType,
          size: part.body?.size || 0,
          attachmentId: part.body?.attachmentId
        });
      }
      if (part.parts) {
        for (const subPart of part.parts) {
          extractAttachments(subPart);
        }
      }
    };
    extractAttachments(msg.payload);

    res.json({
      id: msg.id,
      threadId: msg.threadId,
      snippet: decodeHtmlEntities(msg.snippet || ''),
      labelIds: msg.labelIds,
      isRead: !msg.labelIds?.includes('UNREAD'),
      isStarred: msg.labelIds?.includes('STARRED'),
      from: headers.from || 'Unknown',
      to: headers.to || '',
      cc: headers.cc || '',
      subject: decodeHtmlEntities(headers.subject || '(No subject)'),
      date: headers.date,
      hasUnsubscribe: !!headers['list-unsubscribe'],
      bodyHtml,
      bodyText,
      attachments,
      sizeEstimate: msg.sizeEstimate
    });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get message detail error:', error);
    res.status(500).json({ error: 'Failed to fetch email' });
  }
});

// ---------------------------------------------------------------------------
// GET /messages/refresh — Incremental sync using Gmail History API
// Returns new/changed message IDs since a given historyId, plus updated counts.
// If historyId is stale (410 error), falls back to full category re-count.
// ---------------------------------------------------------------------------
router.get('/refresh', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const { historyId, scope: scopeParam } = req.query;
    const scope = (scopeParam as string) || 'inbox';
    const accessToken = await getValidAccessToken(req.user!.id);

    // Always fetch fresh profile for total count + current historyId
    const profile = await gmailFetch('/profile', accessToken);
    const currentHistoryId = profile.historyId;
    const totalEmails = profile.messagesTotal || 0;

    // If no historyId provided, return current state without diff
    if (!historyId) {
      // Fetch fresh category counts
      const categories = await fetchCategoryCounts(accessToken, scope);
      return res.json({
        historyId: currentHistoryId,
        totalEmails,
        categories,
        newMessageIds: [],
        deletedMessageIds: [],
        hasChanges: false
      });
    }

    // Try incremental sync via History API
    try {
      const params = new URLSearchParams();
      params.append('startHistoryId', historyId as string);
      params.append('historyTypes', 'messageAdded');
      params.append('historyTypes', 'messageDeleted');
      params.append('historyTypes', 'labelAdded');
      params.append('historyTypes', 'labelRemoved');

      let allAdded: string[] = [];
      let allDeleted: string[] = [];
      let pageToken: string | undefined;

      // Paginate through history
      do {
        const historyParams = new URLSearchParams(params);
        if (pageToken) historyParams.append('pageToken', pageToken);

        const data = await gmailFetch(`/history?${historyParams}`, accessToken);

        if (data.history) {
          for (const record of data.history) {
            if (record.messagesAdded) {
              for (const item of record.messagesAdded) {
                allAdded.push(item.message.id);
              }
            }
            if (record.messagesDeleted) {
              for (const item of record.messagesDeleted) {
                allDeleted.push(item.message.id);
              }
            }
          }
        }

        pageToken = data.nextPageToken;
      } while (pageToken);

      // Deduplicate
      const newMessageIds = [...new Set(allAdded)];
      const deletedMessageIds = [...new Set(allDeleted)];
      const hasChanges = newMessageIds.length > 0 || deletedMessageIds.length > 0;

      // If there are changes, also refresh category counts
      let categories;
      if (hasChanges) {
        categories = await fetchCategoryCounts(accessToken, scope);
      }

      console.log(`[refresh] historyId ${historyId} → ${currentHistoryId} | +${newMessageIds.length} -${deletedMessageIds.length}`);

      return res.json({
        historyId: currentHistoryId,
        totalEmails,
        categories: categories || undefined,
        newMessageIds: newMessageIds.slice(0, 100), // Cap to prevent huge responses
        deletedMessageIds: deletedMessageIds.slice(0, 100),
        hasChanges
      });

    } catch (historyError: any) {
      // 404 = historyId too old, Gmail purged it. Fall back to full refresh.
      if (historyError.message?.includes('404')) {
        console.log(`[refresh] historyId ${historyId} expired — full refresh`);
        const categories = await fetchCategoryCounts(accessToken, scope);
        return res.json({
          historyId: currentHistoryId,
          totalEmails,
          categories,
          newMessageIds: [],
          deletedMessageIds: [],
          hasChanges: true, // Force UI to reload
          historyExpired: true
        });
      }
      throw historyError;
    }

  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Refresh error:', error);
    res.status(500).json({ error: 'Failed to refresh email data' });
  }
});

// Helper: fetch fresh category counts
async function fetchCategoryCounts(accessToken: string, scope: string) {
  const entries = Object.entries(GMAIL_CATEGORIES);
  return Promise.all(
    entries.map(async ([name, labelId]) => {
      try {
        if (scope === 'inbox') {
          const categoryQuery: Record<string, string> = {
            'CATEGORY_PERSONAL': 'in:inbox category:primary -in:trash -in:draft',
            'CATEGORY_SOCIAL': 'in:inbox category:social -in:trash -in:draft',
            'CATEGORY_PROMOTIONS': 'in:inbox category:promotions -in:trash -in:draft',
            'CATEGORY_UPDATES': 'in:inbox category:updates -in:trash -in:draft',
            'CATEGORY_FORUMS': 'in:inbox category:forums -in:trash -in:draft',
            'SPAM': 'in:spam -in:draft',
          };
          const query = categoryQuery[labelId] || `-in:trash -in:draft label:${labelId}`;
          const count = await countAllMessages([], accessToken, query);
          return { id: name, labelId, count };
        } else {
          if (labelId === 'CATEGORY_PERSONAL') {
            try {
              const data = await gmailFetch(`/labels/${labelId}`, accessToken);
              return { id: name, labelId, count: data.messagesTotal || 0 };
            } catch {
              const count = await countAllMessages([], accessToken, 'category:primary -in:trash -in:draft');
              return { id: name, labelId, count };
            }
          }
          const data = await gmailFetch(`/labels/${labelId}`, accessToken);
          return { id: name, labelId, count: data.messagesTotal || 0 };
        }
      } catch {
        return { id: name, labelId, count: 0 };
      }
    })
  );
}

export default router;
