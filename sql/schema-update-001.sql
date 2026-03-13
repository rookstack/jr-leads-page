-- ============================================================
-- Schema Update 001 — Lists support + missing CSV fields
-- Run in: https://supabase.com/dashboard/project/uebyzgrsaylfexldhccu
-- ============================================================

-- Create schema if not already done
CREATE SCHEMA IF NOT EXISTS jr_leads;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- LISTS TABLE — each Property Radar export is a named list
-- ============================================================
CREATE TABLE IF NOT EXISTS jr_leads.lists (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,                    -- e.g. "High Distress March 2026"
  description   TEXT,
  source        TEXT DEFAULT 'property_radar',
  imported_at   TIMESTAMPTZ DEFAULT NOW(),
  record_count  INTEGER DEFAULT 0
);

-- ============================================================
-- PROPERTIES TABLE (full schema with all CSV fields)
-- ============================================================
CREATE TABLE IF NOT EXISTS jr_leads.properties (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  -- List membership
  list_id             UUID REFERENCES jr_leads.lists(id),

  -- Owner names (from CSV Primary Name fields)
  primary_name        TEXT,
  primary_first       TEXT,
  primary_last        TEXT,

  -- Property address
  address             TEXT NOT NULL,
  city                TEXT NOT NULL,
  state               TEXT NOT NULL DEFAULT 'FL',
  zip                 TEXT,
  property_type       TEXT,                        -- SFR, MFR, etc.

  -- Mailing address (may differ from property — use for Lob.com)
  mail_address        TEXT,
  mail_city           TEXT,
  mail_state          TEXT,
  mail_zip            TEXT,

  -- Property details
  sq_ft               INTEGER,
  beds                NUMERIC(3,1),
  baths               NUMERIC(3,1),
  year_built          INTEGER,
  lot_size            INTEGER,

  -- Valuation
  est_value           INTEGER,
  est_equity          INTEGER,                     -- can be negative
  est_equity_pct      INTEGER,                     -- Est Equity %
  cltv_pct            INTEGER,                     -- Combined Loan-to-Value %
  purchase_price      INTEGER,
  owned_since         DATE,

  -- Distress signals
  distress_score      INTEGER,
  owner_occupied      BOOLEAN,
  listed              BOOLEAN DEFAULT FALSE,
  est_open_loans      INTEGER,                     -- # of open loans

  -- Owner record (as listed on title)
  owner_name          TEXT,                        -- full owner name from record
  owner_age           INTEGER,
  owner_2_name        TEXT,
  owner_2_age         INTEGER,
  is_business_owned   BOOLEAN DEFAULT FALSE,       -- TRUE if owner is LLC/Trust/Corp (affects mailer copy)

  -- Contact (unlocked via Property Radar credits)
  phone               TEXT,
  email               TEXT,
  phone_unlocked      BOOLEAN DEFAULT FALSE,
  email_unlocked      BOOLEAN DEFAULT FALSE,
  phone_unlocked_at   TIMESTAMPTZ,
  email_unlocked_at   TIMESTAMPTZ,

  -- Source
  source              TEXT DEFAULT 'property_radar',
  external_id         TEXT,
  source_criteria     TEXT,

  -- PRP validation
  prp_validated       BOOLEAN DEFAULT FALSE,
  prp_validated_at    TIMESTAMPTZ,
  prp_owner_match     BOOLEAN,
  prp_notes           TEXT,

  -- Campaign pipeline
  stage               INTEGER DEFAULT 1,
  mailer_sent_at      TIMESTAMPTZ,
  mailer_version      TEXT,
  mailer_lob_id       TEXT,

  -- QR + form tracking
  qr_code             TEXT UNIQUE,
  qr_scanned_at       TIMESTAMPTZ,
  qr_scan_count       INTEGER DEFAULT 0,
  fb_synced_at        TIMESTAMPTZ,

  -- Lead status
  is_warm             BOOLEAN DEFAULT FALSE,
  warm_lead_at        TIMESTAMPTZ,
  is_hot              BOOLEAN DEFAULT FALSE,
  hot_lead_at         TIMESTAMPTZ,

  -- Drop tracking
  dropped             BOOLEAN DEFAULT FALSE,
  dropped_at          TIMESTAMPTZ,
  drop_reason         TEXT,

  -- Timestamps
  added_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(address, city, state)
);

-- ============================================================
-- FORM SUBMISSIONS
-- ============================================================
CREATE TABLE IF NOT EXISTS jr_leads.form_submissions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  property_id     UUID REFERENCES jr_leads.properties(id),
  qr_code         TEXT,
  form_type       TEXT NOT NULL,

  first_name      TEXT,
  street_number   TEXT,
  last_name       TEXT,
  phone           TEXT,
  email           TEXT,
  full_address    TEXT,
  reason_selling  TEXT,
  timeline        TEXT,
  asking_price    INTEGER,
  notes           TEXT,
  ip_address      TEXT,
  submitted_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- AUTO-UPDATE TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION jr_leads.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER properties_updated_at
  BEFORE UPDATE ON jr_leads.properties
  FOR EACH ROW EXECUTE FUNCTION jr_leads.update_updated_at();

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_jr_leads_list        ON jr_leads.properties(list_id);
CREATE INDEX IF NOT EXISTS idx_jr_leads_stage       ON jr_leads.properties(stage)          WHERE dropped = FALSE;
CREATE INDEX IF NOT EXISTS idx_jr_leads_hot         ON jr_leads.properties(is_hot)         WHERE is_hot = TRUE;
CREATE INDEX IF NOT EXISTS idx_jr_leads_warm        ON jr_leads.properties(is_warm)        WHERE is_warm = TRUE;
CREATE INDEX IF NOT EXISTS idx_jr_leads_distress    ON jr_leads.properties(distress_score DESC);
CREATE INDEX IF NOT EXISTS idx_jr_leads_prp         ON jr_leads.properties(prp_validated, prp_owner_match);
CREATE INDEX IF NOT EXISTS idx_jr_leads_submissions ON jr_leads.form_submissions(property_id);

-- ============================================================
-- ROLE GRANTS (required for PostgREST access)
-- ============================================================
GRANT USAGE ON SCHEMA jr_leads TO postgres, anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA jr_leads TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA jr_leads TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA jr_leads TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA jr_leads TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA jr_leads TO anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA jr_leads GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA jr_leads GRANT ALL ON SEQUENCES TO service_role;

-- ============================================================
-- EXPOSE TO POSTGREST
-- Settings → API → Extra schemas → add "jr_leads"
-- ============================================================
