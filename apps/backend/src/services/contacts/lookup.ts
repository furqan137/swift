import { supabaseService } from '../supabase.service.js';
import type { LookupResult } from './types.js';

const supabaseAdmin = supabaseService.getAdminClient();
const NUMVERIFY_API_KEY = process.env.NUMVERIFY_API_KEY || '';

/**
 * Normalize a phone string: strip everything except digits and leading +.
 */
function cleanPhone(phone: string): string {
  return phone.replace(/[^\d+]/g, '');
}

/**
 * Look up a phone number via cache or NumVerify API.
 */
export async function lookupPhone(phone: string): Promise<LookupResult> {
  const cleaned = cleanPhone(phone);

  if (cleaned.replace(/\+/g, '').length < 7) {
    throw Object.assign(new Error('Phone number too short (minimum 7 digits)'), { status: 400 });
  }

  if (cleaned.replace(/\+/g, '').length > 15) {
    throw Object.assign(new Error('Phone number too long (maximum 15 digits per E.164)'), { status: 400 });
  }

  // ── 1. Check Supabase cache (< 30 days old) ──
  const { data: cached } = await supabaseAdmin
    .from('phone_lookups')
    .select('*')
    .eq('phone', cleaned)
    .single();

  if (cached && cached.looked_up_at) {
    const age = Date.now() - new Date(cached.looked_up_at).getTime();
    const thirtyDays = 30 * 24 * 60 * 60 * 1000;

    if (age < thirtyDays) {
      console.log(`[contacts/lookup] Cache hit for ${cleaned.substring(0, 4)}****`);
      return {
        valid: cached.valid,
        carrier: cached.carrier,
        lineType: cached.line_type,
        location: cached.location,
        countryCode: cached.country_code,
        countryName: cached.country_name,
        internationalFormat: cached.international_format,
        cached: true
      };
    }
  }

  // ── 2. Call NumVerify API ──
  if (!NUMVERIFY_API_KEY) {
    console.warn('[contacts/lookup] NUMVERIFY_API_KEY not set — returning validation-only response');
    return {
      valid: null,
      carrier: null,
      lineType: null,
      location: null,
      countryCode: cleaned.startsWith('1') || cleaned.startsWith('+1') ? 'US' : null,
      countryName: null,
      internationalFormat: cleaned.startsWith('+') ? cleaned : `+${cleaned}`,
      cached: false,
      note: 'NumVerify API key not configured'
    };
  }

  // NumVerify free tier only supports HTTP (not HTTPS)
  const numverifyUrl = `http://apilayer.net/api/validate?access_key=${NUMVERIFY_API_KEY}&number=${encodeURIComponent(cleaned)}&country_code=&format=1`;

  console.log(`[contacts/lookup] Calling NumVerify for ${cleaned.substring(0, 4)}****`);
  const apiResponse = await fetch(numverifyUrl);

  if (!apiResponse.ok) {
    console.error('[contacts/lookup] NumVerify HTTP error:', apiResponse.status);
    throw Object.assign(new Error('Phone lookup service unavailable'), { status: 502 });
  }

  const data: any = await apiResponse.json();

  // NumVerify error handling
  if (data.error) {
    console.error('[contacts/lookup] NumVerify error:', data.error);
    throw Object.assign(new Error(data.error.info || 'Phone lookup failed'), { status: 502 });
  }

  const result: LookupResult = {
    valid: data.valid ?? null,
    carrier: data.carrier || null,
    lineType: data.line_type || null,
    location: data.location || null,
    countryCode: data.country_code || null,
    countryName: data.country_name || null,
    internationalFormat: data.international_format || null,
    cached: false
  };

  // ── 3. Cache in Supabase ──
  try {
    await supabaseAdmin
      .from('phone_lookups')
      .upsert({
        phone: cleaned,
        valid: result.valid,
        carrier: result.carrier,
        line_type: result.lineType,
        location: result.location,
        country_code: result.countryCode,
        country_name: result.countryName,
        international_format: result.internationalFormat,
        looked_up_at: new Date().toISOString()
      }, { onConflict: 'phone' });
  } catch (cacheErr) {
    console.warn('[contacts/lookup] Cache write failed (non-fatal):', cacheErr);
  }

  return result;
}
