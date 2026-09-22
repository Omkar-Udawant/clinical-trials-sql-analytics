-- ============================================================
-- governance.sql (v2 — corrected after live test run)
-- Data governance & access-control layer for the
-- clinical-trials-sql-analytics database.
--
-- PREREQUISITE: run this AFTER sql/clinical_trials_db.sql has
-- created and populated the tables in the "public" schema.
-- ============================================================


-- ------------------------------------------------------------
-- 1. ROLES
-- ------------------------------------------------------------
-- Passwords intentionally NOT hardcoded. Create roles without a
-- password here, then set it interactively or via an environment
-- variable at deploy time:
--   ALTER ROLE data_steward WITH PASSWORD :'steward_pw';
-- (psql variable, not a literal in version control).

CREATE ROLE data_steward LOGIN;
CREATE ROLE data_analyst LOGIN;
CREATE ROLE reporting_tool LOGIN;


-- ------------------------------------------------------------
-- 2. SCHEMA SEPARATION
-- ------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS reporting;

-- Move existing public-schema objects into their governed schemas.
-- These are LIVE statements (not examples) — run once, after the
-- base pipeline has created the tables.
ALTER TABLE staging_clinical_trials SET SCHEMA raw;
ALTER TABLE staging_sample SET SCHEMA raw;
ALTER TABLE organizations SET SCHEMA core;
ALTER TABLE trials SET SCHEMA core;
ALTER TABLE conditions SET SCHEMA core;
ALTER TABLE interventions SET SCHEMA core;
ALTER TABLE trial_conditions SET SCHEMA core;
ALTER TABLE trial_interventions SET SCHEMA core;

-- Reporting view (create after the move, since it references core.*)
CREATE OR REPLACE VIEW reporting.organization_activity AS
SELECT o.organization_name, COUNT(*) AS trials
FROM core.trials t
JOIN core.organizations o ON t.organization_id = o.organization_id
GROUP BY o.organization_name;


-- ------------------------------------------------------------
-- 3. PRIVILEGE GRANTS (least privilege, corrected)
-- ------------------------------------------------------------

-- data_steward: full control over raw + core, read on reporting
GRANT USAGE ON SCHEMA raw, core, reporting TO data_steward;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA raw TO data_steward;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core TO data_steward;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO data_steward;

-- data_analyst: read-only on core + reporting, NO access to raw
GRANT USAGE ON SCHEMA core, reporting TO data_analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO data_analyst;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO data_analyst;

-- reporting_tool: reporting views only
GRANT USAGE ON SCHEMA reporting TO reporting_tool;
GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO reporting_tool;

-- Explicit revokes: REVOKE ALL ON SCHEMA only removes CREATE/USAGE
-- on the schema itself, NOT table-level grants already applied.
-- Revoke both layers so the boundary actually holds.
REVOKE ALL ON SCHEMA raw FROM data_analyst, reporting_tool;
REVOKE ALL ON ALL TABLES IN SCHEMA raw FROM data_analyst, reporting_tool;
REVOKE ALL ON SCHEMA core FROM reporting_tool;
REVOKE ALL ON ALL TABLES IN SCHEMA core FROM reporting_tool;

-- Default privileges: without this, tables/views created AFTER
-- this script runs default to no access for these roles, silently
-- breaking the pipeline on the next load.
ALTER DEFAULT PRIVILEGES IN SCHEMA raw GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO data_steward;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO data_steward;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT ON TABLES TO data_analyst;
ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO data_steward, data_analyst, reporting_tool;


-- ------------------------------------------------------------
-- 4. AUDIT TRAIL
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.load_audit_log (
    load_id     SERIAL PRIMARY KEY,
    table_name  TEXT NOT NULL,
    loaded_by   TEXT NOT NULL DEFAULT current_user,
    loaded_at   TIMESTAMP NOT NULL DEFAULT now(),
    row_count   INTEGER NOT NULL,
    notes       TEXT
);

INSERT INTO core.load_audit_log (table_name, row_count, notes)
VALUES ('trials', (SELECT COUNT(*) FROM core.trials), 'Initial governed-schema load');


-- ------------------------------------------------------------
-- 5. COLUMN-LEVEL SENSITIVITY (run AFTER the schema move, since
--    core.trials doesn't exist until section 2 has executed)
-- ------------------------------------------------------------
COMMENT ON COLUMN core.trials.responsible_party IS
  'Organization/individual name — treat as sensitive; do not expose in public-facing exports without review.';

COMMENT ON TABLE core.trials IS
  'Governed trial-level data. Access via reporting.* views only for BI tools; direct table access restricted to data_steward and data_analyst roles.';
