-- Schema Update 003 — Lead Status Tracking
-- Run in Supabase SQL editor (project: uebyzgrsaylfexldhccu)

ALTER TABLE jr_leads.properties 
  ADD COLUMN IF NOT EXISTS lead_status VARCHAR(32) DEFAULT 'unassigned',
  ADD COLUMN IF NOT EXISTS warm_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS hot_at TIMESTAMPTZ;

-- Allow anon key to mark a lead warm or hot (used by landing page on QR scan / form submit)
-- Limited to only these two values — no destructive updates via anon
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies 
    WHERE schemaname = 'jr_leads' AND tablename = 'properties' 
    AND policyname = 'anon can mark warm or hot'
  ) THEN
    CREATE POLICY "anon can mark warm or hot" ON jr_leads.properties
      FOR UPDATE TO anon
      USING (true)
      WITH CHECK (lead_status IN ('warm', 'hot'));
  END IF;
END $$;

GRANT UPDATE (lead_status, warm_at, hot_at) ON jr_leads.properties TO anon;
