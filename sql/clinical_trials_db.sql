CREATE TABLE organizations (
organization_id SERIAL PRIMARY KEY,
organization_name TEXT,
organization_class TEXT
);

CREATE TABLE trials (
trial_id SERIAL PRIMARY KEY,
brief_title TEXT,
full_title TEXT,
responsible_party TEXT,
study_type TEXT,
primary_purpose TEXT,
phase TEXT,
status TEXT,
start_date DATE,
standard_age TEXT,
organization_id INT,
FOREIGN KEY (organization_id) REFERENCES organizations(organization_id)
);

CREATE TABLE conditions (
condition_id SERIAL PRIMARY KEY,
condition_name TEXT
);

CREATE TABLE interventions (
intervention_id SERIAL PRIMARY KEY,
intervention_name TEXT,
description TEXT
);

CREATE TABLE trial_conditions (
trial_id INT,
condition_id INT,
PRIMARY KEY (trial_id, condition_id),
FOREIGN KEY (trial_id) REFERENCES trials(trial_id),
FOREIGN KEY (condition_id) REFERENCES conditions(condition_id)
);

CREATE TABLE trial_interventions (
    trial_id INT,
    intervention_id INT,
    PRIMARY KEY (trial_id, intervention_id),
    FOREIGN KEY (trial_id) REFERENCES trials(trial_id),
    FOREIGN KEY (intervention_id) REFERENCES interventions(intervention_id)
);

CREATE TABLE staging_clinical_trials (
organization_full_name TEXT,
organization_class TEXT,
responsible_party TEXT,
brief_title TEXT,
full_title TEXT,
overall_status TEXT,
start_date TEXT,
standard_age TEXT,
conditions TEXT,
primary_purpose TEXT,
interventions TEXT,
intervention_description TEXT,
study_type TEXT,
phases TEXT,
outcome_measure TEXT,
medical_subject_headings TEXT
);

COPY staging_clinical_trials
FROM 'C:/data/clean_clinical_trials.csv'
DELIMITER ','
CSV HEADER;

SELECT COUNT(*) FROM staging_clinical_trials;

SELECT COUNT(*) FROM organizations;
SELECT COUNT(*) FROM trials;
SELECT COUNT(*) FROM conditions;
SELECT COUNT(*) FROM interventions;
SELECT COUNT(*) FROM trial_conditions;
SELECT COUNT(*) FROM trial_interventions;

SELECT COUNT(*) FROM staging_clinical_trials;

CREATE TABLE staging_sample AS
SELECT *
FROM staging_clinical_trials
LIMIT 1000;

SELECT COUNT(*) FROM staging_sample;

INSERT INTO organizations (organization_name, organization_class)
SELECT DISTINCT
organization_full_name,
organization_class
FROM staging_sample;

SELECT COUNT(*) FROM organizations;

INSERT INTO trials (
brief_title,
full_title,
responsible_party,
study_type,
primary_purpose,
phase,
status,
start_date,
standard_age,
organization_id
)

SELECT
s.brief_title,
s.full_title,
s.responsible_party,
s.study_type,
s.primary_purpose,
s.phases,
s.overall_status,

CASE
WHEN s.start_date ~ '^\d{4}-\d{2}$'
THEN TO_DATE(s.start_date || '-01','YYYY-MM-DD')

WHEN s.start_date ~ '^\d{4}-\d{2}-\d{2}$'
THEN TO_DATE(s.start_date,'YYYY-MM-DD')

ELSE NULL
END,

s.standard_age,
o.organization_id

FROM staging_sample s
JOIN organizations o
ON s.organization_full_name = o.organization_name;

SELECT COUNT(*) FROM trials;

INSERT INTO conditions (condition_name)

SELECT DISTINCT
TRIM(condition_name)

FROM staging_sample,
LATERAL UNNEST(string_to_array(conditions,';')) AS condition_name

WHERE condition_name IS NOT NULL;

SELECT COUNT(*) FROM conditions;

SELECT * 
FROM conditions
LIMIT 10;


SELECT COUNT(*) FROM conditions;

INSERT INTO interventions (intervention_name, description)

SELECT DISTINCT
TRIM(intervention_name),
intervention_description

FROM staging_sample,
LATERAL UNNEST(string_to_array(interventions,';')) AS intervention_name

WHERE intervention_name IS NOT NULL;

SELECT COUNT(*) FROM interventions;

INSERT INTO trial_conditions (trial_id, condition_id)

SELECT DISTINCT
t.trial_id,
c.condition_id

FROM staging_sample s

JOIN trials t
ON s.brief_title = t.brief_title

JOIN LATERAL UNNEST(string_to_array(s.conditions,';')) AS cond(condition_name)
ON TRUE

JOIN conditions c
ON TRIM(cond.condition_name) = c.condition_name

ON CONFLICT DO NOTHING;

SELECT COUNT(*) FROM trial_conditions;

INSERT INTO trial_interventions (trial_id, intervention_id)

SELECT DISTINCT
t.trial_id,
i.intervention_id

FROM staging_sample s

JOIN trials t
ON s.brief_title = t.brief_title

JOIN LATERAL UNNEST(string_to_array(s.interventions,';')) AS inter(intervention_name)
ON TRUE

JOIN interventions i
ON TRIM(inter.intervention_name) = i.intervention_name

ON CONFLICT DO NOTHING;

SELECT COUNT(*) FROM trial_interventions;

SELECT COUNT(*) AS total_trials FROM trials;

SELECT COUNT(*) AS total_organizations FROM organizations;

SELECT COUNT(*) AS total_conditions FROM conditions;

SELECT COUNT(*) AS total_interventions FROM interventions;

SELECT
o.organization_name,
COUNT(t.trial_id) AS total_trials
FROM trials t
JOIN organizations o
ON t.organization_id = o.organization_id
GROUP BY o.organization_name
ORDER BY total_trials DESC
LIMIT 10;

SELECT
organization_class,
COUNT(*) AS trials
FROM organizations o
JOIN trials t
ON o.organization_id = t.organization_id
GROUP BY organization_class
ORDER BY trials DESC;


SELECT
c.condition_name,
COUNT(tc.trial_id) AS total_trials
FROM trial_conditions tc
JOIN conditions c
ON tc.condition_id = c.condition_id
GROUP BY c.condition_name
ORDER BY total_trials DESC
LIMIT 10;

SELECT
phase,
COUNT(*) AS trials
FROM trials
GROUP BY phase
ORDER BY trials DESC;

SELECT
study_type,
COUNT(*) AS trials
FROM trials
GROUP BY study_type
ORDER BY trials DESC;

SELECT
i.intervention_name,
COUNT(ti.trial_id) AS usage_count
FROM trial_interventions ti
JOIN interventions i
ON ti.intervention_id = i.intervention_id
GROUP BY i.intervention_name
ORDER BY usage_count DESC
LIMIT 10;

SELECT
c.condition_name,
i.intervention_name,
COUNT(*) AS usage
FROM trial_conditions tc
JOIN trial_interventions ti
ON tc.trial_id = ti.trial_id
JOIN conditions c
ON tc.condition_id = c.condition_id
JOIN interventions i
ON ti.intervention_id = i.intervention_id
GROUP BY c.condition_name, i.intervention_name
ORDER BY usage DESC
LIMIT 15;

CREATE VIEW organization_activity AS
SELECT
o.organization_name,
COUNT(*) AS trials
FROM trials t
JOIN organizations o
ON t.organization_id = o.organization_id
GROUP BY o.organization_name;

SELECT * FROM organization_activity;










