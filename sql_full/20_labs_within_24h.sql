-- Most-recent Potassium and Magnesium within 24h BEFORE cardioversion (BigQuery)
-- Input:  tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib
-- Output: tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24
-- Source: physionet-data.mimiciv_3_1_hosp.labevents

-- Tunable lookback window
DECLARE LOOKBACK_HOURS INT64 DEFAULT 24;

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24` AS
WITH
cv AS (
  SELECT
    subject_id, hadm_id, stay_id, cv_time, cv_endtime,
    location, locationcategory, ordercategoryname, ordercategorydescription,
    statusdescription, cv_inside_af_episode, has_nearby_arrest,
    mins_to_nearest_arrest, shock_type_label
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib`
),

-- Most recent K within LOOKBACK_HOURS before CV
k_candidates AS (
  SELECT
    c.subject_id, c.hadm_id, c.stay_id, c.cv_time,
    le.charttime AS k_time,
    -- Potassium already in mEq/L for these itemids
    le.valuenum  AS k_meq_l,
    ROW_NUMBER() OVER (
      PARTITION BY c.subject_id, c.hadm_id, c.stay_id, c.cv_time
      ORDER BY le.charttime DESC
    ) AS rn
  FROM cv c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = c.subject_id
   AND le.hadm_id    = c.hadm_id
  WHERE le.itemid IN (50971, 52610)                  -- Potassium (blood, chemistry)
    AND le.valuenum IS NOT NULL
    AND (le.valueuom IS NULL OR LOWER(le.valueuom) = 'meq/l')
    AND le.charttime BETWEEN DATETIME_SUB(c.cv_time, INTERVAL LOOKBACK_HOURS HOUR) AND c.cv_time
),

-- Most recent Mg within LOOKBACK_HOURS before CV
mg_candidates AS (
  SELECT
    c.subject_id, c.hadm_id, c.stay_id, c.cv_time,
    le.charttime AS mg_time,
    -- Magnesium already in mg/dL for this itemid
    le.valuenum  AS mg_mgdl,
    ROW_NUMBER() OVER (
      PARTITION BY c.subject_id, c.hadm_id, c.stay_id, c.cv_time
      ORDER BY le.charttime DESC
    ) AS rn
  FROM cv c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = c.subject_id
   AND le.hadm_id    = c.hadm_id
  WHERE le.itemid = 50960                             -- Magnesium (blood, chemistry)
    AND le.valuenum IS NOT NULL
    AND (le.valueuom IS NULL OR LOWER(le.valueuom) = 'mg/dl')
    AND le.charttime BETWEEN DATETIME_SUB(c.cv_time, INTERVAL LOOKBACK_HOURS HOUR) AND c.cv_time
),

k_latest  AS (SELECT * EXCEPT(rn) FROM k_candidates  WHERE rn = 1),
mg_latest AS (SELECT * EXCEPT(rn) FROM mg_candidates WHERE rn = 1)

SELECT
  c.*,

  -- Potassium
  kl.k_time,
  kl.k_meq_l AS potassium_meq_l,
  CASE
    WHEN kl.k_meq_l IS NULL                      THEN NULL
    WHEN kl.k_meq_l < 3.5                        THEN '<3.5'
    WHEN kl.k_meq_l >= 3.5 AND kl.k_meq_l < 4.5  THEN '3.5–<4.5'
    WHEN kl.k_meq_l >= 4.5 AND kl.k_meq_l <= 5.5 THEN '4.5–5.5'
    ELSE '>5.5'
  END AS potassium_bin,

  -- Magnesium
  ml.mg_time,
  ml.mg_mgdl AS magnesium_mgdl,
  CASE
    WHEN ml.mg_mgdl IS NULL                      THEN NULL
    WHEN ml.mg_mgdl < 1.0                        THEN '0–<1'
    WHEN ml.mg_mgdl >= 1.0 AND ml.mg_mgdl < 2.0  THEN '1–<2'
    ELSE '>2'
  END AS magnesium_bin,

  -- Convenience flags and timing deltas
  (ml.mg_time IS NOT NULL) AS had_mg_within_24h,
  (kl.k_time  IS NOT NULL) AS had_k_within_24h,
  TIMESTAMP_DIFF(TIMESTAMP(c.cv_time), TIMESTAMP(kl.k_time), MINUTE) AS mins_from_k_to_cv,
  TIMESTAMP_DIFF(TIMESTAMP(c.cv_time), TIMESTAMP(ml.mg_time), MINUTE) AS mins_from_mg_to_cv

FROM cv c
LEFT JOIN k_latest kl
  ON kl.subject_id = c.subject_id AND kl.hadm_id = c.hadm_id
 AND kl.stay_id = c.stay_id AND kl.cv_time = c.cv_time
LEFT JOIN mg_latest ml
  ON ml.subject_id = c.subject_id AND ml.hadm_id = c.hadm_id
 AND ml.stay_id = c.stay_id AND ml.cv_time = c.cv_time
ORDER BY c.stay_id, c.cv_time;

