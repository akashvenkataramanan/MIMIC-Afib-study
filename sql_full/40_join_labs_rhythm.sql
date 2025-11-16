-- Join labs-within-24h with rhythm-10_14h (BigQuery)
-- Input:
--   - tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24
--   - tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_rhythm_10_14h
-- Output:
--   - tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h` AS
SELECT
  l.*,  -- includes potassium/magnesium values and bins
  r.has_time_obs,
  r.has_data_10_14h,
  r.rhythm_10_14h_naive_category,
  r.has_data_10_14h_censored,
  r.rhythm_10_14h_censored_category
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24` l
LEFT JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_rhythm_10_14h` r
  USING (subject_id, hadm_id, stay_id, cv_time);

