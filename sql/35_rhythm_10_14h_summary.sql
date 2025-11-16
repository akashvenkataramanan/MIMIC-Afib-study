-- Summary stats for 10–14h rhythm table
-- Input: {{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h

-- Basic proportions (naive flags)
SELECT
  COUNT(*) AS n_cv,
  AVG(CAST(has_data_10_14h AS INT64)) AS p_any_rhythm_10_14h,
  AVG(CAST(any_af_10_14h_naive AS INT64)) AS p_af_10_14h,
  AVG(CAST(any_sinus_10_14h_naive AS INT64)) AS p_sinus_10_14h,
  AVG(CAST(any_other_10_14h_naive AS INT64)) AS p_other_10_14h
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h`;

-- Category breakdowns (naive vs censored)
-- Naive categories
SELECT rhythm_10_14h_naive_category AS category, COUNT(*) AS n
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h`
GROUP BY category
ORDER BY n DESC;

-- Censored categories
SELECT rhythm_10_14h_censored_category AS category, COUNT(*) AS n
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h`
GROUP BY category
ORDER BY n DESC;

