-- ============================================================
-- safe_date_fix.sql
-- Fixes a real bug found via live testing: the date validation
-- in sql/clinical_trials_db.sql checks format shape only
-- (regex), not valid ranges. A value like '2021-13-40' matches
-- '^\d{4}-\d{2}-\d{2}$' and reaches TO_DATE(), which throws a
-- hard error — crashing the entire INSERT INTO trials statement
-- (0 rows loaded, cascading to 0 rows in the junction tables).
--
-- HOW TO APPLY: run this once against your database (creates the
-- function), then replace the date CASE expression inside the
-- "INSERT INTO trials (...)" statement in sql/clinical_trials_db.sql
-- with a single call to safe_to_date(s.start_date), as shown below.
-- ============================================================

CREATE OR REPLACE FUNCTION safe_to_date(txt TEXT)
RETURNS DATE AS $$
BEGIN
    IF txt ~ '^\d{4}-\d{2}$' THEN
        RETURN TO_DATE(txt || '-01', 'YYYY-MM-DD');
    ELSIF txt ~ '^\d{4}-\d{2}-\d{2}$' THEN
        RETURN TO_DATE(txt, 'YYYY-MM-DD');
    ELSE
        RETURN NULL;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;  -- catches out-of-range month/day (e.g. 2021-13-40)
                  -- that the regex alone lets through
END;
$$ LANGUAGE plpgsql IMMUTABLE;


-- BEFORE (in sql/clinical_trials_db.sql), this block:
--
--   CASE
--   WHEN s.start_date ~ '^\d{4}-\d{2}$'
--   THEN TO_DATE(s.start_date || '-01','YYYY-MM-DD')
--   WHEN s.start_date ~ '^\d{4}-\d{2}-\d{2}$'
--   THEN TO_DATE(s.start_date,'YYYY-MM-DD')
--   ELSE NULL
--   END,
--
-- AFTER (replace with):
--
--   safe_to_date(s.start_date),
--
-- Everything else in the trials INSERT stays the same.
