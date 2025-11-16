-- Patients with any AF rhythm documented during an ICU stay
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_patients` AS

-- 1) Rhythm itemids from d_items
WITH rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- 2) All rhythm observations (non-null value & charttime)
rhythm_obs AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
),

-- 3) Label as AF vs not AF
labeled AS (
  SELECT
    stay_id,
    charttime,
    REGEXP_CONTAINS(
      value_lc,
      r'(atrial.?fibrillation|a[- ]fib|afib)'
    ) AS is_af,
    value_lc AS rhythm_value
  FROM rhythm_obs
),

-- 4) Remove duplicate observations at the same stay_id + charttime
dedup AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    rhythm_value
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY stay_id, charttime
        ORDER BY is_af DESC
      ) AS rn
    FROM labeled
  )
  WHERE rn = 1
),

-- 5) ICU stays where AF was ever documented
af_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    d.stay_id,
    MIN(d.charttime) AS first_af_time,
    MAX(d.charttime) AS last_af_time,
    COUNT(*)        AS num_af_observations
  FROM dedup d
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON d.stay_id = icu.stay_id
  WHERE d.is_af = TRUE
  GROUP BY
    icu.subject_id,
    icu.hadm_id,
    d.stay_id
)

SELECT
  subject_id,
  hadm_id,
  stay_id,
  first_af_time,
  last_af_time,
  num_af_observations
FROM af_stays
ORDER BY subject_id, stay_id;
