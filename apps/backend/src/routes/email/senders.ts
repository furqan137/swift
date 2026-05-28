import { Router, Response } from 'express';
import { AuthenticatedRequest, authenticateToken } from '../../middleware/auth.js';
import {
  GmailTokenExpiredError,
  getValidAccessToken,
  gmailFetch,
  fetchSenderHeaders,
  delay,
  GMAIL_CATEGORIES,
  invalidateTokenCache
} from './helpers.js';
const router = Router();

// Kept-sender persistence lives on the iOS device (see
// BeeClean/Services/LocalKeptStore.swift). The old `email_kept_senders`
// table + routes + in-memory cache were removed when the feature moved
// client-side — the client filters its own list.

// Per-user cache and lock for senders to prevent duplicate scans
const senderScanLocks = new Map<string, boolean>();
const senderCache = new Map<string, { senders: any[]; totalSenders: number; totalEmails: number; ts: number }>();

// Per-user cache and lock for single-category sender scans
const categorySenderLocks = new Map<string, boolean>();
const categorySenderCache = new Map<string, { senders: any[]; totalSenders: number; totalEmails: number; ts: number }>();

// Invalidate all sender caches for a user (called after delete/unsubscribe)
export function invalidateSenderCaches(userId: string) {
  senderCache.delete(userId);
  // Clear all category-specific caches for this user
  for (const key of categorySenderCache.keys()) {
    if (key.startsWith(`${userId}:`)) {
      categorySenderCache.delete(key);
    }
  }
  console.log(`[senders] Cache invalidated for user ${userId.substring(0, 8)}...`);
}

// ---------------------------------------------------------------------------
// Shared: collect message IDs for a set of labels, with concurrency
// ---------------------------------------------------------------------------
// Map label IDs to query strings for reliable pagination (no labelIds mixing)
const LABEL_TO_QUERY: Record<string, string> = {
  'CATEGORY_PERSONAL': 'category:primary -in:trash -in:draft',
  'CATEGORY_SOCIAL': 'category:social -in:trash -in:draft',
  'CATEGORY_PROMOTIONS': 'category:promotions -in:trash -in:draft',
  'CATEGORY_UPDATES': 'category:updates -in:trash -in:draft',
  'CATEGORY_FORUMS': 'category:forums -in:trash -in:draft',
  'SPAM': 'in:spam -in:draft',
};

async function collectMessageIds(
  labelConfigs: { labelId: string; scope: string }[],
  accessToken: string
): Promise<string[]> {
  const seenIds = new Set<string>();
  const allIds: string[] = [];

  // Scan ALL labels concurrently. No artificial caps — the loop runs
  // until Gmail returns no `nextPageToken`, which is the API's signal
  // that we've exhausted every email matching the query. Whatever the
  // user has, we scan in full.
  const chunkResults = await Promise.all(
    labelConfigs.map(async ({ labelId, scope }) => {
      const ids: string[] = [];
      let pageToken: string | undefined;
      let pageCount = 0;

      let query = LABEL_TO_QUERY[labelId] || `-in:trash -in:draft label:${labelId}`;
      if (scope === 'inbox' && labelId !== 'SPAM') {
        query += ' in:inbox';
      }

      try {
        do {
          const params = new URLSearchParams();
          params.append('q', query);
          params.append('maxResults', '500');
          if (pageToken) params.append('pageToken', pageToken);

          const data = await gmailFetch(`/messages?${params}`, accessToken);

          if (data.messages) {
            for (const m of data.messages) {
              ids.push(m.id);
            }
          }

          pageToken = data.nextPageToken;
          pageCount++;
        } while (pageToken);
      } catch (error) {
        console.error(`[collectIds] Error for ${labelId}:`, error);
      }

      console.log(`[collectIds] ${labelId}: ${ids.length} IDs in ${pageCount} pages`);
      return ids;
    })
  );

  for (const ids of chunkResults) {
    for (const id of ids) {
      if (!seenIds.has(id)) {
        seenIds.add(id);
        allIds.push(id);
      }
    }
  }

  return allIds;
}

// ---------------------------------------------------------------------------
// Shared: group header results into sender objects
// ---------------------------------------------------------------------------
function groupBySender(headerResults: { from: string; hasUnsubscribe: boolean }[]) {
  const senderMap = new Map<string, { name: string; email: string; count: number; hasUnsubscribe: boolean }>();

  for (const msg of headerResults) {
    if (!msg?.from) continue;

    const match = msg.from.match(/(?:"?([^"<]*)"?\s*)?<?([^>]+@[^>]+)>?/);
    if (!match || !match[2]) continue;

    const email = match[2].toLowerCase().trim();
    if (!email || !email.includes('@')) continue;
    const name = (match[1]?.trim() || email).replace(/^["']+|["']+$/g, '').trim();

    if (senderMap.has(email)) {
      const existing = senderMap.get(email)!;
      existing.count++;
      existing.hasUnsubscribe = existing.hasUnsubscribe || msg.hasUnsubscribe;
    } else {
      senderMap.set(email, { name: name || email, email, count: 1, hasUnsubscribe: msg.hasUnsubscribe });
    }
  }

  const senders = Array.from(senderMap.values()).sort((a, b) => b.count - a.count);
  const totalEmails = senders.reduce((sum, s) => sum + s.count, 0);

  return { senders, totalSenders: senderMap.size, totalEmails };
}

// ---------------------------------------------------------------------------
// GET /senders/:category — lighter scan for Quick Clean mode
// ---------------------------------------------------------------------------
router.get('/senders/:category', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const category = req.params.category.toLowerCase();
    const scope = (req.query.scope as string) || 'all';
    const forceRefresh = req.query.refresh === 'true';

    const labelId = GMAIL_CATEGORIES[category];
    if (!labelId) {
      return res.status(400).json({ error: `Invalid category: ${category}. Valid: ${Object.keys(GMAIL_CATEGORIES).join(', ')}` });
    }

    const cacheKey = `${userId}:${category}`;

    // 5-minute TTL — short enough that new senders surface quickly on natural revisits.
    // Kept-sender filtering happens on the device.
    const cached = categorySenderCache.get(cacheKey);
    if (!forceRefresh && cached && Date.now() - cached.ts < 5 * 60 * 1000) {
      console.log(`[senders/${category}] Cache hit (${cached.senders.length} senders)`);
      return res.json({
        senders: cached.senders,
        totalSenders: cached.senders.length,
        totalEmails: cached.totalEmails,
        scanning: false
      });
    }

    if (categorySenderLocks.has(cacheKey)) {
      // Another request is already scanning — return whatever the bg scan
      // has put in the cache so far + scanning:true so the client polls.
      const partial = cached?.senders || [];
      return res.json({
        senders: partial,
        totalSenders: partial.length,
        totalEmails: cached?.totalEmails || 0,
        scanning: true
      });
    }

    categorySenderLocks.set(cacheKey, true);

    let accessToken: string;
    try {
      accessToken = await getValidAccessToken(userId);
    } catch (e) {
      categorySenderLocks.delete(cacheKey);
      throw e;
    }

    // Return current cache immediately + scanning:true; the wave-based scan
    // fills the cache progressively so polling clients see live updates.
    res.json({
      senders: cached?.senders || [],
      totalSenders: cached?.senders?.length || 0,
      totalEmails: cached?.totalEmails || 0,
      scanning: true
    });

    // ── Background progressive scan (mirror of /senders pattern) ──
    (async () => {
      try {
        console.log(`[senders/${category}] Phase 1: collecting IDs...`);
        // No cap. Pagination terminates when Gmail returns no
        // `nextPageToken`, which means every email in this category
        // matching the query has been collected.
        const allIds = await collectMessageIds(
          [{ labelId, scope }],
          accessToken
        );
        console.log(`[senders/${category}] Phase 1 done: ${allIds.length} IDs`);

        const BATCH_SIZE = 100;
        const CONCURRENT = 5;
        const allHeaders: { from: string; hasUnsubscribe: boolean }[] = [];
        const chunks: string[][] = [];
        for (let i = 0; i < allIds.length; i += BATCH_SIZE) {
          chunks.push(allIds.slice(i, i + BATCH_SIZE));
        }

        for (let w = 0; w < chunks.length; w += CONCURRENT) {
          const wave = chunks.slice(w, w + CONCURRENT);
          const waveHeaders = await fetchSenderHeaders(
            wave.flat(),
            accessToken,
            100
          );
          allHeaders.push(...waveHeaders);

          // Update cache every wave so polling clients see progress
          const partial = groupBySender(allHeaders);
          categorySenderCache.set(cacheKey, { ...partial, ts: Date.now() });
          console.log(`[senders/${category}] Progressive: ${allHeaders.length}/${allIds.length} → ${partial.senders.length} senders`);
        }

        const result = groupBySender(allHeaders);
        categorySenderCache.set(cacheKey, { ...result, ts: Date.now() });
        console.log(`[senders/${category}] DONE: ${result.senders.length} senders, ${result.totalEmails} emails`);
      } catch (error) {
        console.error(`[senders/${category}] Background scan error:`, error);
      } finally {
        categorySenderLocks.delete(cacheKey);
      }
    })();
  } catch (error) {
    const cacheKey = `${req.user!.id}:${req.params.category.toLowerCase()}`;
    categorySenderLocks.delete(cacheKey);
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get category senders error:', error);
    res.status(500).json({ error: 'Failed to fetch category senders' });
  }
});

// ---------------------------------------------------------------------------
// GET /senders — DEEP scan across all subscription categories
// ---------------------------------------------------------------------------
router.get('/senders', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const userId = req.user!.id;
    const scope = (req.query.scope as string) || 'all';
    const forceRefresh = req.query.refresh === 'true';

    // Kept-sender filtering lives on-device. Server returns the full list
    // and the client's LocalKeptStore filters before display.

    // 60-second TTL — was 5 min, but users opening Unsubscribe were
    // getting stranded on a stale partial scan from a prior session
    // ("only 53 senders" on TestFlight). Tighter TTL plus the iOS layer
    // sending refresh=true on every Unsubscribe entry guarantees a fresh
    // wave-based scan when the user actually wants to act on it.
    const cached = senderCache.get(userId);
    if (!forceRefresh && cached && Date.now() - cached.ts < 60 * 1000) {
      console.log(`[senders] Cache hit (${cached.senders.length} senders, ${cached.totalEmails} emails)`);
      return res.json({
        senders: cached.senders,
        totalSenders: cached.senders.length,
        totalEmails: cached.totalEmails,
        scanning: false
      });
    }

    if (senderScanLocks.has(userId)) {
      // Scan in progress — return partial results from cache (updated progressively)
      const partial = senderCache.get(userId);
      return res.json({
        senders: partial?.senders || [],
        totalSenders: partial?.senders?.length || 0,
        totalEmails: partial?.totalEmails || 0,
        scanning: true
      });
    }

    senderScanLocks.set(userId, true);

    let accessToken: string;
    try {
      accessToken = await getValidAccessToken(userId);
    } catch (e) {
      senderScanLocks.delete(userId);
      throw e;
    }

    // Return current cache immediately, then kick off background scan
    const currentCache = senderCache.get(userId);
    res.json({
      senders: currentCache?.senders || [],
      totalSenders: currentCache?.senders?.length || 0,
      totalEmails: currentCache?.totalEmails || 0,
      scanning: true
    });

    // --- Background progressive scan (updates cache as it goes) ---
    (async () => {
      try {
        // Scan multiple query scopes in parallel for maximum coverage + speed
        const scanQueries = [
          '-in:trash -in:draft -in:sent',             // All received mail
          'category:primary -in:trash -in:draft',      // Primary inbox — the all-mail query above
                                                       // tends to hit its 200k cap before primary
                                                       // contacts get fully harvested for users with
                                                       // promo/update-heavy mailboxes. Querying primary
                                                       // explicitly + deduping below guarantees
                                                       // first-class coverage of the people they
                                                       // actually correspond with.
          'category:promotions -in:trash -in:draft',   // Promotions specifically (biggest sender pool)
          'category:updates -in:trash -in:draft',      // Updates (receipts, notifications)
          'category:social -in:trash -in:draft',       // Social notifications
        ];

        console.log(`[senders] Phase 1: Collecting IDs from ${scanQueries.length} parallel scans...`);
        const seenIds = new Set<string>();
        const allIds: string[] = [];
        // No cap. Each query paginates until Gmail returns no
        // `nextPageToken`, meaning every email matching the query has
        // been collected. Five queries run in parallel; the dedupe pass
        // below merges them into the final ID list.

        const queryResults = await Promise.all(
          scanQueries.map(async (query) => {
            const ids: string[] = [];
            let pageToken: string | undefined;
            let pages = 0;
            try {
              do {
                const params = new URLSearchParams();
                params.append('q', query);
                params.append('maxResults', '500');
                if (pageToken) params.append('pageToken', pageToken);
                const data = await gmailFetch(`/messages?${params}`, accessToken);
                if (data.messages) {
                  for (const m of data.messages) ids.push(m.id);
                }
                pageToken = data.nextPageToken;
                pages++;
              } while (pageToken);
            } catch (e) {
              console.error(`[senders] Query "${query.substring(0, 30)}..." error:`, e);
            }
            console.log(`[senders] Query "${query.substring(0, 30)}...": ${ids.length} IDs in ${pages} pages`);
            return ids;
          })
        );

        // Merge and deduplicate
        for (const ids of queryResults) {
          for (const id of ids) {
            if (!seenIds.has(id)) {
              seenIds.add(id);
              allIds.push(id);
            }
          }
        }
        console.log(`[senders] Phase 1 done: ${allIds.length} IDs`);

        // Phase 2: Fetch headers in waves, updating cache after each wave
        const BATCH_SIZE = 100;
        const CONCURRENT = 5;
        const allHeaders: { from: string; hasUnsubscribe: boolean }[] = [];
        const chunks: string[][] = [];
        for (let i = 0; i < allIds.length; i += BATCH_SIZE) {
          chunks.push(allIds.slice(i, i + BATCH_SIZE));
        }

        for (let w = 0; w < chunks.length; w += CONCURRENT) {
          const wave = chunks.slice(w, w + CONCURRENT);
          const waveHeaders = await fetchSenderHeaders(
            wave.flat(),
            accessToken,
            100
          );
          allHeaders.push(...waveHeaders);

          // Update cache every wave so polling clients see progress in near-real-time
          const partial = groupBySender(allHeaders);
          senderCache.set(userId, { ...partial, ts: Date.now() });
          console.log(`[senders] Progressive: ${allHeaders.length}/${allIds.length} → ${partial.senders.length} senders`);
        }

        // Final update
        const result = groupBySender(allHeaders);
        senderCache.set(userId, { ...result, ts: Date.now() });
        console.log(`[senders] DONE: ${result.senders.length} senders, ${result.totalEmails} emails from ${allHeaders.length} messages`);
      } catch (error) {
        console.error('[senders] Background scan error:', error);
      } finally {
        // `finally` (not in both success + catch) so a throw between
        // the final `senderCache.set` and the lock-delete — or any
        // future code added to the success path — can't leak the lock
        // and trap the user's next /senders call returning stale
        // `scanning: true` forever. Matches the /senders/:category
        // pattern below.
        senderScanLocks.delete(userId);
      }
    })();
  } catch (error) {
    senderScanLocks.delete(req.user!.id);
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get senders error:', error);
    res.status(500).json({ error: 'Failed to fetch senders' });
  }
});

// Kept-sender routes (POST /senders/keep, POST /senders/unkeep,
// GET /senders/kept) were removed — the iOS app now persists the kept set
// on-device via LocalKeptStore. See BeeClean/Services/LocalKeptStore.swift.

export default router;
