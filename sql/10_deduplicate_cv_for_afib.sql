-- Deduplicate cardioversion cohort table
-- Input:  {{PROJECT}}.{{DATASET}}.cv_for_afib
-- Output: {{PROJECT}}.{{DATASET}}.cv_for_afib  (replaced, distinct rows)

-- Caution: destructive replace of the target table.
CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.cv_for_afib` AS
SELECT DISTINCT *
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib`;

