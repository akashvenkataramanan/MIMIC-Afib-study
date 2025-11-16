-- Association tables for K/Mg vs 10–14h rhythm categories (BigQuery)
-- Input:  tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h
-- Outputs:
--   - kmg_rhythm10_14h_naive_counts
--   - kmg_rhythm10_14h_naive_pct
--   - kmg_rhythm10_14h_censored_counts
--   - kmg_rhythm10_14h_censored_pct

-- Naive counts by potassium_bin x magnesium_bin x category
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_naive_counts` AS
SELECT
  potassium_bin,
  magnesium_bin,
  rhythm_10_14h_naive_category AS category,
  COUNT(*) AS n
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- Naive percentages within each K/Mg bin
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_naive_pct` AS
WITH counts AS (
  SELECT
    potassium_bin,
    magnesium_bin,
    rhythm_10_14h_naive_category AS category,
    COUNT(*) AS n
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
  GROUP BY 1, 2, 3
)
SELECT
  potassium_bin,
  magnesium_bin,
  category,
  n,
  SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin) AS denom,
  SAFE_DIVIDE(n, SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin)) AS pct
FROM counts
ORDER BY 1, 2, 3;

-- Censored counts by potassium_bin x magnesium_bin x category
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_censored_counts` AS
SELECT
  potassium_bin,
  magnesium_bin,
  rhythm_10_14h_censored_category AS category,
  COUNT(*) AS n
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- Censored percentages within each K/Mg bin
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_censored_pct` AS
WITH counts AS (
  SELECT
    potassium_bin,
    magnesium_bin,
    rhythm_10_14h_censored_category AS category,
    COUNT(*) AS n
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
  GROUP BY 1, 2, 3
)
SELECT
  potassium_bin,
  magnesium_bin,
  category,
  n,
  SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin) AS denom,
  SAFE_DIVIDE(n, SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin)) AS pct
FROM counts
ORDER BY 1, 2, 3;

