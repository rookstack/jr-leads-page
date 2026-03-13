-- ============================================================
-- Schema Update 002 — Add flags array for data quality review
-- Run in: https://supabase.com/dashboard/project/uebyzgrsaylfexldhccu
-- ============================================================

ALTER TABLE jr_leads.properties
  ADD COLUMN IF NOT EXISTS flags TEXT[] DEFAULT '{}';

-- Index for fast flag queries (e.g. WHERE 'no_street_number' = ANY(flags))
CREATE INDEX IF NOT EXISTS idx_jr_leads_flags ON jr_leads.properties USING GIN(flags);

-- ============================================================
-- FLAG REFERENCE
-- no_street_number  — property address had no street number; mail address used as fallback
-- mail_differs      — mailing address is in a different city/state (absentee/out-of-state owner)
-- negative_equity   — est_equity < 0 (underwater mortgage)
-- high_distress     — distress_score >= 70
-- business_owned    — owner is LLC/Trust/Corp (mirrors is_business_owned)
-- ============================================================
