-- ============================================================================
-- TravelEase: Migration 003
-- Module 3: Multimodal Accessible Communication Module (FR-M3-01 to FR-M3-18)
-- Module 4: Sign-Language Reference Engine Module (FR-M4-01 to FR-M4-19)
-- Supports ASL (American), BIM (Malaysian), and CSL (Chinese) Sign Languages
-- ============================================================================

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 1. Sign Languages Catalog
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_languages (
    id TEXT PRIMARY KEY, -- 'ASL', 'BIM', 'CSL'
    name TEXT NOT NULL,
    native_name TEXT NOT NULL,
    country_code TEXT NOT NULL,
    country_name TEXT NOT NULL,
    primary_spoken_language TEXT NOT NULL, -- 'en', 'ms', 'zh'
    description TEXT,
    flag_emoji TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. Sign Reference Categories
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_categories (
    id TEXT PRIMARY KEY, -- 'all', 'airport', 'hotel', 'restaurant', 'transit', 'medical', 'emergency', 'general'
    name TEXT NOT NULL,
    icon_name TEXT NOT NULL,
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 3. Sign Dictionary Phrases (Multilingual Master Dictionary)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_dictionary_phrases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category_id TEXT NOT NULL REFERENCES public.sign_categories(id) ON UPDATE CASCADE,
    phrase_en TEXT NOT NULL,
    phrase_ms TEXT NOT NULL,
    phrase_zh TEXT NOT NULL,
    gloss_asl TEXT, -- e.g. "WHERE GATE ?"
    gloss_bim TEXT, -- e.g. "PINTU MANA ?"
    gloss_csl TEXT, -- e.g. "登机口 在哪 ?"
    scenario TEXT, -- e.g. "Airport Departure / Security Check"
    step_instructions JSONB DEFAULT '[]'::jsonb, -- [{"step": 1, "title": "...", "description": "..."}]
    related_phrase_ids TEXT[] DEFAULT ARRAY[]::TEXT[],
    is_verified BOOLEAN DEFAULT TRUE,
    view_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 4. Sign Media Assets (Front & Side Visual Perspectives, Video, 3D Assets)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_media_assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phrase_id UUID NOT NULL REFERENCES public.sign_dictionary_phrases(id) ON DELETE CASCADE,
    sign_language_id TEXT NOT NULL REFERENCES public.sign_languages(id) ON UPDATE CASCADE,
    perspective TEXT NOT NULL DEFAULT 'front' CHECK (perspective IN ('front', 'side', 'top')),
    video_url TEXT NOT NULL,
    animation_url TEXT,
    thumbnail_url TEXT,
    duration_seconds NUMERIC(4, 2) DEFAULT 3.00,
    frame_count INT DEFAULT 90,
    fps INT DEFAULT 30,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 5. User Favorite / Bookmarked Phrases (FR-M4-17, FR-M4-18, FR-M4-19)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_favorite_phrases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    phrase_id UUID NOT NULL REFERENCES public.sign_dictionary_phrases(id) ON DELETE CASCADE,
    order_index INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, phrase_id)
);

-- ----------------------------------------------------------------------------
-- 6. Dictionary Search History (FR-M4-15, FR-M4-16)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dictionary_search_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    search_query TEXT NOT NULL,
    sign_language_id TEXT,
    category_id TEXT,
    result_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 7. Sign Asset Feedback & Moderation (UC402 Alt A3)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_asset_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    phrase_id UUID REFERENCES public.sign_dictionary_phrases(id) ON DELETE SET NULL,
    sign_language_id TEXT REFERENCES public.sign_languages(id),
    issue_type TEXT NOT NULL CHECK (issue_type IN ('unclear_gesture', 'broken_video', 'incorrect_gloss', 'incorrect_translation', 'other')),
    description TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 8. Two-Way Dialogue Sessions (FR-M3-13, UC303)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.communication_dialogue_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_code TEXT UNIQUE NOT NULL,
    traveler_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    traveler_name TEXT NOT NULL DEFAULT 'Deaf Traveler',
    staff_name TEXT NOT NULL DEFAULT 'Staff / Hearing Individual',
    traveler_sign_language TEXT NOT NULL DEFAULT 'BIM' REFERENCES public.sign_languages(id),
    source_language TEXT NOT NULL DEFAULT 'en', -- deaf traveler typed/spoken output
    target_language TEXT NOT NULL DEFAULT 'ms', -- counter staff spoken language
    speech_playback_speed NUMERIC(3, 2) DEFAULT 1.00, -- FR-M3-10
    speech_playback_volume NUMERIC(3, 2) DEFAULT 1.00, -- FR-M3-11
    speech_voice_gender TEXT DEFAULT 'female' CHECK (speech_voice_gender IN ('female', 'male', 'neutral')), -- FR-M3-12
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    ended_at TIMESTAMPTZ
);

-- ----------------------------------------------------------------------------
-- 9. Two-Way Dialogue Messages (FR-M3-09, FR-M3-14, FR-M3-15)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.communication_dialogue_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES public.communication_dialogue_sessions(id) ON DELETE CASCADE,
    sender_role TEXT NOT NULL CHECK (sender_role IN ('traveler', 'staff', 'system')),
    sender_name TEXT NOT NULL,
    original_text TEXT NOT NULL,
    translated_text TEXT NOT NULL,
    source_language TEXT NOT NULL,
    target_language TEXT NOT NULL,
    input_modality TEXT NOT NULL CHECK (input_modality IN ('sign_to_text', 'speech_to_text', 'typed_text', 'quick_phrase')),
    ai_confidence_score NUMERIC(4, 3) DEFAULT 0.950,
    is_corrected BOOLEAN DEFAULT FALSE,
    corrected_text TEXT,
    audio_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 10. Saved Conversation Logs (FR-M3-17, FR-M3-18, UC304)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.communication_saved_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.communication_dialogue_sessions(id) ON DELETE SET NULL,
    log_title TEXT NOT NULL,
    translation_type TEXT NOT NULL CHECK (translation_type IN ('two_way_dialogue', 'sign_to_text', 'speech_to_sign')),
    summary TEXT,
    full_transcript JSONB NOT NULL DEFAULT '[]'::jsonb,
    message_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 11. Predefined Dialogue Context-Aware Quick Phrases (FR-M3-16)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.communication_quick_phrases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    category TEXT NOT NULL,
    text_en TEXT NOT NULL,
    text_ms TEXT NOT NULL,
    text_zh TEXT NOT NULL,
    icon_name TEXT DEFAULT 'chat',
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 12. Sign Translation Predictions Log (FR-M3-01 to FR-M3-06, UC301)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sign_translations_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    sign_language_id TEXT NOT NULL REFERENCES public.sign_languages(id),
    predicted_text TEXT NOT NULL,
    confirmed_text TEXT NOT NULL,
    confidence_score NUMERIC(4, 3) NOT NULL,
    is_edited BOOLEAN DEFAULT FALSE,
    audio_played BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- Indexes for High Performance Querying
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_phrases_category ON public.sign_dictionary_phrases(category_id);
CREATE INDEX IF NOT EXISTS idx_phrases_text_en ON public.sign_dictionary_phrases USING gin (to_tsvector('english', phrase_en));
CREATE INDEX IF NOT EXISTS idx_media_phrase_lang ON public.sign_media_assets(phrase_id, sign_language_id);
CREATE INDEX IF NOT EXISTS idx_fav_user ON public.user_favorite_phrases(user_id);
CREATE INDEX IF NOT EXISTS idx_history_user ON public.dictionary_search_history(user_id);
CREATE INDEX IF NOT EXISTS idx_messages_session ON public.communication_dialogue_messages(session_id, created_at);
CREATE INDEX IF NOT EXISTS idx_saved_logs_user ON public.communication_saved_logs(user_id, translation_type);

-- ----------------------------------------------------------------------------
-- Enable Row Level Security (RLS)
-- ----------------------------------------------------------------------------
ALTER TABLE public.sign_languages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sign_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sign_dictionary_phrases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sign_media_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_favorite_phrases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dictionary_search_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sign_asset_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_dialogue_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_dialogue_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_saved_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communication_quick_phrases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sign_translations_history ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- Public Read & Full Access Policies for Traveler Development
-- ----------------------------------------------------------------------------
CREATE POLICY "Public read sign_languages" ON public.sign_languages FOR SELECT USING (true);
CREATE POLICY "Public read sign_categories" ON public.sign_categories FOR SELECT USING (true);
CREATE POLICY "Public read sign_dictionary_phrases" ON public.sign_dictionary_phrases FOR SELECT USING (true);
CREATE POLICY "Public read sign_media_assets" ON public.sign_media_assets FOR SELECT USING (true);
CREATE POLICY "Public read communication_quick_phrases" ON public.communication_quick_phrases FOR SELECT USING (true);

-- User-scoped policies (allows all operations for traveler app)
CREATE POLICY "Allow all user_favorite_phrases" ON public.user_favorite_phrases FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all dictionary_search_history" ON public.dictionary_search_history FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all sign_asset_feedback" ON public.sign_asset_feedback FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all communication_dialogue_sessions" ON public.communication_dialogue_sessions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all communication_dialogue_messages" ON public.communication_dialogue_messages FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all communication_saved_logs" ON public.communication_saved_logs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all sign_translations_history" ON public.sign_translations_history FOR ALL USING (true) WITH CHECK (true);

-- ----------------------------------------------------------------------------
-- Realtime Replication Setup
-- ----------------------------------------------------------------------------
ALTER PUBLICATION supabase_realtime ADD TABLE public.communication_dialogue_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.communication_dialogue_sessions;

-- ============================================================================
-- SEED DATA: Sign Languages, Categories, Multilingual Phrases & Media
-- ============================================================================

INSERT INTO public.sign_languages (id, name, native_name, country_code, country_name, primary_spoken_language, description, flag_emoji)
VALUES 
    ('BIM', 'Malaysian Sign Language', 'Bahasa Isyarat Malaysia', 'MY', 'Malaysia', 'ms', 'Official sign language for the Deaf community in Malaysia.', '🇲🇾'),
    ('ASL', 'American Sign Language', 'American Sign Language', 'US', 'United States', 'en', 'Widely recognized international and US standard sign language.', '🇺🇸'),
    ('CSL', 'Chinese Sign Language', '中国手语 (Zhongguo Shouyu)', 'CN', 'China', 'zh', 'Standard sign language used throughout mainland China and Chinese travelers.', '🇨🇳')
ON CONFLICT (id) DO UPDATE SET 
    name = EXCLUDED.name,
    native_name = EXCLUDED.native_name,
    description = EXCLUDED.description;

INSERT INTO public.sign_categories (id, name, icon_name, display_order)
VALUES
    ('all', 'All Categories', 'grid_view', 0),
    ('airport', 'Airport & Flights', 'flight_takeoff', 1),
    ('hotel', 'Hotel & Check-in', 'hotel', 2),
    ('restaurant', 'Food & Dining', 'restaurant', 3),
    ('transit', 'Transit & Buses', 'directions_bus', 4),
    ('medical', 'Medical & Pharmacy', 'local_hospital', 5),
    ('emergency', 'Emergency & SOS', 'warning_amber', 6),
    ('general', 'Greetings & General', 'chat_bubble_outline', 7)
ON CONFLICT (id) DO NOTHING;

-- Seed Multilingual Dictionary Phrases
INSERT INTO public.sign_dictionary_phrases (
    id, category_id, phrase_en, phrase_ms, phrase_zh,
    gloss_asl, gloss_bim, gloss_csl, scenario,
    step_instructions, is_verified
) VALUES
(
    'a1111111-1111-1111-1111-111111111111',
    'airport',
    'Where is the gate?',
    'Di mana pintu masuk?',
    '登机口在哪里？',
    'GATE WHERE ?',
    'PINTU MANA ?',
    '登机口 在哪 ?',
    'Airport Departure / Boarding Area',
    '[
        {"step": 1, "title": "Raise Open Palms", "description": "Raise both hands with open palms facing upward at chest level."},
        {"step": 2, "title": "Move Hands Outward", "description": "Move both hands gently apart in an inquisitive questioning motion."},
        {"step": 3, "title": "Point & Question Facial Expression", "description": "Point forward with dominant index finger while raising eyebrows to indicate a question."}
    ]'::jsonb,
    true
),
(
    'a2222222-2222-2222-2222-222222222222',
    'airport',
    'I need to check in',
    'Saya perlu daftar masuk',
    '我需要办理值机',
    'I NEED CHECK-IN',
    'SAYA PERLU DAFTAR MASUK',
    '我 需要 办理 值机',
    'Airport Counter / Terminal Entrance',
    '[
        {"step": 1, "title": "Indicate Self", "description": "Tap chest with index finger to indicate yourself."},
        {"step": 2, "title": "Sign Need / Require", "description": "Form a bent index finger and tap downward twice firmly."},
        {"step": 3, "title": "Sign Ticket / Pass Registration", "description": "Slide flat hand into open palm like presenting a boarding pass."}
    ]'::jsonb,
    true
),
(
    'a3333333-3333-3333-3333-333333333333',
    'airport',
    'My flight is delayed',
    'Penerbangan saya tertangguh',
    '我的航班延误了',
    'MY FLIGHT DELAY',
    'PENERBANGAN SAYA TANGGUH',
    '我 航班 延误',
    'Airport Flight Information Display',
    '[
        {"step": 1, "title": "Sign Airplane", "description": "Extend thumb, index, and pinky (ILY shape) moving forward in flight path."},
        {"step": 2, "title": "Sign Delay", "description": "Hold both hands in F-shape and move dominant hand forward slowly in increments."}
    ]'::jsonb,
    true
),
(
    'a4444444-4444-4444-4444-444444444444',
    'hotel',
    'I have a reservation',
    'Saya ada tempahan bilik',
    '我有房间预订',
    'I HAVE ROOM BOOK',
    'SAYA ADA TEMPAH BILIK',
    '我 有 预订 房间',
    'Hotel Reception Desk',
    '[
        {"step": 1, "title": "Sign Have / Own", "description": "Touch both fingertips to chest with hands slightly cupped."},
        {"step": 2, "title": "Sign Booking / Reserve", "description": "Grasp with dominant hand onto the non-dominant palm firmly."}
    ]'::jsonb,
    true
),
(
    'a5555555-5555-5555-5555-555555555555',
    'restaurant',
    'Can I get the menu?',
    'Boleh saya dapatkan menu?',
    '可以给我菜单吗？',
    'CAN I SEE MENU ?',
    'BOLEH SAYA LIHAT MENU ?',
    '可以 给我 菜单 吗 ?',
    'Dining Table / Counter',
    '[
        {"step": 1, "title": "Sign Please / Request", "description": "Rub open flat palm in circular motion on chest."},
        {"step": 2, "title": "Sign Menu / Book", "description": "Open both palms together like opening a booklet."}
    ]'::jsonb,
    true
),
(
    'a6666666-6666-6666-6666-666666666666',
    'emergency',
    'I need help / SOS',
    'Saya perlukan bantuan kecemasan',
    '我需要紧急帮助',
    'I NEED HELP SOS',
    'SAYA PERLU BANTUAN KECEMASAN',
    '我 需要 紧急 帮助',
    'Emergency Incident / First Aid Station',
    '[
        {"step": 1, "title": "Sign Help", "description": "Place closed fist with thumb up onto open flat palm and lift upward together."},
        {"step": 2, "title": "Urgent Facial Cue", "description": "Widen eyes and mouth in an urgent request."}
    ]'::jsonb,
    true
),
(
    'a7777777-7777-7777-7777-777777777777',
    'general',
    'Thank you very much',
    'Terima kasih banyak',
    '非常感谢',
    'THANK YOU MUCH',
    'TERIMA KASIH BANYAK',
    '非常 谢谢 你',
    'General Conversation',
    '[
        {"step": 1, "title": "Fingertips to Chin", "description": "Touch fingertips of flat hand to chin or lips."},
        {"step": 2, "title": "Extend Forward", "description": "Move hand forward and down toward the listener with a warm smile."}
    ]'::jsonb,
    true
),
(
    'a8888888-8888-8888-8888-888888888888',
    'general',
    'Hello, nice to meet you',
    'Halo, selamat berkenalan',
    '你好，很高兴认识你',
    'HELLO NICE MEET YOU',
    'HALO GEMBIRA JUMPA AWAK',
    '你好 很高兴 认识 你',
    'General Greeting',
    '[
        {"step": 1, "title": "Salute Gesture", "description": "Place flat hand at forehead and move outward in friendly salute."},
        {"step": 2, "title": "Sign Meet", "description": "Bring both index fingers pointing upward toward each other in center."}
    ]'::jsonb,
    true
),
(
    'a9999999-9999-9999-9999-999999999999',
    'transit',
    'Which bus goes to the city center?',
    'Bas mana pergi ke pusat bandar?',
    '哪趟巴士去市中心？',
    'WHICH BUS GO CITY CENTER ?',
    'BAS MANA PERGI PUSAT BANDAR ?',
    '哪个 巴士 去 市中心 ?',
    'Bus Terminal / Transit Station',
    '[
        {"step": 1, "title": "Sign Bus", "description": "Mime steering a large bus wheel with both hands."},
        {"step": 2, "title": "Sign City / Downtown", "description": "Touch fingertips of both hands together to form rooftops."}
    ]'::jsonb,
    true
),
(
    'baaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
    'medical',
    'I feel sick and need a doctor',
    'Saya rasa tidak sihat, perlu doktor',
    '我感觉不舒服，需要医生',
    'I SICK NEED DOCTOR',
    'SAYA SAKIT PERLU DOKTOR',
    '我 生病 需要 医生',
    'Pharmacy / Medical Clinic',
    '[
        {"step": 1, "title": "Sign Sick", "description": "Touch bent middle finger to forehead and stomach simultaneously."},
        {"step": 2, "title": "Sign Doctor", "description": "Tap fingertips of dominant M-hand on wrist pulse."}
    ]'::jsonb,
    true
)
ON CONFLICT (id) DO NOTHING;

-- Seed Media Assets (Front and Side Perspectives for BIM, ASL, CSL)
INSERT INTO public.sign_media_assets (phrase_id, sign_language_id, perspective, video_url, animation_url, thumbnail_url, duration_seconds, fps)
VALUES
    -- Gate phrase BIM
    ('a1111111-1111-1111-1111-111111111111', 'BIM', 'front', 'https://assets.travelease.app/signs/bim/gate_front.mp4', 'https://assets.travelease.app/signs/bim/gate_front.glb', 'https://assets.travelease.app/signs/bim/gate_thumb.jpg', 3.2, 30),
    ('a1111111-1111-1111-1111-111111111111', 'BIM', 'side', 'https://assets.travelease.app/signs/bim/gate_side.mp4', 'https://assets.travelease.app/signs/bim/gate_side.glb', 'https://assets.travelease.app/signs/bim/gate_thumb.jpg', 3.2, 30),
    -- Gate phrase ASL
    ('a1111111-1111-1111-1111-111111111111', 'ASL', 'front', 'https://assets.travelease.app/signs/asl/gate_front.mp4', 'https://assets.travelease.app/signs/asl/gate_front.glb', 'https://assets.travelease.app/signs/asl/gate_thumb.jpg', 2.8, 30),
    ('a1111111-1111-1111-1111-111111111111', 'ASL', 'side', 'https://assets.travelease.app/signs/asl/gate_side.mp4', 'https://assets.travelease.app/signs/asl/gate_side.glb', 'https://assets.travelease.app/signs/asl/gate_thumb.jpg', 2.8, 30),
    -- Gate phrase CSL
    ('a1111111-1111-1111-1111-111111111111', 'CSL', 'front', 'https://assets.travelease.app/signs/csl/gate_front.mp4', 'https://assets.travelease.app/signs/csl/gate_front.glb', 'https://assets.travelease.app/signs/csl/gate_thumb.jpg', 3.0, 30),
    ('a1111111-1111-1111-1111-111111111111', 'CSL', 'side', 'https://assets.travelease.app/signs/csl/gate_side.mp4', 'https://assets.travelease.app/signs/csl/gate_side.glb', 'https://assets.travelease.app/signs/csl/gate_thumb.jpg', 3.0, 30),
    -- Check-in phrase BIM & ASL & CSL
    ('a2222222-2222-2222-2222-222222222222', 'BIM', 'front', 'https://assets.travelease.app/signs/bim/checkin_front.mp4', 'https://assets.travelease.app/signs/bim/checkin_front.glb', 'https://assets.travelease.app/signs/bim/checkin_thumb.jpg', 3.5, 30),
    ('a2222222-2222-2222-2222-222222222222', 'ASL', 'front', 'https://assets.travelease.app/signs/asl/checkin_front.mp4', 'https://assets.travelease.app/signs/asl/checkin_front.glb', 'https://assets.travelease.app/signs/asl/checkin_thumb.jpg', 3.4, 30),
    ('a2222222-2222-2222-2222-222222222222', 'CSL', 'front', 'https://assets.travelease.app/signs/csl/checkin_front.mp4', 'https://assets.travelease.app/signs/csl/checkin_front.glb', 'https://assets.travelease.app/signs/csl/checkin_thumb.jpg', 3.3, 30),
    -- SOS Help
    ('a6666666-6666-6666-6666-666666666666', 'BIM', 'front', 'https://assets.travelease.app/signs/bim/help_front.mp4', 'https://assets.travelease.app/signs/bim/help_front.glb', 'https://assets.travelease.app/signs/bim/help_thumb.jpg', 2.5, 30),
    ('a6666666-6666-6666-6666-666666666666', 'ASL', 'front', 'https://assets.travelease.app/signs/asl/help_front.mp4', 'https://assets.travelease.app/signs/asl/help_front.glb', 'https://assets.travelease.app/signs/asl/help_thumb.jpg', 2.4, 30),
    ('a6666666-6666-6666-6666-666666666666', 'CSL', 'front', 'https://assets.travelease.app/signs/csl/help_front.mp4', 'https://assets.travelease.app/signs/csl/help_front.glb', 'https://assets.travelease.app/signs/csl/help_thumb.jpg', 2.6, 30),
    -- Thank you
    ('a7777777-7777-7777-7777-777777777777', 'BIM', 'front', 'https://assets.travelease.app/signs/bim/thankyou_front.mp4', 'https://assets.travelease.app/signs/bim/thankyou_front.glb', 'https://assets.travelease.app/signs/bim/thankyou_thumb.jpg', 2.0, 30),
    ('a7777777-7777-7777-7777-777777777777', 'ASL', 'front', 'https://assets.travelease.app/signs/asl/thankyou_front.mp4', 'https://assets.travelease.app/signs/asl/thankyou_front.glb', 'https://assets.travelease.app/signs/asl/thankyou_thumb.jpg', 2.0, 30),
    ('a7777777-7777-7777-7777-777777777777', 'CSL', 'front', 'https://assets.travelease.app/signs/csl/thankyou_front.mp4', 'https://assets.travelease.app/signs/csl/thankyou_front.glb', 'https://assets.travelease.app/signs/csl/thankyou_thumb.jpg', 2.0, 30)
ON CONFLICT DO NOTHING;

-- Seed Predefined Quick Phrases for Live Dialogue
INSERT INTO public.communication_quick_phrases (category, text_en, text_ms, text_zh, icon_name, display_order)
VALUES
    ('General', 'Thank you', 'Terima kasih', '谢谢', 'volunteer_activism', 1),
    ('General', 'Where is...?', 'Di manakah...?', '在哪里...？', 'location_on', 2),
    ('General', 'I need help', 'Saya perlukan bantuan', '我需要帮助', 'sos', 3),
    ('General', 'Please repeat', 'Sila ulang semula', '请重复一次', 'replay', 4),
    ('General', 'How much does it cost?', 'Berapakah harganya?', '这个多少钱？', 'payments', 5),
    ('Airport', 'Where is my boarding gate?', 'Di manakah pintu perlepasan saya?', '我的登机口在哪里？', 'flight_takeoff', 6),
    ('Airport', 'I am deaf, please write or type here', 'Saya pekak, sila taip atau tulis di sini', '我是听障人士，请在此打字或书写', 'hearing_disabled', 7),
    ('Hotel', 'I want to check in', 'Saya ingin daftar masuk', '我想办理入住', 'hotel', 8),
    ('Emergency', 'Please call emergency assistance', 'Sila hubungi bantuan kecemasan', '请呼叫紧急救助', 'warning', 9)
ON CONFLICT DO NOTHING;
