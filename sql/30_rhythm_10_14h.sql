-- Rhythm classification in 10–14h after cardioversion (12h ± 2h)
-- Flags: AF/AFlutter, Sinus, Other (everything not AF/AFlutter or Sinus)
-- Creates one row per cardioversion with naive & censored variants + completeness and categories.
-- Input:  {{PROJECT}}.{{DATASET}}.cv_for_afib
-- Output: {{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h
-- Sources:
--   - physionet-data.mimiciv_3_1_icu.chartevents (itemid 220048)
--   - physionet-data.mimiciv_3_1_icu.icustays

CREATE OR REPLACE TABLE `{{PROJECT}}.{{DATASET}}.cv_for_afib_rhythm_10_14h` AS
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
  FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib` c
),

-- ICU in/out
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

