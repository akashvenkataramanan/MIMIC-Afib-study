-- COMPREHENSIVE DIAGNOSTIC AUDIT FOR stay_id 30000831
-- One giant table showing EVERY step of the pipeline for each observation
-- Download this as CSV for analysis

WITH rhythm_itemids AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- Step 1: Raw observations
raw_obs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.caregiver_id,
    ce.charttime,
    ce.storetime,
    ce.itemid,
    ce.value AS original_value,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.stay_id = 30000831
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
),

-- Step 2: Apply is_af label
labeled AS (
  SELECT
    *,
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]fib|afib)') AS is_af
  FROM raw_obs
),

-- Step 3: Deduplication analysis
dedup_ranked AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY stay_id, charttime ORDER BY is_af DESC) as dedup_rank,
    COUNT(*) OVER (PARTITION BY stay_id, charttime) as obs_at_charttime
  FROM labeled
),

-- Step 4: Only keep what passes dedup (rn=1)
dedup_kept AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    value_lc
  FROM dedup_ranked
  WHERE dedup_rank = 1
),

-- Step 5: Calculate LAG for segmentation
lagged AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    value_lc,
    LAG(is_af) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_is_af
  FROM dedup_kept
),

-- Step 6: Assign segment_id
segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    value_lc,
    prev_is_af,
    SUM(CASE
      WHEN is_af != prev_is_af OR prev_is_af IS NULL
      THEN 1
      ELSE 0
    END) OVER (PARTITION BY stay_id ORDER BY charttime) AS segment_id
  FROM lagged
),

-- Step 7: Get segment summaries
segment_summary AS (
  SELECT
    stay_id,
    segment_id,
    MIN(charttime) AS segment_start,
    MAX(charttime) AS segment_end,
    ANY_VALUE(is_af) AS segment_is_af,
    COUNT(*) as segment_obs_count
  FROM segmented
  GROUP BY stay_id, segment_id
),

-- Step 8: Get final AF episodes
final_episodes AS (
  SELECT
    seg.stay_id,
    seg.segment_id,
    seg.segment_start AS af_start,
    COALESCE(
      LEAD(seg.segment_start) OVER (PARTITION BY seg.stay_id ORDER BY seg.segment_start),
      icu.outtime
    ) AS af_end,
    ROW_NUMBER() OVER (PARTITION BY seg.stay_id ORDER BY seg.segment_start) AS episode_number
  FROM segment_summary seg
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON seg.stay_id = icu.stay_id
  WHERE seg.segment_is_af = TRUE
)

-- THE BIG TABLE: Everything joined together
SELECT
  -- Raw observation data
  dr.subject_id,
  dr.hadm_id,
  dr.stay_id,
  dr.charttime,
  dr.storetime,
  dr.original_value,
  dr.value_lc,
  dr.caregiver_id,

  -- Step 2: Labeling
  dr.is_af AS labeled_as_af,

  -- Step 3: Deduplication
  dr.dedup_rank,
  dr.obs_at_charttime,
  CASE
    WHEN dr.dedup_rank = 1 THEN 'KEPT'
    ELSE 'DISCARDED'
  END AS dedup_decision,
  CASE
    WHEN dr.obs_at_charttime > 1 THEN 'YES'
    ELSE 'NO'
  END AS has_conflict,

  -- Step 6: Segmentation (only if this obs was kept)
  seg.segment_id,
  seg.prev_is_af,
  CASE
    WHEN seg.is_af != seg.prev_is_af OR seg.prev_is_af IS NULL
    THEN 'NEW_SEGMENT'
    ELSE 'CONTINUES'
  END AS segment_change,

  -- Segment summary
  ss.segment_start,
  ss.segment_end,
  ss.segment_is_af,
  ss.segment_obs_count,
  TIMESTAMP_DIFF(ss.segment_end, ss.segment_start, HOUR) AS segment_duration_hours,

  -- Final episode (only if this segment became an AF episode)
  fe.episode_number,
  fe.af_start AS episode_start,
  fe.af_end AS episode_end,
  TIMESTAMP_DIFF(fe.af_end, fe.af_start, HOUR) AS episode_duration_hours

FROM dedup_ranked dr
LEFT JOIN segmented seg
  ON dr.stay_id = seg.stay_id
  AND dr.charttime = seg.charttime
  AND dr.dedup_rank = 1  -- Only join if this obs was kept
LEFT JOIN segment_summary ss
  ON seg.stay_id = ss.stay_id
  AND seg.segment_id = ss.segment_id
LEFT JOIN final_episodes fe
  ON ss.stay_id = fe.stay_id
  AND ss.segment_id = fe.segment_id

ORDER BY dr.charttime, dr.storetime, dr.dedup_rank;

-- ==============================================================================
-- COLUMN GUIDE
-- ==============================================================================
--
-- Raw Data Columns:
--   charttime: When rhythm was observed
--   storetime: When it was documented in system
--   original_value: The exact rhythm text (e.g., "AF (Atrial Fibrillation)")
--   value_lc: Lowercase version
--
-- Labeling:
--   labeled_as_af: TRUE if regex matched AF, FALSE otherwise
--
-- Deduplication:
--   dedup_rank: 1 = KEPT, 2+ = DISCARDED
--   obs_at_charttime: How many obs at this exact charttime
--   dedup_decision: KEPT or DISCARDED
--   has_conflict: YES if multiple obs at same time
--
-- Segmentation (NULL if observation was DISCARDED):
--   segment_id: Which segment this belongs to
--   prev_is_af: What was the previous observation's is_af value?
--   segment_change: NEW_SEGMENT if rhythm changed, CONTINUES if same
--
-- Segment Summary (NULL if not kept or non-AF segment):
--   segment_start/end: Time boundaries of this segment
--   segment_is_af: Whether this segment is AF
--   segment_obs_count: How many observations in this segment
--
-- Final Episodes (NULL if not an AF segment):
--   episode_number: 1, 2, 3... for this patient
--   episode_start/end: Final episode boundaries
--   episode_duration_hours: How long the episode lasted
--
-- ==============================================================================
-- HOW TO USE THIS DATA
-- ==============================================================================
--
-- 1. Download as CSV from BigQuery
-- 2. Look for rows where:
--    - has_conflict = 'YES' AND dedup_decision = 'DISCARDED'
--    → These are rhythm changes that got thrown away!
--
-- 3. Focus on rows where:
--    - labeled_as_af = FALSE but they're in the middle of an AF episode
--    → This shows the algorithm is wrong
--
-- 4. Check if:
--    - original_value contains "Flut" but labeled_as_af = TRUE
--    → Regex is matching flutter as fibrillation (BUG!)
--
-- ==============================================================================
