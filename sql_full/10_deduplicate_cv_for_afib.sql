-- Deduplicate cardioversion cohort table (BigQuery)
-- Input:  tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib
-- Output: tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib  (replaced, distinct rows)

-- Caution: destructive replace of the target table.
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib` AS
SELECT DISTINCT *
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib`;

