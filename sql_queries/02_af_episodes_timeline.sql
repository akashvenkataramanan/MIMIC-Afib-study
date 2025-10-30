-- Query 2: Build AF Episode Timeline
-- This query constructs AF episodes from rhythm charting in chartevents
-- IMPORTANT: Replace RHYTHM_ITEMIDS with the validated itemids from Query 1

-- PARAMETERS: Fill these after running rhythm discovery
DECLARE RHYTHM_ITEMIDS ARRAY<INT64> DEFAULT [220045, 223257];  -- UPDATE THESE!

WITH rhythm_obs AS (
  -- Extract all rhythm observations from chartevents
  SELECT
    ce.stay_id,
    ce.charttime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN UNNEST(RHYTHM_ITEMIDS)
    AND ce.charttime IS NOT NULL
    AND ce.value IS NOT NULL
),

labeled AS (
  -- Label each observation as AF or non-AF
  SELECT
    stay_id,
    charttime,
    -- Identify AF (can optionally include flutter)
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]?fib|afib)') AS is_af,
    value_lc
  FROM rhythm_obs
),

-- Remove duplicates at same timestamp
dedup AS (
  SELECT AS VALUE x
  FROM (
    SELECT ARRAY_AGG(l ORDER BY l.charttime LIMIT 1)[OFFSET(0)] AS x
    FROM labeled l
    GROUP BY l.stay_id, l.charttime
  )
),

-- Create segments when rhythm changes
segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    value_lc,
    -- Create new segment ID whenever rhythm changes
    SUM(CASE
      WHEN is_af != LAG(is_af) OVER w OR LAG(is_af) OVER w IS NULL
      THEN 1
      ELSE 0
    END) OVER (PARTITION BY stay_id ORDER BY charttime) AS seg_id
  FROM dedup
  WINDOW w AS (PARTITION BY stay_id ORDER BY charttime)
),

-- Compress into segments
segments AS (
  SELECT
    stay_id,
    seg_id,
    ANY_VALUE(is_af) AS is_af,
    MIN(charttime) AS seg_start,
    LEAD(MIN(charttime)) OVER (PARTITION BY stay_id ORDER BY MIN(charttime)) AS seg_end,
    STRING_AGG(DISTINCT value_lc, '; ' ORDER BY value_lc) AS rhythm_values
  FROM segmented
  GROUP BY stay_id, seg_id
),

-- Extract AF-only episodes
af_episodes AS (
  SELECT
    s.stay_id,
    s.seg_start AS af_start,
    COALESCE(s.seg_end, i.outtime) AS af_end,
    TIMESTAMP_DIFF(COALESCE(s.seg_end, i.outtime), s.seg_start, MINUTE)/60.0 AS af_hours,
    s.rhythm_values,
    -- Flag if this is the first AF episode for this stay
    ROW_NUMBER() OVER (PARTITION BY s.stay_id ORDER BY s.seg_start) AS episode_number
  FROM segments s
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i USING (stay_id)
  WHERE s.is_af = TRUE
)

SELECT
  stay_id,
  af_start,
  af_end,
  af_hours,
  episode_number,
  CASE WHEN episode_number = 1 THEN TRUE ELSE FALSE END AS is_first_episode,
  rhythm_values
FROM af_episodes
WHERE af_hours > 0.0
ORDER BY stay_id, af_start;
