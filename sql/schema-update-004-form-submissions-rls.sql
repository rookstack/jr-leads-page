-- ============================================================
-- Schema Update 004 — Grant anon role INSERT on form_submissions
-- Run in: https://supabase.com/dashboard/project/uebyzgrsaylfexldhccu/sql/new
-- ============================================================

-- Allow the browser (anon role) to write form submissions
GRANT INSERT ON jr_leads.form_submissions TO anon;

-- Allow the browser to read back its own submission (optional, for confirmation)
GRANT SELECT ON jr_leads.form_submissions TO anon;

-- Verify the grant worked (run this after the above)
-- SELECT grantee, privilege_type FROM information_schema.role_table_grants
-- WHERE table_schema = 'jr_leads' AND table_name = 'form_submissions';
