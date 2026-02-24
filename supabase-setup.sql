-- ============================================
-- MENTORSHIP APPLICATION SYSTEM
-- Run this in Supabase SQL Editor (all at once)
-- ============================================

-- Enable pg_net for server-side HTTP calls (Telegram notifications)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================
-- TABLE: applications
-- ============================================
CREATE TABLE applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Step 1: About You
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  instagram TEXT,
  tiktok TEXT,

  -- Step 2: Your Business
  business_description TEXT NOT NULL,
  revenue_stage TEXT NOT NULL CHECK (revenue_stage IN (
    'just_starting', 'under_5k', '5k_to_15k', '15k_plus'
  )),
  biggest_challenge TEXT NOT NULL,

  -- Step 3: What Lights You Up
  areas_of_interest JSONB NOT NULL DEFAULT '[]',
  dream_outcome TEXT NOT NULL,

  -- Step 4: Final Details
  investment_readiness TEXT NOT NULL CHECK (investment_readiness IN (
    'ready', 'chat_first', 'exploring'
  )),
  how_found TEXT NOT NULL CHECK (how_found IN (
    'tiktok', 'instagram', 'facebook', 'word_of_mouth', 'other'
  )),
  preferred_contact TEXT NOT NULL CHECK (preferred_contact IN (
    'telegram', 'whatsapp', 'email', 'phone'
  )),
  anything_else TEXT,

  -- Honeypot (hidden field - should always be empty)
  website_url TEXT,

  -- Management
  status TEXT NOT NULL DEFAULT 'new' CHECK (status IN (
    'new', 'contacted', 'accepted', 'declined'
  )),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_applications_status ON applications(status);
CREATE INDEX idx_applications_created ON applications(created_at DESC);

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;

-- Form submissions (anon INSERT)
CREATE POLICY "Public can submit applications"
  ON applications FOR INSERT
  WITH CHECK (
    website_url IS NULL OR website_url = ''
  );

-- Command Centre reads (anon SELECT)
CREATE POLICY "Public can read applications"
  ON applications FOR SELECT
  USING (true);

-- Command Centre status updates (anon UPDATE)
CREATE POLICY "Public can update applications"
  ON applications FOR UPDATE
  USING (true)
  WITH CHECK (true);

-- ============================================
-- AUTO-UPDATE updated_at TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_applications_updated_at
  BEFORE UPDATE ON applications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- TELEGRAM NOTIFICATION ON NEW APPLICATION
-- Bot token stays server-side (never in browser)
-- ============================================
CREATE OR REPLACE FUNCTION notify_telegram_new_application()
RETURNS TRIGGER AS $$
DECLARE
  message_text TEXT;
  revenue_label TEXT;
  readiness_label TEXT;
  interests TEXT;
BEGIN
  -- Skip spam (honeypot filled)
  IF NEW.website_url IS NOT NULL AND NEW.website_url != '' THEN
    RETURN NEW;
  END IF;

  -- Readable revenue stage
  CASE NEW.revenue_stage
    WHEN 'just_starting' THEN revenue_label := 'Just starting';
    WHEN 'under_5k' THEN revenue_label := 'Under $5K/mo';
    WHEN '5k_to_15k' THEN revenue_label := '$5-15K/mo';
    WHEN '15k_plus' THEN revenue_label := '$15K+/mo';
    ELSE revenue_label := NEW.revenue_stage;
  END CASE;

  -- Readable investment readiness
  CASE NEW.investment_readiness
    WHEN 'ready' THEN readiness_label := 'Yes, I am ready';
    WHEN 'chat_first' THEN readiness_label := 'I would like to chat first';
    WHEN 'exploring' THEN readiness_label := 'Just exploring';
    ELSE readiness_label := NEW.investment_readiness;
  END CASE;

  -- Format interests array
  SELECT string_agg(value::text, ', ')
  INTO interests
  FROM jsonb_array_elements_text(NEW.areas_of_interest);

  message_text :=
    '<b>New Mentorship Application</b>' || chr(10) || chr(10)
    || '<b>' || NEW.full_name || '</b>' || chr(10)
    || NEW.email || chr(10)
    || NEW.phone
    || CASE WHEN NEW.instagram IS NOT NULL AND NEW.instagram != ''
         THEN chr(10) || 'IG: @' || NEW.instagram
         ELSE '' END
    || CASE WHEN NEW.tiktok IS NOT NULL AND NEW.tiktok != ''
         THEN chr(10) || 'TT: @' || NEW.tiktok
         ELSE '' END
    || chr(10) || chr(10)
    || '<b>Revenue:</b> ' || revenue_label || chr(10)
    || '<b>Investment:</b> ' || readiness_label || chr(10)
    || '<b>Found via:</b> ' || REPLACE(NEW.how_found, '_', ' ') || chr(10)
    || '<b>Contact via:</b> ' || NEW.preferred_contact || chr(10)
    || '<b>Interests:</b> ' || COALESCE(interests, 'None selected') || chr(10) || chr(10)
    || '<b>Business:</b> ' || LEFT(NEW.business_description, 300) || chr(10) || chr(10)
    || '<b>Challenge:</b> ' || LEFT(NEW.biggest_challenge, 300) || chr(10) || chr(10)
    || '<b>Dream outcome:</b> ' || LEFT(NEW.dream_outcome, 300)
    || CASE WHEN NEW.anything_else IS NOT NULL AND NEW.anything_else != ''
         THEN chr(10) || chr(10) || '<b>Also said:</b> ' || LEFT(NEW.anything_else, 200)
         ELSE '' END;

  PERFORM net.http_post(
    url := 'https://api.telegram.org/bot8370823351:AAFIS2oYqnoqm_y4xaZlNMqb4SaFnapDu7s/sendMessage',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := json_build_object(
      'chat_id', '6783708099',
      'text', message_text,
      'parse_mode', 'HTML'
    )::jsonb
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_new_application
  AFTER INSERT ON applications
  FOR EACH ROW EXECUTE FUNCTION notify_telegram_new_application();
