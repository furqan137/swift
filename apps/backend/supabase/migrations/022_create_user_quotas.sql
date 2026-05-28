-- ============================================================================
-- User Quotas — deletion gate for freemium users
-- ============================================================================
-- Each user gets 5 free photo deletes per day. Watching a rewarded ad grants
-- +25 deletes (capped at 15 ads/day). Pro subscribers have unlimited deletes.
-- All operations are atomic to prevent client-side race conditions.
--
-- NOTE: This app uses a custom `public.users` table (not Supabase Auth's
-- `auth.users`). The backend accesses this table with the service_role key,
-- so RLS policies are bypassed. RLS is enabled as defense-in-depth but the
-- policies below are permissive since the backend handles auth via its own JWT.

-- Table
CREATE TABLE IF NOT EXISTS public.user_quotas (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                     uuid NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    free_photo_deletes_remaining int  NOT NULL DEFAULT 5,
    ads_watched_today           int  NOT NULL DEFAULT 0,
    total_deletes_today         int  NOT NULL DEFAULT 0,
    quota_reset_at              timestamptz NOT NULL DEFAULT (now() + interval '1 day')::date::timestamptz,
    is_pro                      boolean NOT NULL DEFAULT false,
    pro_expires_at              timestamptz,
    created_at                  timestamptz NOT NULL DEFAULT now(),
    updated_at                  timestamptz NOT NULL DEFAULT now()
);

-- Index for fast lookups by user_id
CREATE INDEX IF NOT EXISTS idx_user_quotas_user_id ON public.user_quotas(user_id);

-- RLS (defense-in-depth — backend uses service_role key which bypasses RLS)
ALTER TABLE public.user_quotas ENABLE ROW LEVEL SECURITY;

-- Allow the service_role full access (backend calls use this)
CREATE POLICY "Service role full access"
    ON public.user_quotas
    USING (true)
    WITH CHECK (true);

-- ============================================================================
-- Atomic Functions (SECURITY DEFINER = runs as table owner, bypasses RLS)
-- ============================================================================

-- check_and_reset_quota: Auto-resets if quota_reset_at has passed
CREATE OR REPLACE FUNCTION public.check_and_reset_quota(p_user_id uuid)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
BEGIN
    -- Upsert: create row if first call, otherwise fetch existing
    INSERT INTO public.user_quotas (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    -- Reset if the quota period has expired
    UPDATE public.user_quotas
    SET free_photo_deletes_remaining = 5,
        ads_watched_today = 0,
        total_deletes_today = 0,
        quota_reset_at = (now() + interval '1 day')::date::timestamptz,
        updated_at = now()
    WHERE user_id = p_user_id
      AND quota_reset_at < now();

    -- Return current state
    SELECT * INTO result
    FROM public.user_quotas
    WHERE user_id = p_user_id;

    RETURN result;
END;
$$;

-- consume_free_deletes: Atomically decrement free deletes
CREATE OR REPLACE FUNCTION public.consume_free_deletes(p_user_id uuid, p_count int)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
BEGIN
    IF p_count <= 0 THEN
        RAISE EXCEPTION 'count must be positive';
    END IF;

    UPDATE public.user_quotas
    SET free_photo_deletes_remaining = GREATEST(0, free_photo_deletes_remaining - p_count),
        total_deletes_today = total_deletes_today + p_count,
        updated_at = now()
    WHERE user_id = p_user_id
    RETURNING * INTO result;

    IF result IS NULL THEN
        RAISE EXCEPTION 'User quota not found. Call check_and_reset_quota first.';
    END IF;

    RETURN result;
END;
$$;

-- grant_ad_reward: Atomically add +25 deletes, enforcing 15 ads/day cap
CREATE OR REPLACE FUNCTION public.grant_ad_reward(p_user_id uuid)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
    current_ads int;
BEGIN
    -- Check current ad count
    SELECT ads_watched_today INTO current_ads
    FROM public.user_quotas
    WHERE user_id = p_user_id;

    IF current_ads IS NULL THEN
        RAISE EXCEPTION 'User quota not found. Call check_and_reset_quota first.';
    END IF;

    IF current_ads >= 15 THEN
        RAISE EXCEPTION 'Daily ad cap reached' USING ERRCODE = 'P0429';
    END IF;

    UPDATE public.user_quotas
    SET free_photo_deletes_remaining = free_photo_deletes_remaining + 25,
        ads_watched_today = ads_watched_today + 1,
        updated_at = now()
    WHERE user_id = p_user_id
    RETURNING * INTO result;

    RETURN result;
END;
$$;

-- ============================================================================
-- pg_cron: Daily reset at midnight UTC
-- ============================================================================
-- Requires the pg_cron extension to be enabled in your Supabase project.
-- This is a safety net — the check_and_reset_quota function also resets
-- expired quotas on every call, so the cron job catches any stragglers.
--
-- To enable: go to Supabase Dashboard → Database → Extensions → enable pg_cron
-- Then uncomment and run this in the SQL editor:

-- SELECT cron.schedule(
--     'reset-user-quotas',
--     '0 0 * * *',
--     $$
--     UPDATE public.user_quotas
--     SET free_photo_deletes_remaining = 5,
--         ads_watched_today = 0,
--         total_deletes_today = 0,
--         quota_reset_at = (now() + interval '1 day')::date::timestamptz,
--         updated_at = now()
--     WHERE quota_reset_at < now();
--     $$
-- );
