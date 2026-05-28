import { Router, Response } from 'express';
import { AuthenticatedRequest, authenticateToken } from '../../middleware/auth.js';
import {
  GMAIL_CATEGORIES,
  GmailTokenExpiredError,
  getValidAccessToken,
  gmailFetch,
  countAllMessages,
  invalidateTokenCache,
  getGmailCredentials,
  refreshAccessToken
} from './helpers.js';

const router = Router();

// Per-user category-count cache. Counts don't change often; serve stale
// instantly and revalidate in the background so revisits feel zero-lag.
interface CachedCategories {
  payload: { categories: Array<{ id: string; name: string; labelId: string; count: number }>; scope: string; totalEmails: number };
  fetchedAt: number;
}
const categoryCache = new Map<string, CachedCategories>();
const CATEGORY_CACHE_TTL = 2 * 60 * 1000; // 2 min fresh
const categoryRevalidating = new Set<string>();

function categoryCacheKey(userId: string, scope: string): string {
  return `${userId}:${scope}`;
}

export function invalidateCategoryCache(userId: string): void {
  for (const key of categoryCache.keys()) {
    if (key.startsWith(userId + ':')) categoryCache.delete(key);
  }
}

// Verify which Gmail account the stored access token belongs to
router.get('/profile', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const accessToken = await getValidAccessToken(req.user!.id);

    if (!accessToken) {
      return res.status(401).json({ error: 'no_token', message: 'No Google access token stored' });
    }

    const profile = await gmailFetch('/profile', accessToken);

    console.log(`[profile] Token belongs to: ${profile.emailAddress} (user expects: ${req.user!.email})`);

    const tokenEmail = (profile.emailAddress || '').toLowerCase();
    const userEmail = (req.user!.email || '').toLowerCase();
    const matches = tokenEmail === userEmail;

    if (!matches) {
      console.warn(`[profile] TOKEN MISMATCH: token=${tokenEmail}, user=${userEmail}`);
    }

    res.json({
      email: profile.emailAddress,
      messagesTotal: profile.messagesTotal,
      threadsTotal: profile.threadsTotal,
      historyId: profile.historyId,
      matches
    });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Profile check error:', error);
    res.status(500).json({ error: 'Failed to verify Gmail profile' });
  }
});

async function fetchCategoriesFromGmail(accessToken: string, scope: 'all' | 'inbox') {
  const entries = Object.entries(GMAIL_CATEGORIES);
  const categoryDisplayName = (name: string, labelId: string) =>
    labelId === 'CATEGORY_PERSONAL' ? 'Primary' : name.charAt(0).toUpperCase() + name.slice(1);

  const profile = await gmailFetch('/profile', accessToken).catch(() => null);

  const categoryQueryMap: Record<string, string> = {
    'CATEGORY_PERSONAL': 'in:inbox category:primary -in:trash -in:draft',
    'CATEGORY_SOCIAL': 'in:inbox category:social -in:trash -in:draft',
    'CATEGORY_PROMOTIONS': 'in:inbox category:promotions -in:trash -in:draft',
    'CATEGORY_UPDATES': 'in:inbox category:updates -in:trash -in:draft',
    'CATEGORY_FORUMS': 'in:inbox category:forums -in:trash -in:draft',
    'SPAM': 'in:spam -in:draft',
  };

  // Fan out all 6 category counts in parallel — Gmail per-user quota is
  // 250 units/sec and each /labels call costs 1 unit, so 6 simultaneous
  // calls are well within budget. Previously this loop awaited sequentially
  // with a 120ms delay between iterations (~700ms+ overhead).
  const results = await Promise.allSettled(
    entries.map(async ([name, labelId]) => {
      if (scope === 'all') {
        if (labelId === 'CATEGORY_PERSONAL') {
          try {
            const data = await gmailFetch(`/labels/${labelId}`, accessToken);
            return { id: name, name: 'Primary', labelId, count: data.messagesTotal || 0 };
          } catch {
            const count = await countAllMessages([], accessToken, 'category:primary -in:trash -in:draft');
            return { id: name, name: 'Primary', labelId, count };
          }
        }
        const data = await gmailFetch(`/labels/${labelId}`, accessToken);
        return { id: name, name: categoryDisplayName(name, labelId), labelId, count: data.messagesTotal || 0 };
      }
      const query = categoryQueryMap[labelId] || `-in:trash -in:draft label:${labelId}`;
      const count = await countAllMessages([], accessToken, query);
      return { id: name, name: categoryDisplayName(name, labelId), labelId, count };
    })
  );

  const categories: Array<{ id: string; name: string; labelId: string; count: number }> = [];
  for (let i = 0; i < results.length; i++) {
    const result = results[i];
    const [name, labelId] = entries[i];
    if (result.status === 'fulfilled') {
      categories.push(result.value);
    } else {
      // Surface token expiry so the route handler can refresh + retry.
      if (result.reason instanceof GmailTokenExpiredError) throw result.reason;
      console.error(`[categories] Error fetching ${name}:`, result.reason);
      categories.push({ id: name, name: categoryDisplayName(name, labelId), labelId, count: 0 });
    }
  }

  const categoryTotal = categories.reduce((sum: number, c: any) => sum + (c.count || 0), 0);
  const gmailTotal = profile?.messagesTotal || 0;

  return { categories, scope, totalEmails: Math.max(categoryTotal, gmailTotal) };
}

// Get email category counts (stale-while-revalidate)
router.get('/categories', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const rawScope = (req.query.scope as string) || 'all';
    const scope: 'all' | 'inbox' = rawScope === 'inbox' ? 'inbox' : 'all';
    const userId = req.user!.id;
    const cacheKey = categoryCacheKey(userId, scope);

    const cached = categoryCache.get(cacheKey);
    if (cached) {
      const stale = Date.now() - cached.fetchedAt >= CATEGORY_CACHE_TTL;
      console.log(`[categories] CACHE ${stale ? 'STALE-SERVE' : 'HIT'} (age ${Date.now() - cached.fetchedAt}ms)`);
      if (stale && !categoryRevalidating.has(cacheKey)) {
        categoryRevalidating.add(cacheKey);
        (async () => {
          try {
            let accessToken = await getValidAccessToken(userId);
            let fresh;
            try {
              fresh = await fetchCategoriesFromGmail(accessToken, scope);
            } catch (innerErr) {
              if (innerErr instanceof GmailTokenExpiredError) {
                invalidateTokenCache(userId);
                const { refreshToken } = await getGmailCredentials(userId);
                if (!refreshToken) throw innerErr;
                accessToken = await refreshAccessToken(userId, refreshToken);
                fresh = await fetchCategoriesFromGmail(accessToken, scope);
              } else {
                throw innerErr;
              }
            }
            categoryCache.set(cacheKey, { payload: fresh, fetchedAt: Date.now() });
            console.log(`[categories] Background revalidate done`);
          } catch (e) {
            console.error('[categories] Background revalidate failed:', e);
          } finally {
            categoryRevalidating.delete(cacheKey);
          }
        })();
      }
      return res.json({ ...cached.payload, scanning: categoryRevalidating.has(cacheKey) });
    }

    let accessToken = await getValidAccessToken(userId);
    let payload;
    try {
      payload = await fetchCategoriesFromGmail(accessToken, scope);
    } catch (err) {
      if (err instanceof GmailTokenExpiredError) {
        // Refresh once, then retry. The cached token was stale.
        invalidateTokenCache(userId);
        const { refreshToken } = await getGmailCredentials(userId);
        if (!refreshToken) throw err;
        accessToken = await refreshAccessToken(userId, refreshToken);
        payload = await fetchCategoriesFromGmail(accessToken, scope);
      } else {
        throw err;
      }
    }
    categoryCache.set(cacheKey, { payload, fetchedAt: Date.now() });
    res.json({ ...payload, scanning: false });
  } catch (error) {
    if (error instanceof GmailTokenExpiredError) {
      invalidateTokenCache(req.user!.id);
      return res.status(401).json({ error: 'token_expired' });
    }
    console.error('Get categories error:', error);
    res.status(500).json({ error: 'Failed to fetch email categories' });
  }
});

export default router;
