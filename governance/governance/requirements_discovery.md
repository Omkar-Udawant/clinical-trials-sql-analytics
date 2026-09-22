# Requirements & Discovery Notes — Clinical Trials Analytics

This project was self-directed (no live client/stakeholder), so this
document records the research and discovery process actually used to
define scope, data source, and success criteria — the same process
that would normally happen through stakeholder interviews on a team
project.

## 1. Problem framing

Started from a broad question: *"Can public clinical-trial data reveal
which organizations and disease areas dominate global research
activity, in a structure clean enough to support repeatable SQL
analysis?"* This was narrowed down by researching what data was
actually available and what a governed schema would need to support.

## 2. Source evaluation

Evaluated ClinicalTrials.gov (via a Kaggle mirror) against alternative
public health datasets. Selected it because:
- It's the canonical public registry for global clinical trials (a
  credible, authoritative source rather than a scraped/aggregated one).
- It includes structured fields (phase, status, organization,
  condition, intervention) suitable for relational normalization,
  rather than free-text-only data.
- At ~496,000 records, it was large enough to require real schema
  design decisions (dedup, many-to-many relationships) rather than a
  flat spreadsheet.

## 3. Requirements derived from the data itself

Before writing any SQL, the raw export was profiled to identify what
the schema needed to handle:

| Discovery finding | Requirement it produced |
|---|---|
| `conditions` and `interventions` fields contain semicolon-delimited multi-value strings | Schema needs many-to-many junction tables, not flat columns |
| `start_date` appears in at least two formats (`YYYY-MM`, `YYYY-MM-DD`) and sometimes missing | Load logic must validate/normalize dates and null out unparseable values rather than fail or miscast |
| Organization names repeat across many trial rows | Organizations must be a separate deduplicated table, not repeated text |
| Full dataset (~496K rows) exceeds GitHub's practical file-size limits | Development/demo scope reduced to a representative 1,000-row subset, documented explicitly rather than silently substituted |

## 4. Success criteria defined upfront

- Schema must eliminate duplicate organization/condition/intervention
  entries (data-quality requirement).
- Every trial must be traceable to a real organization via foreign key
  (referential-integrity requirement).
- Final structure must support the analytical questions identified in
  the project's business-objectives list (top organizations, disease
  focus areas, phase distribution, etc.) without further reshaping.

## 5. What this maps to in a team setting

On a team, steps 1–3 above are normally done through stakeholder
interviews and a requirements document before any schema is built.
Here they were done through direct dataset research/profiling —
functionally the same discovery process, applied to a public dataset
instead of a live business stakeholder.
