-- Identify ICU stays admitted with AF or Atrial Flutter (BigQuery)
-- Output: tactical-grid-454202-h6.mimic_af_electrolytes.admitted_with_af_or_aflutter
--
-- Plain-English goal
-- - For each ICU stay, look at the first documented rhythm near ICU admission.
-- - If that first rhythm indicates AF or Atrial Flutter, mark the stay as
--   "admitted with AF/AFlutter".
-- - No segmentation or complex time series processing is needed here.
--
-- Tunable assumption
-- - We treat "on admission" as the first rhythm observed within ADMISSION_WINDOW_MIN
--   minutes after ICU intime. Default: 120 minutes (2 hours). Adjust if needed.

DECLARE ADMISSION_WINDOW_MIN INT64 DEFAULT 120;  -- minutes after ICU intime

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.admitted_with_af_or_aflutter` AS
WITH
-- 1) ICU stays with admission time
icu AS (
  SELECT
    isty.subject_id,
    isty.hadm_id,
    isty.stay_id,
    CAST(isty.intime AS DATETIME)  AS icu_intime,
    CAST(isty.outtime AS DATETIME) AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` isty
),

-- 2) Identify rhythm itemids (future-proof discovery)
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- 3) Rhythm observations near admission window
rhythm_obs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    CAST(ce.charttime AS DATETIME) AS chart_dt,
    LOWER(TRIM(ce.value)) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu i USING (subject_id, hadm_id, stay_id)
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
    AND ce.charttime >= TIMESTAMP(i.icu_intime)
    AND ce.charttime <  TIMESTAMP_ADD(TIMESTAMP(i.icu_intime), INTERVAL ADMISSION_WINDOW_MIN MINUTE)
),

-- 4) Classify AF and Atrial Flutter via simple regex
classified AS (
  SELECT
    r.*,
    REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
    REGEXP_CONTAINS(value_lc, r"(atrial.?flut|a[- ]?flut)") AS is_aflutter
  FROM rhythm_obs r
),

-- 5) Pick the first rhythm observed in the window per stay
first_rhythm AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.chart_dt AS first_chart_dt,
    c.value_lc AS first_value_lc,
    c.is_af    AS first_is_af,
    c.is_aflutter AS first_is_aflutter
  FROM classified c
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.chart_dt) = 1
),

-- 6) Join back to ICU stays so we retain stays even with no rhythm in the window
joined AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.icu_intime,
    i.icu_outtime,
    f.first_chart_dt AS first_rhythm_time,
    f.first_value_lc AS first_rhythm_value_lc,
    f.first_is_af    AS first_is_af,
    f.first_is_aflutter AS first_is_aflutter
  FROM icu i
  LEFT JOIN first_rhythm f USING (subject_id, hadm_id, stay_id)
)

-- 7) Final flag: admitted_with_af_or_aflutter if first rhythm is AF or Flutter
SELECT
  subject_id,
  hadm_id,
  stay_id,
  icu_intime,
  icu_outtime,
  first_rhythm_time,
  first_rhythm_value_lc,
  first_is_af,
  first_is_aflutter,
  (COALESCE(first_is_af, FALSE) OR COALESCE(first_is_aflutter, FALSE)) AS admitted_with_af_or_aflutter
FROM joined
ORDER BY stay_id;
