-- ============================================================
-- data_quality_checks.sql (v2 — corrected after live test run)
-- Run against the "core" schema after governance.sql has moved
-- the tables there.
-- ============================================================


-- 1. RECONCILIATION
SELECT
    (SELECT COUNT(*) FROM raw.staging_sample)  AS staging_rows,
    (SELECT COUNT(*) FROM core.trials)         AS trials_rows,
    (SELECT COUNT(*) FROM raw.staging_sample) - (SELECT COUNT(*) FROM core.trials) AS row_loss;


-- 2. NULL/MISSING DATE RATE
SELECT
    COUNT(*) FILTER (WHERE start_date IS NULL) AS null_dates,
    COUNT(*) AS total_trials,
    ROUND(100.0 * COUNT(*) FILTER (WHERE start_date IS NULL) / NULLIF(COUNT(*), 0), 2) AS pct_null_dates
FROM core.trials;


-- 3. ORPHAN CHECKS — expanded to cover ALL foreign-key relationships,
--    not just trial_conditions (original gap).
SELECT 'trial_conditions -> trials' AS check_name, COUNT(*) AS orphan_rows
FROM core.trial_conditions tc LEFT JOIN core.trials t ON tc.trial_id = t.trial_id
WHERE t.trial_id IS NULL
UNION ALL
SELECT 'trial_interventions -> trials', COUNT(*)
FROM core.trial_interventions ti LEFT JOIN core.trials t ON ti.trial_id = t.trial_id
WHERE t.trial_id IS NULL
UNION ALL
SELECT 'trials -> organizations', COUNT(*)
FROM core.trials t LEFT JOIN core.organizations o ON t.organization_id = o.organization_id
WHERE t.organization_id IS NOT NULL AND o.organization_id IS NULL;
-- Expect orphan_rows = 0 on every row.


-- 4. DUPLICATE CHECK — organizations dedup key
SELECT organization_name, organization_class, COUNT(*)
FROM core.organizations
GROUP BY organization_name, organization_class
HAVING COUNT(*) > 1;
-- Expect 0 rows.

-- NOTE: interventions in this schema are deduplicated on
-- (intervention_name, description), NOT intervention_name alone —
-- two interventions with the same name but different descriptions
-- are treated as distinct rows. Documented here so the data
-- dictionary and the actual dedup behavior agree.
SELECT intervention_name, description, COUNT(*)
FROM core.interventions
GROUP BY intervention_name, description
HAVING COUNT(*) > 1;
-- Expect 0 rows.


-- 5. COMPLETENESS
SELECT
    COUNT(*) FILTER (WHERE phase IS NULL OR phase = '')       AS missing_phase,
    COUNT(*) FILTER (WHERE study_type IS NULL OR study_type = '') AS missing_study_type,
    COUNT(*) FILTER (WHERE status IS NULL OR status = '')     AS missing_status,
    COUNT(*) AS total_trials
FROM core.trials;


-- 6. PARSE CHECK — fixed to catch whitespace-only entries via TRIM,
--    not just exact empty strings (original gap).
SELECT condition_name FROM core.conditions WHERE TRIM(condition_name) = '' OR condition_name IS NULL;
SELECT intervention_name FROM core.interventions WHERE TRIM(intervention_name) = '' OR intervention_name IS NULL;
-- Expect 0 rows from both.


-- 7. KNOWN LIMITATION (documented, not silently fixed): the load
-- logic joins staging rows back to trials via brief_title, which
-- is NOT guaranteed unique. Two distinct trials sharing a title
-- would be misattributed (rows joined to the wrong trial_id)
-- without necessarily showing up as row_loss in check #1 — the
-- row count could look correct while conditions/interventions are
-- linked to the wrong trial. This check estimates exposure:
SELECT brief_title, COUNT(*) AS duplicate_title_trials
FROM core.trials
GROUP BY brief_title
HAVING COUNT(*) > 1;
-- Any rows returned here indicate trials at risk of condition/
-- intervention misattribution. Long-term fix: carry a stable
-- staging row id through the pipeline and join on that instead
-- of brief_title.
