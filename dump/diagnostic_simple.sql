-- SIMPLIFIED DIAGNOSTIC: Shows the key problem in ONE query
-- For stay_id 30000831
-- Run this to see exactly where deduplication goes wrong

WITH rhythm_itemids AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

rhythm_obs AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    ce.storetime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.stay_id = 30000831  -- Focus on problem patient
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
),

labeled AS (
  SELECT
    stay_id,
    charttime,
    storetime,
    value_lc as rhythm_value,
    -- Current regex (the problem)
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]fib|afib)') AS is_af
  FROM rhythm_obs
),

dedup_analysis AS (
  SELECT
    charttime,
    rhythm_value,
    is_af,
    storetime,
    -- Show what dedup does
    ROW_NUMBER() OVER (PARTITION BY stay_id, charttime ORDER BY is_af DESC) as rank,
    COUNT(*) OVER (PARTITION BY stay_id, charttime) as obs_count
  FROM labeled
)

-- THE MONEY QUERY: Shows conflicts and what gets kept/discarded
SELECT
  charttime,
  rhythm_value,
  is_af,
  obs_count AS observations_at_this_time,
  rank AS dedup_rank,
  CASE
    WHEN rank = 1 THEN '✓ KEPT'
    ELSE '✗ DISCARDED'
  END AS dedup_decision,
  CASE
    WHEN obs_count > 1 AND rank = 1 THEN '⚠️ CONFLICT - THIS ONE WINS'
    WHEN obs_count > 1 AND rank > 1 THEN '⚠️ CONFLICT - THROWN AWAY'
    ELSE 'no conflict'
  END AS conflict_status,
  storetime
FROM dedup_analysis
WHERE obs_count > 1  -- ONLY show rows where there's a conflict
ORDER BY charttime, rank;

-- ==============================================================================
-- WHAT TO LOOK FOR:
-- ==============================================================================
-- 1. Rows where obs_count > 1 = Multiple rhythms charted at same time
-- 2. When you see "AF" with rank=1 and "A Flut" with rank=2 at same charttime
--    → This means AF gets KEPT and A Flut gets DISCARDED
--    → The algorithm thinks AF continues, but actually the rhythm changed!
-- 3. This is why Episode 1 extends from 21:48 all the way to 11:00 or later
--    → It's not actually continuous AF, it's just discarding all the non-AF obs
-- ==============================================================================
