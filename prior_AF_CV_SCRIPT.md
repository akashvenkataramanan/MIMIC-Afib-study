
Some helpful codes
ICD codes are generally unhelpful as they only help you find if the procedure was done that day or not More useful was chartevents and procedureevents

itemid for rhythm in the chartevents table = 220048

itemid for cardioversion in procedureevents = 225464

itemid for cardiac arrest in procedureeevents = 225466

This was my initial attempt which faced some problems
there was no way to audit the work being done and whether the segments were being correctly labelled as atrial fibrillation or not.
The segments were not being correctly labeled as atrial fibrillation The problem is with the part which has the COALESCE function which returns the first non null value- basically this was taking the end time of the segment as the start of the next segment with atrial fibrillation

3 cells hidden
Ok so we have a problem here. The atrial fibrillation episodes are split up by other random reports in the chart. For instance, in the first row that shows

Ok so we are going to be running the same thing as a test to see what went wrong and why there is misclassification.
So this attempt fixed it. Changed COALESCE() function to seg.segment_end AS af_end as you will see below. Now the segments are being correctly identified


1 cell hidden
Finding cardioversions for atrial fibrillation

1 cell hidden
Checking how many patients we have
df

[ ]
SELECT
  stay_id,
  MIN(mins_to_nearest_arrest) AS min_mins
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib`
GROUP BY stay_id;
You should have about 207 patients. 2 of these patients had a cardiac arrest within 2 hours of the cardioversion.

we actually have duplicated rows- about 4 of them
Code below will get rid of them

df

[ ]
-- Caution: destructive replace
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib` AS
SELECT DISTINCT *
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib`;

Finding potassium and magnesium levels of patients.
THere are two itemid's for potassium in the d_labitems table 50971 and 52610. Both are from chemistry and from blood. 50960 is the itemid for magnesium , chemistry of blood.

The valueuom is mEq/L for all potassium and mg/dl for all magnesium. THere are no other uom.

df

[ ]
-- Simplest version: hard-code itemids & units you verified
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

-- Most recent K within 24h BEFORE CV
k_candidates AS (
  SELECT
    c.subject_id, c.hadm_id, c.stay_id, c.cv_time,
    le.charttime AS k_time,
    -- K already in mEq/L for these itemids
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

-- Most recent Mg within 24h BEFORE CV
mg_candidates AS (
  SELECT
    c.subject_id, c.hadm_id, c.stay_id, c.cv_time,
    le.charttime AS mg_time,
    -- Mg already in mg/dL for this itemid
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


Our next job is to find the number of patients who were in sinus rhythm right after cardioversion (30-60 minutes) and 2 hours and 12 hours later
df

[ ]
-- Windows you can tune
DECLARE RIGHT_AFTER_FROM_MIN  INT64 DEFAULT 30;   -- 30–60 min window
DECLARE RIGHT_AFTER_TO_MIN    INT64 DEFAULT 60;

DECLARE TWO_H_CENTER_MIN      INT64 DEFAULT 120;  -- 2h ± 45 min
DECLARE TWO_H_HALF_WIDTH_MIN  INT64 DEFAULT 45;

DECLARE TWELVE_H_CENTER_MIN   INT64 DEFAULT 720;  -- 12h ± 90 min
DECLARE TWELVE_H_HALF_WIDTH   INT64 DEFAULT 90;

…
  CASE
    WHEN sinus_win12h AND NOT af_win12h THEN 'sinus'
    WHEN af_win12h    AND NOT sinus_win12h THEN 'af'
    WHEN sinus_win12h AND af_win12h THEN 'both'
    ELSE 'no_data'
  END AS outcome_12h

FROM scored
ORDER BY stay_id, cv_time;

Problem faced
Ok so the i ran the numbers and they dont make any sense. The main results seem to indicate that patients are more commonly in sinus as time goes by following cardioversion which is almost certainly not correct. So we are going to be abandoning this line of inquire and trying something else. Clearly we are not able to depend on the duration of exact proportion of patients in afib at any point in time. so here is what we will do instead. we will try to find percentage of patients who remained completely atrial fibrillation free following cardioversion.

df

[ ]
-- Rhythm classification in 10–14h after cardioversion (12h ± 2h)
-- Flags: AF/AFlutter, Sinus, Other (everything not AF/AFlutter or Sinus)
-- Creates one row per cardioversion with naive & censored variants + completeness and categories.

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_rhythm_10_14h` AS
WITH
-- Exact value lists (stick to your earlier exact matches)
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

df

[ ]
SELECT
  COUNT(*) AS n_cv,
  AVG(CAST(has_data_10_14h AS INT64)) AS p_any_rhythm_10_14h,
  AVG(CAST(any_af_10_14h_naive AS INT64)) AS p_af_10_14h,
  AVG(CAST(any_sinus_10_14h_naive AS INT64)) AS p_sinus_10_14h,
  AVG(CAST(any_other_10_14h_naive AS INT64)) AS p_other_10_14h
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.cv_for_afib_rhythm_10_14h`;

Ok so now we have a more sane output. about half of patients were in sinus and half were in afib. There was some flipping back and forth in about 10 % . and there were some other rhythms mixed in there in about another 10 %


[ ]

Start coding or generate with AI.
Is there an association between potassium and magnesium and membership in afib or sinus groups at 12 hours following cardioversion
df

[ ]

Start coding or generate with AI.
