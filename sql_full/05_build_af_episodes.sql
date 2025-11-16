-- Build AF episodes table from ICU rhythm observations (BigQuery)
-- Output: tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes
--
-- What this does, in plain English:
-- 1) Finds the ICU charted rhythm rows (e.g., "Heart Rhythm").
-- 2) Marks each row as AF or not AF using a simple regex (catches "a-fib", "afib").
-- 3) Removes duplicate entries at the same time for the same stay.
-- 4) Groups contiguous rows with the same AF flag into segments.
-- 5) Keeps only the AF segments and sets each episode's start and end.
-- 6) Clips the episode end to ICU discharge time and computes duration.
-- 7) Outputs one row per AF episode with a sequential episode number.
--
-- Why not use COALESCE(LEAD(next segment start), ICU out)?
-- - In earlier attempts, that extended AF segments incorrectly. The fix is
--   to use the segment's own end time and clip to ICU outtime.

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes` AS
WITH
-- 0. Identify itemids for rhythm in ICU CHARTEVENTS (future-proof approach)
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- 1. Pull rhythm observations with non-null values/times; normalize text
rhythm_obs AS (
  SELECT
    ce.stay_id,
    CAST(ce.charttime AS DATETIME) AS chart_dt,
    LOWER(TRIM(ce.value)) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
),

-- 2. Tag AF using a relaxed regex to capture common variants
labeled AS (
  SELECT
    stay_id,
    chart_dt,
    REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
    value_lc AS rhythm_value
  FROM rhythm_obs
),

-- 3. Remove duplicates if multiple entries share the same stay_id+time
dedup AS (
  SELECT stay_id, chart_dt, is_af, rhythm_value
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY stay_id, chart_dt ORDER BY is_af DESC) AS rn
    FROM labeled
  )
  WHERE rn = 1
),

-- 4. Determine change points where AF/non-AF switches
lagged AS (
  SELECT
    stay_id,
    chart_dt,
    is_af,
    rhythm_value,
    LAG(is_af) OVER (PARTITION BY stay_id ORDER BY chart_dt) AS prev_is_af
  FROM dedup
),
segmented AS (
  SELECT
    stay_id,
    chart_dt,
    is_af,
    rhythm_value,
    SUM(CASE WHEN is_af != prev_is_af OR prev_is_af IS NULL THEN 1 ELSE 0 END)
      OVER (PARTITION BY stay_id ORDER BY chart_dt) AS segment_id
  FROM lagged
),

-- 5. Collapse to segment start/end with AF flag
segments AS (
  SELECT
    stay_id,
    segment_id,
    MIN(chart_dt) AS segment_start,
    MAX(chart_dt) AS segment_end,
    ANY_VALUE(is_af) AS is_af,
    COUNT(*) AS num_observations
  FROM segmented
  GROUP BY stay_id, segment_id
),

-- 6. Keep AF-only segments and clip to ICU outtime
af_only AS (
  SELECT
    seg.stay_id,
    seg.segment_start AS af_start,
    LEAST(seg.segment_end, CAST(icu.outtime AS DATETIME)) AS af_end,
    seg.num_observations
  FROM segments seg
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.stay_id = seg.stay_id
  WHERE seg.is_af = TRUE
)

-- 7. Final AF episode rows
SELECT
  stay_id,
  af_start,
  af_end,
  SAFE_DIVIDE(DATETIME_DIFF(af_end, af_start, MINUTE), 60.0) AS af_duration_hours,
  ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY af_start) AS episode_number,
  num_observations
FROM af_only
WHERE DATETIME_DIFF(af_end, af_start, MINUTE) > 0
ORDER BY stay_id, af_start;

