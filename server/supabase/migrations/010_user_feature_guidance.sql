-- ============================================================================
-- TravelEase: Migration 010
-- Per-user first-use tracking for the traveller app.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_feature_guidance (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    feature_key TEXT NOT NULL CHECK (feature_key IN (
        'sign_translate',
        'speech_to_sign',
        'two_way_dialogue',
        'sign_dictionary',
        'request_help',
        'queue_tracking',
        'announcements',
        'gps_location',
        'sos'
    )),
    first_opened_at TIMESTAMPTZ,
    first_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, feature_key)
);

CREATE INDEX IF NOT EXISTS idx_user_feature_guidance_user_id
    ON public.user_feature_guidance(user_id);

ALTER TABLE public.user_feature_guidance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own feature guidance"
    ON public.user_feature_guidance
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

CREATE POLICY "Users can create their own feature guidance"
    ON public.user_feature_guidance
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own feature guidance"
    ON public.user_feature_guidance
    FOR UPDATE TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Records an event without overwriting the original timestamp. Calling this
-- RPC is safe repeatedly, which lets mobile screens report usage on every
-- visit while the database preserves each user's first use.
CREATE OR REPLACE FUNCTION public.record_feature_usage(
    p_feature_key TEXT,
    p_event TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
    event_time TIMESTAMPTZ := NOW();
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'An authenticated user is required.';
    END IF;

    IF p_feature_key NOT IN (
        'sign_translate',
        'speech_to_sign',
        'two_way_dialogue',
        'sign_dictionary',
        'request_help',
        'queue_tracking',
        'announcements',
        'gps_location',
        'sos'
    ) THEN
        RAISE EXCEPTION 'Unknown feature key: %', p_feature_key;
    END IF;

    IF p_event NOT IN ('opened', 'completed') THEN
        RAISE EXCEPTION 'Unknown feature event: %', p_event;
    END IF;

    INSERT INTO public.user_feature_guidance (
        user_id,
        feature_key,
        first_opened_at,
        first_completed_at
    ) VALUES (
        auth.uid(),
        p_feature_key,
        CASE WHEN p_event IN ('opened', 'completed') THEN event_time END,
        CASE WHEN p_event = 'completed' THEN event_time END
    )
    ON CONFLICT (user_id, feature_key) DO UPDATE SET
        first_opened_at = COALESCE(
            user_feature_guidance.first_opened_at,
            CASE WHEN p_event IN ('opened', 'completed') THEN event_time END
        ),
        first_completed_at = COALESCE(
            user_feature_guidance.first_completed_at,
            CASE WHEN p_event = 'completed' THEN event_time END
        ),
        updated_at = event_time;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_feature_usage(TEXT, TEXT)
    TO authenticated;
