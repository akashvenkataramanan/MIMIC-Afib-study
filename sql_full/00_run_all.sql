-- Runs all steps to produce analysis-ready tables using your default
-- project and dataset: tactical-grid-454202-h6.mimic_af_electrolytes
--
-- This script is safe to paste into BigQuery Console and run as a single job.
-- It creates/overwrites the following tables:
--   - admitted_with_af_or_aflutter
--   - af_episodes
--   - af_or_aflutter_episodes
--   - cv_for_afib                (deduplicated in place)
--   - cv_for_afib_labs24
--   - cv_for_afib_rhythm_10_14h
--   - cv_for_afib_labs24_rhythm_10_14h
--   - kmg_rhythm10_14h_naive_counts
--   - kmg_rhythm10_14h_naive_pct
--   - kmg_rhythm10_14h_censored_counts
--   - kmg_rhythm10_14h_censored_pct

-- ---------------------------------------------------------------------
-- Step 0: Build AF episodes table from rhythm observations (CHARTEVENTS)
-- Output: af_episodes
-- Why: Creates contiguous AF segments (start/end/duration) per ICU stay.
-- Notes:
--   - This follows your initial approach but fixes the segment end logic.
--   - Earlier COALESCE(LEAD(next segment start), ICU outtime) mis-labeled
--     segments. We now use each AF segment's own segment_end and clip to
--     ICU outtime.
--   - We intentionally keep regex matching for AF to capture variations
--     like "a-fib", "afib", etc.
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes` AS
WITH
-- 0. Identify itemids for rhythm in ICU CHARTEVENTS (future-proof)
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- 1. Pull rhythm observations with non-null values/times; lowercase text
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

-- 2. Tag each observation as AF vs not-AF using a regex
labeled AS (
  SELECT
    stay_id,
    chart_dt,
    REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
    value_lc AS rhythm_value
  FROM rhythm_obs
),

-- 3. Deduplicate any repeated entries at identical time within a stay
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

-- 4. Compute segment breaks when AF/non-AF switches
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

-- 5. Collapse to segments with start/end and AF indicator
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

-- 6. AF-only segments, clipped to ICU outtime
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

-- 7. Final AF episode rows with duration and sequence number
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

-- ---------------------------------------------------------------------
-- Step 0a: Identify ICU stays admitted with AF or Atrial Flutter
-- Output: admitted_with_af_or_aflutter
-- No segmentation; just the first documented rhythm within 2h of ICU intime.
DECLARE ADMISSION_WINDOW_MIN INT64 DEFAULT 120;  -- minutes after ICU intime

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.admitted_with_af_or_aflutter` AS
WITH
icu AS (
  SELECT subject_id, hadm_id, stay_id,
         CAST(intime AS DATETIME) AS icu_intime,
         CAST(outtime AS DATETIME) AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),
rhythm_obs AS (
  SELECT ce.subject_id, ce.hadm_id, ce.stay_id,
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
classified AS (
  SELECT r.*,
         REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
         REGEXP_CONTAINS(value_lc, r"(atrial.?flut|a[- ]?flut)") AS is_aflutter
  FROM rhythm_obs r
),
first_rhythm AS (
  SELECT c.subject_id, c.hadm_id, c.stay_id,
         c.chart_dt AS first_chart_dt,
         c.value_lc AS first_value_lc,
         c.is_af AS first_is_af,
         c.is_aflutter AS first_is_aflutter
  FROM classified c
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.chart_dt) = 1
)
SELECT i.subject_id, i.hadm_id, i.stay_id,
       i.icu_intime, i.icu_outtime,
       f.first_chart_dt AS first_rhythm_time,
       f.first_value_lc AS first_rhythm_value_lc,
       f.first_is_af AS first_is_af,
       f.first_is_aflutter AS first_is_aflutter,
       (COALESCE(f.first_is_af, FALSE) OR COALESCE(f.first_is_aflutter, FALSE)) AS admitted_with_af_or_aflutter
FROM icu i
LEFT JOIN first_rhythm f USING (subject_id, hadm_id, stay_id)
ORDER BY i.stay_id;

-- ---------------------------------------------------------------------
-- Step 0b: Build AF OR Atrial Flutter episodes from rhythm observations
-- Output: af_or_aflutter_episodes
-- Purpose: Align episode extraction with downstream logic that groups AF
--          and Atrial Flutter together. Segments represent contiguous
--          periods with either AF or Flutter charted.
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_or_aflutter_episodes` AS
WITH
rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),
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
labeled AS (
  SELECT
    stay_id,
    chart_dt,
    REGEXP_CONTAINS(value_lc, r"(atrial.?fibrillation|a[- ]?fib|afib)") AS is_af,
    REGEXP_CONTAINS(value_lc, r"(atrial.?flut|a[- ]?flut)") AS is_aflutter,
    value_lc AS rhythm_value
  FROM rhythm_obs
),
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

-- ---------------------------------------------------------------------
-- Step 1: Deduplicate the cardioversion cohort table in place
-- Reason: prior notes show a few exact duplicate rows in cv_for_afib.
-- Caution: This overwrites the target with DISTINCT rows.
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib` AS
SELECT DISTINCT *
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib`;

-- ---------------------------------------------------------------------
-- Step 2: Most-recent Potassium and Magnesium within 24h BEFORE CV
-- Output: cv_for_afib_labs24
-- Sources: physionet-data.mimiciv_3_1_hosp.labevents
DECLARE LOOKBACK_HOURS INT64 DEFAULT 24;  -- tunable if needed

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

-- Most recent Potassium within LOOKBACK_HOURS before CV
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

-- Most recent Magnesium within LOOKBACK_HOURS before CV
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

-- ---------------------------------------------------------------------
-- Step 3: Rhythm classification in 10–14h after CV (12h ± 2h)
-- Output: cv_for_afib_rhythm_10_14h
-- Sources:
--   - physionet-data.mimiciv_3_1_icu.chartevents (itemid 220048)
--   - physionet-data.mimiciv_3_1_icu.icustays
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_rhythm_10_14h` AS
WITH
-- Exact value lists (stick to known labels)
label_sets AS (
  SELECT
    ['SR (Sinus Rhythm)','ST (Sinus Tachycardia)','SB (Sinus Bradycardia)','SA (Sinus Arrhythmia)'] AS sinus_labels,
    ['AF (Atrial Fibrillation)'] AS af_labels,
    ['A Flut (Atrial Flutter)']  AS aflutter_labels
),

-- Cohort + next CV per stay
cv AS (
  SELECT
    c.*,
    LEAD(c.cv_time) OVER (PARTITION BY c.stay_id ORDER BY c.cv_time) AS next_cv_time
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib` c
),

-- ICU in/out boundaries
icu AS (
  SELECT
    isty.stay_id, isty.subject_id, isty.hadm_id,
    CAST(isty.intime  AS DATETIME) AS icu_intime,
    CAST(isty.outtime AS DATETIME) AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` isty
),

-- Rhythm stream from CHARTEVENTS item 220048
rhythm_ce AS (
  SELECT
    ce.subject_id, ce.hadm_id, ce.stay_id,
    CAST(ce.charttime AS DATETIME) AS chart_dt,
    TRIM(ce.value) AS value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid = 220048
),

-- Tag each row as AF/AFlutter, Sinus, or Other
rhythm_flagged AS (
  SELECT
    r.*,
    CASE WHEN r.value IN UNNEST(s.af_labels) OR r.value IN UNNEST(s.aflutter_labels) THEN TRUE ELSE FALSE END AS is_af_or_aflutter,
    CASE WHEN r.value IN UNNEST(s.sinus_labels) THEN TRUE ELSE FALSE END AS is_sinus,
    CASE WHEN (r.value IS NOT NULL)
              AND NOT (r.value IN UNNEST(s.af_labels)
                       OR r.value IN UNNEST(s.aflutter_labels)
                       OR r.value IN UNNEST(s.sinus_labels))
         THEN TRUE ELSE FALSE END AS is_other
  FROM rhythm_ce r
  CROSS JOIN label_sets s
),

-- Window: 10h to 14h; censored end at min(14h end, ICU out, next CV)
windows AS (
  SELECT
    c.*,
    i.icu_intime, i.icu_outtime,
    DATETIME_ADD(c.cv_time, INTERVAL 10 HOUR) AS win_start_10h,
    DATETIME_ADD(c.cv_time, INTERVAL 14 HOUR) AS win_end_14h,
    (SELECT MIN(dt)
       FROM UNNEST([DATETIME_ADD(c.cv_time, INTERVAL 14 HOUR), i.icu_outtime, c.next_cv_time]) AS dt
       WHERE dt IS NOT NULL) AS observed_end_14h
  FROM cv c
  LEFT JOIN icu i USING (stay_id, subject_id, hadm_id)
),

-- Score presence (naive vs censored) + completeness
scored AS (
  SELECT
    w.*,

    -- Completeness (naive window)
    EXISTS (
      SELECT 1 FROM rhythm_flagged r
      WHERE r.stay_id = w.stay_id
        AND r.chart_dt >= w.win_start_10h
        AND r.chart_dt <  w.win_end_14h
    ) AS has_data_10_14h,

    -- Presence (naive)
    EXISTS (
      SELECT 1 FROM rhythm_flagged r
      WHERE r.stay_id = w.stay_id
        AND r.chart_dt >= w.win_start_10h
        AND r.chart_dt <  w.win_end_14h
        AND r.is_af_or_aflutter
    ) AS any_af_10_14h_naive,
    EXISTS (
      SELECT 1 FROM rhythm_flagged r
      WHERE r.stay_id = w.stay_id
        AND r.chart_dt >= w.win_start_10h
        AND r.chart_dt <  w.win_end_14h
        AND r.is_sinus
    ) AS any_sinus_10_14h_naive,
    EXISTS (
      SELECT 1 FROM rhythm_flagged r
      WHERE r.stay_id = w.stay_id
        AND r.chart_dt >= w.win_start_10h
        AND r.chart_dt <  w.win_end_14h
        AND r.is_other
    ) AS any_other_10_14h_naive,

    -- Censoring guard: if no time, mark as no-time
    (w.observed_end_14h > w.win_start_10h) AS has_time_obs,

    -- Completeness (censored)
    CASE
      WHEN w.observed_end_14h > w.win_start_10h THEN EXISTS (
        SELECT 1 FROM rhythm_flagged r
        WHERE r.stay_id = w.stay_id
          AND r.chart_dt >= w.win_start_10h
          AND r.chart_dt <  w.observed_end_14h
      )
      ELSE FALSE
    END AS has_data_10_14h_censored,

    -- Presence (censored)
    CASE
      WHEN w.observed_end_14h > w.win_start_10h THEN EXISTS (
        SELECT 1 FROM rhythm_flagged r
        WHERE r.stay_id = w.stay_id
          AND r.chart_dt >= w.win_start_10h
          AND r.chart_dt <  w.observed_end_14h
          AND r.is_af_or_aflutter
      )
      ELSE NULL
    END AS any_af_10_14h_censored,

    CASE
      WHEN w.observed_end_14h > w.win_start_10h THEN EXISTS (
        SELECT 1 FROM rhythm_flagged r
        WHERE r.stay_id = w.stay_id
          AND r.chart_dt >= w.win_start_10h
          AND r.chart_dt <  w.observed_end_14h
          AND r.is_sinus
      )
      ELSE NULL
    END AS any_sinus_10_14h_censored,

    CASE
      WHEN w.observed_end_14h > w.win_start_10h THEN EXISTS (
        SELECT 1 FROM rhythm_flagged r
        WHERE r.stay_id = w.stay_id
          AND r.chart_dt >= w.win_start_10h
          AND r.chart_dt <  w.observed_end_14h
          AND r.is_other
      )
      ELSE NULL
    END AS any_other_10_14h_censored
  FROM windows w
)

SELECT
  subject_id, hadm_id, stay_id,
  cv_time, cv_endtime,
  location, locationcategory, ordercategoryname, ordercategorydescription, statusdescription,
  shock_type_label,

  -- Window bounds
  icu_intime, icu_outtime, next_cv_time,
  win_start_10h, win_end_14h, observed_end_14h,
  (observed_end_14h > win_start_10h) AS has_time_obs,

  -- Naive flags (10–14h)
  has_data_10_14h,
  any_af_10_14h_naive,
  any_sinus_10_14h_naive,
  any_other_10_14h_naive,

  -- Simple naive category
  CASE
    WHEN NOT has_data_10_14h THEN 'no_data'
    WHEN any_af_10_14h_naive AND any_sinus_10_14h_naive THEN 'both_af_and_sinus'
    WHEN any_af_10_14h_naive  THEN 'af'
    WHEN any_sinus_10_14h_naive THEN 'sinus'
    WHEN any_other_10_14h_naive THEN 'other'
    ELSE 'none_mapped'
  END AS rhythm_10_14h_naive_category,

  -- Censored flags (clip end at ICU out / next CV / 14h)
  has_data_10_14h_censored,
  any_af_10_14h_censored,
  any_sinus_10_14h_censored,
  any_other_10_14h_censored,

  -- Censored category (with guards)
  CASE
    WHEN NOT (observed_end_14h > win_start_10h) THEN 'no_time'
    WHEN NOT has_data_10_14h_censored           THEN 'no_data'
    WHEN any_af_10_14h_censored  AND any_sinus_10_14h_censored THEN 'both_af_and_sinus'
    WHEN any_af_10_14h_censored  THEN 'af'
    WHEN any_sinus_10_14h_censored THEN 'sinus'
    WHEN any_other_10_14h_censored THEN 'other'
    ELSE 'none_mapped'
  END AS rhythm_10_14h_censored_category

FROM scored
ORDER BY stay_id, cv_time;

-- ---------------------------------------------------------------------
-- Step 4: Join labs-within-24h with rhythm-10_14h
-- Output: cv_for_afib_labs24_rhythm_10_14h
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

-- ---------------------------------------------------------------------
-- Step 5: Association tables — counts and row-wise percents per K/Mg bin
-- These help inspect the distribution of 10–14h rhythm categories across
-- potassium and magnesium bins (both naive and censored interpretations).

-- Naive counts by potassium_bin x magnesium_bin x category
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_naive_counts` AS
SELECT
  potassium_bin,
  magnesium_bin,
  rhythm_10_14h_naive_category AS category,
  COUNT(*) AS n
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- Naive percentages within each K/Mg bin
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_naive_pct` AS
WITH counts AS (
  SELECT
    potassium_bin,
    magnesium_bin,
    rhythm_10_14h_naive_category AS category,
    COUNT(*) AS n
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
  GROUP BY 1, 2, 3
)
SELECT
  potassium_bin,
  magnesium_bin,
  category,
  n,
  SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin) AS denom,
  SAFE_DIVIDE(n, SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin)) AS pct
FROM counts
ORDER BY 1, 2, 3;

-- Censored counts by potassium_bin x magnesium_bin x category
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_censored_counts` AS
SELECT
  potassium_bin,
  magnesium_bin,
  rhythm_10_14h_censored_category AS category,
  COUNT(*) AS n
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;

-- Censored percentages within each K/Mg bin
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.kmg_rhythm10_14h_censored_pct` AS
WITH counts AS (
  SELECT
    potassium_bin,
    magnesium_bin,
    rhythm_10_14h_censored_category AS category,
    COUNT(*) AS n
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_labs24_rhythm_10_14h`
  GROUP BY 1, 2, 3
)
SELECT
  potassium_bin,
  magnesium_bin,
  category,
  n,
  SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin) AS denom,
  SAFE_DIVIDE(n, SUM(n) OVER (PARTITION BY potassium_bin, magnesium_bin)) AS pct
FROM counts
ORDER BY 1, 2, 3;

-- End of build
