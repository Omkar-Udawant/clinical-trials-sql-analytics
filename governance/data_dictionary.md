# Data Dictionary — Clinical Trials Analytics Database

Documents every table in the governed `core` schema: its purpose, columns,
source, and access rules. Maintained alongside `governance.sql`.

---

## core.organizations

| Column | Type | Description | Source | Sensitivity |
|---|---|---|---|---|
| organization_id | SERIAL (PK) | Surrogate key | Generated | — |
| organization_name | TEXT | Sponsoring/research organization name | ClinicalTrials.gov `organization_full_name` | Public |
| organization_class | TEXT | Org type (e.g. Industry, NIH, Other) | ClinicalTrials.gov `organization_class` | Public |

**Data quality rule:** deduplicated via `DISTINCT` at load time — one row per unique (name, class) pair.

---

## core.trials

| Column | Type | Description | Source | Sensitivity |
|---|---|---|---|---|
| trial_id | SERIAL (PK) | Surrogate key | Generated | — |
| brief_title / full_title | TEXT | Trial title(s) | ClinicalTrials.gov | Public |
| responsible_party | TEXT | Named responsible party | ClinicalTrials.gov | **Sensitive** — see governance.sql comment |
| study_type, primary_purpose, phase, status | TEXT | Trial classification fields | ClinicalTrials.gov | Public |
| start_date | DATE | Trial start date | ClinicalTrials.gov (validated) | Public |
| standard_age | TEXT | Eligible age group | ClinicalTrials.gov | Public |
| organization_id | INT (FK → organizations) | Sponsoring org | Derived | — |

**Data quality rule:** `start_date` accepted only if it matches `YYYY-MM` or
`YYYY-MM-DD`; anything else is set to `NULL` rather than silently
miscast, so downstream reports never show a fabricated date.

---

## core.conditions / core.interventions

Normalized out of the raw semicolon-delimited `conditions` /
`interventions` text fields via `string_to_array` + `UNNEST` + `TRIM`,
then deduplicated with `DISTINCT`.

- `conditions` is deduplicated on `condition_name` alone.
- `interventions` is deduplicated on the **pair** `(intervention_name,
  description)` — two interventions with the same name but a different
  description are stored as separate rows. This was confirmed by
  running `data_quality_checks.sql` §4 against a live test load.

Verified live (test DB, synthetic data): 0 duplicate rows on either
table after load — see `data_quality_checks.sql` for the query used.

---

## core.trial_conditions / core.trial_interventions

Many-to-many junction tables. Inserts are idempotent
(`ON CONFLICT DO NOTHING`) so re-running a load never creates duplicate
trial-condition or trial-intervention pairs.

---

## reporting.organization_activity (view)

Read-only aggregate view (`trials per organization`) exposed to the
`reporting_tool` and `data_analyst` roles. This is the only object the
Power BI dashboard is granted access to — it never queries `core` or
`raw` tables directly.

---

## Access Summary

| Role | raw schema | core schema | reporting schema |
|---|---|---|---|
| data_steward | Read/Write | Read/Write | Read |
| data_analyst | No access | Read only | Read only |
| reporting_tool (Power BI) | No access | No access | Read only |

## Known Limitations (found via live testing, not yet fixed in the base pipeline)

1. **Date parsing could crash the entire load.** The original
   `clinical_trials_db.sql` validates date *format* via regex but not
   valid *ranges* — a value like `2021-13-40` matches the shape pattern
   and reaches `TO_DATE`, which throws a hard error and rolls back the
   whole `INSERT INTO trials` statement (zero trials loaded, cascading
   to zero rows in the junction tables). **Not yet fixed in the base
   pipeline** — `governance/safe_date_fix.sql` provides a
   `safe_to_date()` function with exception handling and the exact
   one-line change needed in `sql/clinical_trials_db.sql`. Apply that
   fix before relying on the "nulls malformed dates" claim anywhere.
2. **Trial-to-staging join uses `brief_title`, which is not guaranteed
   unique.** Two trials sharing a title get their conditions/
   interventions joined by title match, risking misattribution that
   won't show up as row loss. See `data_quality_checks.sql` §7 for a
   query that surfaces affected trials. Long-term fix: carry a stable
   row identifier from staging through to `trials` instead of joining
   on title text.

## Refresh Cadence

Development subset (1,000 rows) refreshed manually during project
iteration. In a production setting this would run as a scheduled job
(e.g. nightly) with the `core.load_audit_log` table providing a record
of each run for traceability.
