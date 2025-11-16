-- Build AF or Atrial Flutter episodes from ICU rhythm observations (BigQuery)
-- Output: tactical-grid-454202-h6.mimic_af_electrolytes.af_or_aflutter_episodes
--
-- Purpose
-- - Align episode extraction with downstream analyses that treat AF and
--   Atrial Flutter together. Segments are contiguous periods where either
--   AF or Atrial Flutter is charted.
--
-- What this does
-- 1) Finds ICU rhythm chart rows using d_items to locate the itemids.
-- 2) Tags each row as AF, Atrial Flutter, or neither via regex on text.
-- 3) Deduplicates rows at the same time per stay.
-- 4) Segments the time series by a boolean: (AF OR Flutter).
-- 5) Keeps only segments where (AF OR Flutter) is true.
-- 6) Clips segment end to ICU discharge and computes duration.
-- 7) Adds flags showing if AF and/or Flutter occurred within the segment,
--    and a simple label: 'af', 'aflutter', or 'mixed_af_and_aflutter'.

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_or_aflutter_episodes` AS
WITH
-- 0. Identify itemids for rhythm in ICU CHARTEVENTS
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- 1. Rhythm observations with normalized text
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

-- 2. Tag AF and Flutter using regex
labeled AS (
  SELECT
    stay_id,
    chart_dt,
    -- AF patterns: atrial fibrillation, a-fib, afib
    REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
    -- Atrial flutter patterns: 'a flut', 'atrial flut'
    REGEXP_CONTAINS(value_lc, r"(atrial.?flut|a[- ]?flut)") AS is_aflutter,
    value_lc AS rhythm_value
  FROM rhythm_obs
),

-- 3. Deduplicate per stay_id+time
dedup AS (
  SELECT stay_id, chart_dt, is_af, is_aflutter, rhythm_value
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY stay_id, chart_dt ORDER BY is_af DESC, is_aflutter DESC) AS rn
    FROM labeled
  )
  WHERE rn = 1
),

-- 4. Segment on the boolean (AF OR Flutter)
flagged AS (
  SELECT *, (is_af OR is_aflutter) AS is_af_or_aflutter FROM dedup
),
lagged AS (
  SELECT
    stay_id,
    chart_dt,
    is_af,
    is_aflutter,
    is_af_or_aflutter,
    LAG(is_af_or_aflutter) OVER (PARTITION BY stay_id ORDER BY chart_dt) AS prev_flag
  FROM flagged
),
segmented AS (
  SELECT
    stay_id,
    chart_dt,
    is_af,
    is_aflutter,
    is_af_or_aflutter,
    SUM(CASE WHEN is_af_or_aflutter != prev_flag OR prev_flag IS NULL THEN 1 ELSE 0 END)
      OVER (PARTITION BY stay_id ORDER BY chart_dt) AS segment_id
  FROM lagged
),

-- 5. Collapse to segments and keep only AF/Flutter segments
segments AS (
  SELECT
    stay_id,
    segment_id,
    MIN(chart_dt) AS segment_start,
    MAX(chart_dt) AS segment_end,
    LOGICAL_OR(is_af) AS has_af,
    LOGICAL_OR(is_aflutter) AS has_aflutter,
    LOGICAL_OR(is_af_or_aflutter) AS is_af_or_aflutter,
    COUNT(*) AS num_observations
  FROM segmented
  GROUP BY stay_id, segment_id
),
af_or_aflutter_only AS (
  SELECT * FROM segments WHERE is_af_or_aflutter
),

-- 6. Clip end to ICU outtime
clipped AS (
  SELECT
    seg.stay_id,
    seg.segment_start AS episode_start,
    LEAST(seg.segment_end, CAST(icu.outtime AS DATETIME)) AS episode_end,
    seg.has_af,
    seg.has_aflutter,
    seg.num_observations
  FROM af_or_aflutter_only seg
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.stay_id = seg.stay_id
)

-- 7. Final episodes with label and duration
SELECT
  stay_id,
  episode_start,
  episode_end,
  SAFE_DIVIDE(DATETIME_DIFF(episode_end, episode_start, MINUTE), 60.0) AS episode_duration_hours,
  CASE
    WHEN has_af AND has_aflutter THEN 'mixed_af_and_aflutter'
    WHEN has_af THEN 'af'
    WHEN has_aflutter THEN 'aflutter'
    ELSE 'unknown'
  END AS episode_label,
  has_af,
  has_aflutter,
  ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY episode_start) AS episode_number,
  num_observations
FROM clipped
WHERE DATETIME_DIFF(episode_end, episode_start, MINUTE) > 0
ORDER BY stay_id, episode_start;

