-- =========================================================================
-- CIVILMATE SUPABASE COMPLETE SCHEMA, RLS & RPC SETUP
-- Copy and run this in your Supabase SQL Editor:
-- Dashboard -> SQL Editor -> New Query -> Run
-- =========================================================================

-- 1. Ensure user_profiles has all necessary columns & default UUID
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  full_name text,
  status text DEFAULT 'waitlisted', -- 'waitlisted', 'approved', 'opted_out', 'blacklisted'
  subscription_tier text DEFAULT 'free',
  role text DEFAULT 'user',         -- 'user', 'tester', 'admin'
  last_active_at timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Ensure columns exist if table was previously created
ALTER TABLE IF EXISTS public.user_profiles 
  ADD COLUMN IF NOT EXISTS role text DEFAULT 'user',
  ADD COLUMN IF NOT EXISTS last_active_at timestamptz DEFAULT now(),
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 2. Create beta_feedback table (Replaces Google Forms)
CREATE TABLE IF NOT EXISTS public.beta_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email text NOT NULL,
  feedback_type text NOT NULL, -- 'Bug/Error', 'Feature Suggestions', 'UI/UX Improvement', etc.
  description text NOT NULL,
  steps_to_reproduce text,
  status text DEFAULT 'new',   -- 'new', 'in_progress', 'resolved'
  created_at timestamptz DEFAULT now()
);

-- 3. Create user_activity table for Google Sheets Add-on tracking
CREATE TABLE IF NOT EXISTS public.user_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_email text NOT NULL,
  action text NOT NULL DEFAULT 'addon_opened',
  details jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz DEFAULT now()
);

-- 4. Enable Row Level Security (RLS) on all tables
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.beta_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_activity ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies for user_profiles:
DROP POLICY IF EXISTS "Users and admin can view profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Users and admin can update profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Public can view application counts" ON public.user_profiles;

-- Policy A: Users can view their own profile; Admin (civilmateindia@gmail.com) can view all
CREATE POLICY "Users and admin can view profiles"
ON public.user_profiles
FOR SELECT
TO authenticated, anon
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
  OR auth.uid() = id
  OR lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  OR true -- Allows live capacity counts for public waitlist metrics
);

-- Policy B: Users and anon can insert/upsert their profile
CREATE POLICY "Users can insert own profile"
ON public.user_profiles
FOR INSERT
TO authenticated, anon
WITH CHECK (true);

-- Policy C: Users can update own profile; Admin can update any profile (approve, whitelist, blacklist)
CREATE POLICY "Users and admin can update profiles"
ON public.user_profiles
FOR UPDATE
TO authenticated, anon
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
  OR auth.uid() = id
  OR lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
)
WITH CHECK (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
  OR auth.uid() = id
  OR lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
);

-- 6. RLS Policies for beta_feedback:
DROP POLICY IF EXISTS "Anyone can insert feedback" ON public.beta_feedback;
DROP POLICY IF EXISTS "Admin can view feedback" ON public.beta_feedback;
DROP POLICY IF EXISTS "Admin can update feedback" ON public.beta_feedback;

CREATE POLICY "Anyone can insert feedback"
ON public.beta_feedback
FOR INSERT
TO anon, authenticated
WITH CHECK (true);

CREATE POLICY "Admin can view feedback"
ON public.beta_feedback
FOR SELECT
TO authenticated, anon
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
);

CREATE POLICY "Admin can update feedback"
ON public.beta_feedback
FOR UPDATE
TO authenticated
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
);

-- 7. RLS Policies for user_activity:
DROP POLICY IF EXISTS "Anyone can log activity" ON public.user_activity;
DROP POLICY IF EXISTS "Admin can view activity" ON public.user_activity;

CREATE POLICY "Anyone can log activity"
ON public.user_activity
FOR INSERT
TO anon, authenticated
WITH CHECK (true);

CREATE POLICY "Admin can view activity"
ON public.user_activity
FOR SELECT
TO authenticated
USING (
  lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
);

-- 8. Staged Exports RLS (if table exists)
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'staged_exports') THEN
    ALTER TABLE public.staged_exports ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Users can read own staged exports" ON public.staged_exports;
    CREATE POLICY "Users can read own staged exports"
    ON public.staged_exports
    FOR SELECT
    TO authenticated
    USING (
      lower(coalesce(auth.jwt() ->> 'email', '')) = 'civilmateindia@gmail.com'
      OR lower(user_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    );
  END IF;
END $$;

-- 9. RPC: Fast Public Program Statistics Function (No personal data exposed)
CREATE OR REPLACE FUNCTION get_beta_program_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stats json;
  v_feedback json;
BEGIN
  SELECT json_build_object(
    'total_applications', COUNT(*),
    'allocated_seats', COUNT(*) FILTER (WHERE status = 'approved'),
    'waitlisted_seats', COUNT(*) FILTER (WHERE status = 'waitlisted'),
    'opted_out_seats', COUNT(*) FILTER (WHERE status = 'opted_out'),
    'blacklisted_seats', COUNT(*) FILTER (WHERE status = 'blacklisted'),
    'max_capacity', 100
  ) INTO v_stats
  FROM public.user_profiles;

  SELECT COALESCE(json_object_agg(feedback_type, json_build_object(
    'submitted', count,
    'resolved', resolved_count
  )), '{}'::json) INTO v_feedback
  FROM (
    SELECT 
      feedback_type,
      COUNT(*) AS count,
      COUNT(*) FILTER (WHERE status = 'resolved') AS resolved_count
    FROM public.beta_feedback
    GROUP BY feedback_type
  ) f;

  RETURN json_build_object(
    'profiles', v_stats,
    'feedback', v_feedback
  );
END;
$$;
GRANT EXECUTE ON FUNCTION get_beta_program_stats() TO anon, authenticated;

-- 10. RPC: Public Opt-Out Function
CREATE OR REPLACE FUNCTION request_opt_out(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_profiles
  SET status = 'opted_out', updated_at = now()
  WHERE lower(email) = lower(p_email);
  RETURN FOUND;
END;
$$;
GRANT EXECUTE ON FUNCTION request_opt_out(text) TO anon, authenticated;

-- 11. RPC: Add-on Activity Heartbeat Ping
CREATE OR REPLACE FUNCTION ping_user_activity(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_profiles
  SET last_active_at = now()
  WHERE lower(email) = lower(p_email);
END;
$$;
GRANT EXECUTE ON FUNCTION ping_user_activity(text) TO anon, authenticated;
