-- ============================================================================
-- Extend User Quotas — multi-section freemium gates
-- ============================================================================
-- Adds per-section quota columns for Videos, Contacts, Email, and Compress.
-- Existing columns (free_photo_deletes_remaining, ads_watched_today,
-- total_deletes_today) are untouched for backward compatibility.
--
-- Section configs:
--   Photos   : Pattern A (rewarded ad)    — 5 free/day, +25/ad
--   Videos   : Pattern A (rewarded ad)    — 1 free/day, +15/ad
--   Contacts : Pattern B (hard cap)       — 2 free/day, no ads
--   Email    : Pattern A (rewarded ad)    — 5 free/day, +15/ad
--   Compress : Pattern C (metered 1/ad)   — 3 free/day, +1/ad
--
-- Global: 15-ad daily cap across ALL sections, shared ads_watched_today.

-- ============================================================================
-- 1. Add new columns
-- ============================================================================
ALTER TABLE public.user_quotas
  ADD COLUMN IF NOT EXISTS free_video_deletes_remaining    int NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS free_contact_merges_remaining   int NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS free_email_deletes_remaining    int NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS free_compress_actions_remaining int NOT NULL DEFAULT 3,
  ADD COLUMN IF NOT EXISTS total_contact_merges_today      int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_email_deletes_today       int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_compress_actions_today    int NOT NULL DEFAULT 0;

-- ============================================================================
-- 2. check_and_reset_quota_v2 — resets ALL section columns on daily reset
-- ============================================================================
CREATE OR REPLACE FUNCTION public.check_and_reset_quota_v2(p_user_id uuid)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
BEGIN
    -- Upsert: create row if first call
    INSERT INTO public.user_quotas (user_id)
    VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

    -- Reset ALL section quotas if period expired
    UPDATE public.user_quotas
    SET free_photo_deletes_remaining    = 5,
        free_video_deletes_remaining    = 1,
        free_contact_merges_remaining   = 2,
        free_email_deletes_remaining    = 5,
        free_compress_actions_remaining = 3,
        ads_watched_today               = 0,
        total_deletes_today             = 0,
        total_contact_merges_today      = 0,
        total_email_deletes_today       = 0,
        total_compress_actions_today    = 0,
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

-- ============================================================================
-- 3. consume_section_quota — decrement the correct free_* column
-- ============================================================================
CREATE OR REPLACE FUNCTION public.consume_section_quota(
    p_user_id uuid,
    p_section text,
    p_count   int
)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
BEGIN
    IF p_count <= 0 THEN
        RAISE EXCEPTION 'count must be positive';
    END IF;

    CASE p_section
        WHEN 'photos' THEN
            UPDATE public.user_quotas
            SET free_photo_deletes_remaining = GREATEST(0, free_photo_deletes_remaining - p_count),
                total_deletes_today = total_deletes_today + p_count,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'videos' THEN
            UPDATE public.user_quotas
            SET free_video_deletes_remaining = GREATEST(0, free_video_deletes_remaining - p_count),
                total_deletes_today = total_deletes_today + p_count,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'contacts' THEN
            UPDATE public.user_quotas
            SET free_contact_merges_remaining = GREATEST(0, free_contact_merges_remaining - p_count),
                total_contact_merges_today = total_contact_merges_today + p_count,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'email' THEN
            UPDATE public.user_quotas
            SET free_email_deletes_remaining = GREATEST(0, free_email_deletes_remaining - p_count),
                total_email_deletes_today = total_email_deletes_today + p_count,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'compress' THEN
            UPDATE public.user_quotas
            SET free_compress_actions_remaining = GREATEST(0, free_compress_actions_remaining - p_count),
                total_compress_actions_today = total_compress_actions_today + p_count,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        ELSE
            RAISE EXCEPTION 'Unknown section: %', p_section;
    END CASE;

    IF result IS NULL THEN
        RAISE EXCEPTION 'User quota not found. Call check_and_reset_quota first.';
    END IF;

    RETURN result;
END;
$$;

-- ============================================================================
-- 4. grant_section_ad_reward — section-aware ad reward with global cap
-- ============================================================================
CREATE OR REPLACE FUNCTION public.grant_section_ad_reward(
    p_user_id uuid,
    p_section text
)
RETURNS public.user_quotas
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
    result public.user_quotas;
    current_ads int;
BEGIN
    -- Contacts never allow ad rewards
    IF p_section = 'contacts' THEN
        RAISE EXCEPTION 'Contacts section does not support ad rewards';
    END IF;

    -- Check global ad cap
    SELECT ads_watched_today INTO current_ads
    FROM public.user_quotas
    WHERE user_id = p_user_id;

    IF current_ads IS NULL THEN
        RAISE EXCEPTION 'User quota not found. Call check_and_reset_quota first.';
    END IF;

    IF current_ads >= 15 THEN
        RAISE EXCEPTION 'Daily ad cap reached' USING ERRCODE = 'P0429';
    END IF;

    -- Grant reward based on section
    CASE p_section
        WHEN 'photos' THEN
            UPDATE public.user_quotas
            SET free_photo_deletes_remaining = free_photo_deletes_remaining + 25,
                ads_watched_today = ads_watched_today + 1,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'videos' THEN
            UPDATE public.user_quotas
            SET free_video_deletes_remaining = free_video_deletes_remaining + 15,
                ads_watched_today = ads_watched_today + 1,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'email' THEN
            UPDATE public.user_quotas
            SET free_email_deletes_remaining = free_email_deletes_remaining + 15,
                ads_watched_today = ads_watched_today + 1,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        WHEN 'compress' THEN
            UPDATE public.user_quotas
            SET free_compress_actions_remaining = free_compress_actions_remaining + 1,
                ads_watched_today = ads_watched_today + 1,
                updated_at = now()
            WHERE user_id = p_user_id
            RETURNING * INTO result;

        ELSE
            RAISE EXCEPTION 'Unknown section: %', p_section;
    END CASE;

    RETURN result;
END;
$$;

-- ============================================================================
-- Updated pg_cron template (resets all 5 section quotas)
-- ============================================================================
-- To enable: go to Supabase Dashboard -> Database -> Extensions -> enable pg_cron
-- Then uncomment and run this in the SQL editor:

-- SELECT cron.schedule(
--     'reset-user-quotas-v2',
--     '0 0 * * *',
--     $$
--     UPDATE public.user_quotas
--     SET free_photo_deletes_remaining    = 5,
--         free_video_deletes_remaining    = 1,
--         free_contact_merges_remaining   = 2,
--         free_email_deletes_remaining    = 5,
--         free_compress_actions_remaining = 3,
--         ads_watched_today               = 0,
--         total_deletes_today             = 0,
--         total_contact_merges_today      = 0,
--         total_email_deletes_today       = 0,
--         total_compress_actions_today    = 0,
--         quota_reset_at = (now() + interval '1 day')::date::timestamptz,
--         updated_at = now()
--     WHERE quota_reset_at < now();
--     $$
-- );
