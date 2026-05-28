import { OAuth2Client } from 'google-auth-library';
import { config } from '../../config/index.js';
import { supabaseService } from '../../services/supabase.service.js';

const supabaseAdmin = supabaseService.getAdminClient();

// Gmail category labels
export const GMAIL_CATEGORIES: Record<string, string> = {
  primary: 'CATEGORY_PERSONAL',
  social: 'CATEGORY_SOCIAL',
  promotions: 'CATEGORY_PROMOTIONS',
  updates: 'CATEGORY_UPDATES',
  forums: 'CATEGORY_FORUMS',
  spam: 'SPAM'
};

export class GmailTokenExpiredError extends Error {
  userId?: string;
  constructor(userId?: string) {
    super('Google access token expired');
    this.name = 'GmailTokenExpiredError';
    this.userId = userId;
    // Bust the token cache so next request gets a fresh token
    if (userId) tokenCache.delete(userId);
  }
}

// Allow routes to invalidate token cache on 401
export function invalidateTokenCache(userId: string) {
  tokenCache.delete(userId);
}

export const delay = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

export const getGmailCredentials = async (userId: string) => {
  const { data: user, error } = await supabaseAdmin
    .from('users')
    .select('google_access_token, google_refresh_token')
    .eq('id', userId)
    .single();

  if (error || !user) {
    throw new Error('User not found');
  }

  return {
    accessToken: user.google_access_token,
    refreshToken: user.google_refresh_token
  };
};

// Forward declaration — tokenCache defined below getValidAccessToken
export const refreshAccessToken = async (userId: string, refreshToken: string): Promise<string> => {
  // Bust cache so stale token isn't served during refresh
  tokenCache.delete(userId);
  const oauth2Client = new OAuth2Client(
    config.google.clientId,
    config.google.clientSecret,
    config.google.redirectUri
  );
  oauth2Client.setCredentials({ refresh_token: refreshToken });

  const { credentials } = await oauth2Client.refreshAccessToken();
  const newAccessToken = credentials.access_token!;

  const update: Record<string, string> = { google_access_token: newAccessToken };
  if (credentials.refresh_token) {
    update.google_refresh_token = credentials.refresh_token;
  }
  await supabaseAdmin.from('users').update(update).eq('id', userId);

  console.log(`[refreshAccessToken] Refreshed token for user ${userId.substring(0, 8)}...`);
  return newAccessToken;
};

// Per-user refresh lock to prevent concurrent token refresh storms
const refreshLocks = new Map<string, Promise<string>>();

// Cache validated tokens so we don't hit /profile on every single request
const tokenCache = new Map<string, { token: string; validUntil: number }>();
const TOKEN_CACHE_TTL = 4 * 60 * 1000; // 4 minutes (Google tokens last ~60 min, so this is very safe)

export const getValidAccessToken = async (userId: string): Promise<string> => {
  // Check in-memory cache first — avoids DB + Google round-trip entirely
  const cached = tokenCache.get(userId);
  if (cached && Date.now() < cached.validUntil) {
    return cached.token;
  }

  const { accessToken, refreshToken } = await getGmailCredentials(userId);

  if (!accessToken) {
    if (refreshToken) {
      const newToken = await lockedRefresh(userId, refreshToken);
      tokenCache.set(userId, { token: newToken, validUntil: Date.now() + TOKEN_CACHE_TTL });
      return newToken;
    }
    throw new GmailTokenExpiredError();
  }

  // Trust the token without a /profile round-trip. If it's expired,
  // gmailFetch will get a 401 and the caller's catch block handles refresh.
  tokenCache.set(userId, { token: accessToken, validUntil: Date.now() + TOKEN_CACHE_TTL });
  return accessToken;
};

// Ensure only one refresh runs per user at a time
async function lockedRefresh(userId: string, refreshToken: string): Promise<string> {
  const existing = refreshLocks.get(userId);
  if (existing) {
    return existing; // piggyback on in-flight refresh
  }

  const promise = refreshAccessToken(userId, refreshToken).finally(() => {
    refreshLocks.delete(userId);
  });
  refreshLocks.set(userId, promise);
  return promise;
}

// ---------------------------------------------------------------------------
// Gmail API fetch with retry + exponential backoff on 429/403
// ---------------------------------------------------------------------------
export const gmailFetch = async (
  endpoint: string,
  accessToken: string,
  options: RequestInit = {},
  retries = 4
): Promise<any> => {
  // Abort after 15 seconds to prevent hanging requests
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 15_000);

  let response: globalThis.Response;
  try {
    response = await fetch(`https://gmail.googleapis.com/gmail/v1/users/me${endpoint}`, {
      ...options,
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
        ...options.headers
      }
    });
  } catch (err: any) {
    clearTimeout(timeoutId);
    if (err.name === 'AbortError') {
      throw new Error(`Gmail API timeout: ${endpoint.substring(0, 80)}`);
    }
    throw err;
  }
  clearTimeout(timeoutId);

  if (!response.ok) {
    if (response.status === 401) {
      throw new GmailTokenExpiredError();
    }

    const errorBody = await response.text();
    const isQuotaError = response.status === 429 ||
      (response.status === 403 && errorBody.includes('Quota exceeded'));

    if (isQuotaError && retries > 0) {
      const attempt = 5 - retries;
      const backoffMs = Math.min(2000 * Math.pow(2, attempt), 30000);
      console.log(`[gmailFetch] Rate limited (${response.status}), backoff ${backoffMs}ms (${retries} left)`);
      await delay(backoffMs);
      return gmailFetch(endpoint, accessToken, options, retries - 1);
    }

    console.error('Gmail API error:', response.status, endpoint.substring(0, 80), errorBody.substring(0, 200));
    throw new Error(`Gmail API error: ${response.status}`);
  }

  const contentType = response.headers.get('content-type') || '';
  if (response.status === 204 || !contentType.includes('application/json')) {
    return {};
  }

  const text = await response.text();
  if (!text || text.trim().length === 0) return {};

  try {
    return JSON.parse(text);
  } catch {
    return {};
  }
};

// ---------------------------------------------------------------------------
// HTML entity decoding for snippets
// ---------------------------------------------------------------------------
export const decodeHtmlEntities = (text: string): string => {
  return text
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&#160;/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#x27;/g, "'")
    .replace(/&#x2F;/g, '/')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, num) => String.fromCharCode(parseInt(num, 10)))
    .replace(/\s+/g, ' ')
    .trim();
};

// ---------------------------------------------------------------------------
// Gmail Batch API — send up to 100 individual requests in ONE HTTP call
// Returns parsed JSON responses for each sub-request
// ---------------------------------------------------------------------------
async function gmailBatchFetch(
  endpoints: string[],
  accessToken: string
): Promise<(any | null)[]> {
  const BATCH_URL = 'https://www.googleapis.com/batch/gmail/v1';
  const boundary = `batch_beeclean_${Date.now()}`;

  // Build multipart body
  let body = '';
  for (let i = 0; i < endpoints.length; i++) {
    body += `--${boundary}\r\n`;
    body += 'Content-Type: application/http\r\n';
    body += `Content-ID: <item${i}>\r\n\r\n`;
    body += `GET /gmail/v1/users/me${endpoints[i]} HTTP/1.1\r\n\r\n`;
  }
  body += `--${boundary}--`;

  const response = await fetch(BATCH_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': `multipart/mixed; boundary=${boundary}`,
    },
    body,
  });

  if (!response.ok) {
    if (response.status === 401) throw new GmailTokenExpiredError();
    const errText = await response.text();
    // If rate limited, throw so caller can retry
    if (response.status === 429 || (response.status === 403 && errText.includes('Quota'))) {
      throw new Error(`BATCH_RATE_LIMITED:${response.status}`);
    }
    throw new Error(`Batch API error: ${response.status}`);
  }

  const responseText = await response.text();

  // Parse multipart response — extract JSON bodies
  const results: (any | null)[] = new Array(endpoints.length).fill(null);

  // Split by boundary
  const responseBoundary = response.headers.get('content-type')?.match(/boundary=(.+)/)?.[1];
  if (!responseBoundary) return results;

  const parts = responseText.split(`--${responseBoundary}`);
  for (const part of parts) {
    if (part.trim() === '' || part.trim() === '--') continue;

    // Extract Content-ID to match response to request
    const idMatch = part.match(/Content-ID:\s*<response-item(\d+)>/i);
    const idx = idMatch ? parseInt(idMatch[1], 10) : -1;

    // Extract JSON body (after the HTTP status line and headers)
    const jsonMatch = part.match(/\{[\s\S]*\}/);
    if (jsonMatch && idx >= 0 && idx < results.length) {
      try {
        results[idx] = JSON.parse(jsonMatch[0]);
      } catch {
        // Skip malformed responses
      }
    }
  }

  return results;
}

// ---------------------------------------------------------------------------
// Fetch sender headers using Gmail Batch API — FAST
// 100 messages per HTTP call. 5,000 messages = ~50 HTTP calls.
// With 3 concurrent batch calls = ~17 rounds × ~200ms = ~3-4 seconds.
// ---------------------------------------------------------------------------
export const fetchSenderHeaders = async (
  ids: string[],
  accessToken: string,
  _batchSize = 100 // ignored legacy param, always uses 100 (Gmail batch limit)
): Promise<{ from: string; hasUnsubscribe: boolean }[]> => {
  const results: { from: string; hasUnsubscribe: boolean }[] = [];
  const total = ids.length;
  const BATCH_SIZE = 100; // Gmail batch API max
  const CONCURRENT_BATCHES = 5; // Fire 5 batch calls at once (500 msgs per wave)

  // Build all batch chunks
  const chunks: string[][] = [];
  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    chunks.push(ids.slice(i, i + BATCH_SIZE));
  }

  // Process chunks in concurrent waves
  for (let w = 0; w < chunks.length; w += CONCURRENT_BATCHES) {
    const wave = chunks.slice(w, w + CONCURRENT_BATCHES);

    const waveResults = await Promise.all(
      wave.map(async (chunk) => {
        const endpoints = chunk.map(id =>
          `/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=List-Unsubscribe&fields=payload/headers`
        );

        try {
          return await gmailBatchFetch(endpoints, accessToken);
        } catch (error) {
          const errMsg = (error as Error).message || '';
          if (errMsg.startsWith('BATCH_RATE_LIMITED')) {
            // Backoff and retry this chunk individually
            console.log(`[fetchSenderHeaders] Batch rate limited, falling back to individual for ${chunk.length} msgs`);
            await delay(2000);
            return await Promise.all(
              chunk.map(async (id) => {
                try {
                  return await gmailFetch(
                    `/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=List-Unsubscribe&fields=payload/headers`,
                    accessToken
                  );
                } catch { return null; }
              })
            );
          }
          console.error('[fetchSenderHeaders] Batch error:', error);
          return new Array(chunk.length).fill(null);
        }
      })
    );

    // Parse results
    for (const batchResult of waveResults) {
      for (const msg of batchResult) {
        if (!msg?.payload?.headers) continue;
        const headers: Record<string, string> = {};
        for (const h of msg.payload.headers) {
          headers[h.name.toLowerCase()] = h.value;
        }
        if (headers.from) {
          results.push({
            from: headers.from,
            hasUnsubscribe: !!headers['list-unsubscribe']
          });
        }
      }
    }

    const done = Math.min((w + CONCURRENT_BATCHES) * BATCH_SIZE, total);
    if (done < total) {
      console.log(`[fetchSenderHeaders] ${done}/${total}`);
    }
  }

  console.log(`[fetchSenderHeaders] Done: ${results.length}/${total}`);
  return results;
};

// ---------------------------------------------------------------------------
// Fetch full message metadata using Gmail Batch API (for category detail views)
// 100 messages per HTTP call (Gmail batch limit). 500 messages = 5 calls.
// With 3 concurrent batch calls = fast parallel fetching.
// ---------------------------------------------------------------------------
export const fetchMessageBatch = async (
  ids: string[],
  accessToken: string,
  _batchSize = 100 // legacy param, always uses 100 (Gmail batch limit)
): Promise<any[]> => {
  const results: any[] = new Array(ids.length).fill(null);
  const BATCH_SIZE = 100;
  const CONCURRENT_BATCHES = 5;

  // Build all batch chunks
  const chunks: { ids: string[]; startIdx: number }[] = [];
  for (let i = 0; i < ids.length; i += BATCH_SIZE) {
    chunks.push({ ids: ids.slice(i, i + BATCH_SIZE), startIdx: i });
  }

  // Process chunks in concurrent waves
  for (let w = 0; w < chunks.length; w += CONCURRENT_BATCHES) {
    const wave = chunks.slice(w, w + CONCURRENT_BATCHES);

    const waveResults = await Promise.all(
      wave.map(async (chunk) => {
        const endpoints = chunk.ids.map(id =>
          `/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=List-Unsubscribe&fields=id,threadId,snippet,labelIds,sizeEstimate,payload/headers`
        );

        try {
          const batchResults = await gmailBatchFetch(endpoints, accessToken);
          return { startIdx: chunk.startIdx, results: batchResults };
        } catch (error) {
          const errMsg = (error as Error).message || '';
          if (errMsg.startsWith('BATCH_RATE_LIMITED')) {
            // Fallback to individual requests for this chunk
            console.log(`[fetchMessageBatch] Batch rate limited, falling back for ${chunk.ids.length} msgs`);
            await delay(1000);
            const individual = await Promise.all(
              chunk.ids.map(async (id) => {
                try {
                  return await gmailFetch(
                    `/messages/${id}?format=metadata&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date&metadataHeaders=List-Unsubscribe&fields=id,threadId,snippet,labelIds,sizeEstimate,payload/headers`,
                    accessToken
                  );
                } catch { return null; }
              })
            );
            return { startIdx: chunk.startIdx, results: individual };
          }
          console.error('[fetchMessageBatch] Batch error:', error);
          return { startIdx: chunk.startIdx, results: new Array(chunk.ids.length).fill(null) };
        }
      })
    );

    // Parse results into formatted messages
    for (const { startIdx, results: batchResult } of waveResults) {
      for (let i = 0; i < batchResult.length; i++) {
        const msg = batchResult[i];
        if (!msg) continue;

        const headers = msg.payload?.headers?.reduce((acc: any, h: any) => {
          acc[h.name.toLowerCase()] = h.value;
          return acc;
        }, {}) || {};

        results[startIdx + i] = {
          id: msg.id,
          threadId: msg.threadId,
          snippet: decodeHtmlEntities(msg.snippet || ''),
          labelIds: msg.labelIds,
          isRead: !msg.labelIds?.includes('UNREAD'),
          isStarred: msg.labelIds?.includes('STARRED'),
          from: headers.from || 'Unknown',
          subject: decodeHtmlEntities(headers.subject || '(No subject)'),
          date: headers.date,
          hasUnsubscribe: !!headers['list-unsubscribe'],
          sizeEstimate: msg.sizeEstimate || 0
        };
      }
    }
  }

  console.log(`[fetchMessageBatch] Done: ${results.filter(Boolean).length}/${ids.length} via batch API`);
  return results.filter(Boolean);
};

// ---------------------------------------------------------------------------
// Per-user per-category message cache — avoids hitting Gmail on repeat loads
// Returns cached data in <1ms. Background refresh when stale.
// ---------------------------------------------------------------------------
interface CachedPage {
  messages: any[];
  nextPageToken: string | null;
  count: number;
  filteredCount: number | null;
  fetchedAt: number;
}

const pageCacheMap = new Map<string, CachedPage>();
const PAGE_CACHE_TTL = 2 * 60 * 1000; // 2 minutes

function pageCacheKey(userId: string, category: string, scope: string, maxResults: number, query: string): string {
  return `${userId}:${category}:${scope}:${maxResults}:${query}`;
}

export function getPageCache(userId: string, category: string, scope: string, maxResults: number, query: string): CachedPage | null {
  const key = pageCacheKey(userId, category, scope, maxResults, query);
  const cached = pageCacheMap.get(key);
  if (!cached) return null;
  // Return even if stale — caller decides whether to refresh
  return cached;
}

export function setPageCache(userId: string, category: string, scope: string, maxResults: number, query: string, data: CachedPage): void {
  const key = pageCacheKey(userId, category, scope, maxResults, query);
  data.fetchedAt = Date.now();
  pageCacheMap.set(key, data);

  // Evict old entries to prevent memory leaks (keep last 200)
  if (pageCacheMap.size > 200) {
    let oldest: string | null = null;
    let oldestTime = Infinity;
    for (const [k, v] of pageCacheMap) {
      if (v.fetchedAt < oldestTime) { oldest = k; oldestTime = v.fetchedAt; }
    }
    if (oldest) pageCacheMap.delete(oldest);
  }
}

export function invalidatePageCache(userId: string): void {
  for (const key of pageCacheMap.keys()) {
    if (key.startsWith(userId + ':')) {
      pageCacheMap.delete(key);
    }
  }
}

export function isPageCacheFresh(cached: CachedPage): boolean {
  return Date.now() - cached.fetchedAt < PAGE_CACHE_TTL;
}

// ---------------------------------------------------------------------------
// Count all message IDs for a label set
// ---------------------------------------------------------------------------
// Fast count using resultSizeEstimate (single API call, approximate but instant)
export const countAllMessages = async (labelIds: string[], accessToken: string, query?: string): Promise<number> => {
  const params = new URLSearchParams();
  for (const lid of labelIds) {
    params.append('labelIds', lid);
  }
  params.append('maxResults', '1'); // Only need the estimate, not actual messages
  if (query) params.append('q', query);

  const data = await gmailFetch(`/messages?${params}`, accessToken);
  return data.resultSizeEstimate || 0;
};
