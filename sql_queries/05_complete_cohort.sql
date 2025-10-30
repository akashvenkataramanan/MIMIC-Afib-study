-- Query 5: Complete AF Cohort with Demographics, Medications, and Outcomes
-- This is the master query that combines AF episodes with all relevant clinical data

-- PARAMETERS: Update these based on rhythm discovery results
DECLARE RHYTHM_ITEMIDS ARRAY<INT64> DEFAULT [220045, 223257];  -- UPDATE THESE!

DECLARE AA_RX ARRAY<STRING> DEFAULT [
  'amiodarone','ibutilide','procainamide','dofetilide','sotalol','flecainide','propafenone'
];

DECLARE RATE_RX ARRAY<STRING> DEFAULT [
  'metoprolol','esmolol','diltiazem','verapamil','digoxin'
];

-- Step 1: Build AF episodes
WITH rhythm_obs AS (
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
  SELECT
    stay_id,
    charttime,
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]?fib|afib)') AS is_af,
    value_lc
  FROM rhythm_obs
),

dedup AS (
  SELECT AS VALUE x
  FROM (
    SELECT ARRAY_AGG(l ORDER BY l.charttime LIMIT 1)[OFFSET(0)] AS x
    FROM labeled l
    GROUP BY l.stay_id, l.charttime
  )
),

segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    SUM(CASE WHEN is_af != LAG(is_af) OVER w OR LAG(is_af) OVER w IS NULL THEN 1 ELSE 0 END)
      OVER (PARTITION BY stay_id ORDER BY charttime) AS seg_id
  FROM dedup
  WINDOW w AS (PARTITION BY stay_id ORDER BY charttime)
),

segments AS (
  SELECT
    stay_id,
    seg_id,
    ANY_VALUE(is_af) AS is_af,
    MIN(charttime) AS seg_start,
    LEAD(MIN(charttime)) OVER (PARTITION BY stay_id ORDER BY MIN(charttime)) AS seg_end
  FROM segmented
  GROUP BY stay_id, seg_id
),

af_episodes AS (
  SELECT
    s.stay_id,
    s.seg_start AS af_start,
    COALESCE(s.seg_end, i.outtime) AS af_end,
    TIMESTAMP_DIFF(COALESCE(s.seg_end, i.outtime), s.seg_start, MINUTE)/60.0 AS af_hours,
    ROW_NUMBER() OVER (PARTITION BY s.stay_id ORDER BY s.seg_start) AS episode_number
  FROM segments s
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i USING (stay_id)
  WHERE s.is_af = TRUE AND TIMESTAMP_DIFF(COALESCE(s.seg_end, i.outtime), s.seg_start, MINUTE)/60.0 > 0
),

-- Step 2: Get medications
emar AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime AS admin_time,
    LOWER(ed.medication) AS med_string,
    CASE
      WHEN EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE LOWER(ed.medication) LIKE CONCAT('%', g, '%'))
      THEN 'AA'
      WHEN EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE LOWER(ed.medication) LIKE CONCAT('%', g, '%'))
      THEN 'RATE'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed ON e.emar_id = ed.emar_id
  WHERE e.charttime IS NOT NULL
    AND (
      EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE LOWER(ed.medication) LIKE CONCAT('%', g, '%'))
      OR EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE LOWER(ed.medication) LIKE CONCAT('%', g, '%'))
    )
),

icu_drips AS (
  SELECT
    ie.subject_id,
    i.hadm_id,
    ie.stay_id,
    ie.starttime AS t_start,
    ie.endtime AS t_end,
    LOWER(di.label) AS item_label,
    CASE
      WHEN EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
      THEN 'AA'
      ELSE 'RATE'
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i USING (stay_id)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE (
    EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
    OR EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
  )
),

-- Step 3: Match medications to AF episodes
af_with_meds AS (
  SELECT
    af.stay_id,
    af.af_start,
    af.af_end,
    af.af_hours,
    af.episode_number,
    -- Flag medications given during this AF episode
    COUNTIF(em.drug_class = 'AA' AND em.admin_time BETWEEN af.af_start AND af.af_end) > 0 AS received_aa_emar,
    COUNTIF(em.drug_class = 'RATE' AND em.admin_time BETWEEN af.af_start AND af.af_end) > 0 AS received_rate_emar,
    COUNTIF(dr.drug_class = 'AA' AND dr.t_start <= af.af_end AND COALESCE(dr.t_end, dr.t_start) >= af.af_start) > 0 AS received_aa_drip,
    COUNTIF(dr.drug_class = 'RATE' AND dr.t_start <= af.af_end AND COALESCE(dr.t_end, dr.t_start) >= af.af_start) > 0 AS received_rate_drip
  FROM af_episodes af
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON af.stay_id = icu.stay_id
  LEFT JOIN emar em ON icu.subject_id = em.subject_id AND icu.hadm_id = em.hadm_id
  LEFT JOIN icu_drips dr ON af.stay_id = dr.stay_id
  GROUP BY af.stay_id, af.af_start, af.af_end, af.af_hours, af.episode_number
),

-- Step 4: Add demographics and outcomes
final_cohort AS (
  SELECT
    -- Identifiers
    p.subject_id,
    ad.hadm_id,
    icu.stay_id,

    -- AF episode details
    afm.af_start,
    afm.af_end,
    afm.af_hours,
    afm.episode_number,
    CASE WHEN afm.episode_number = 1 THEN TRUE ELSE FALSE END AS is_first_episode,

    -- Medications
    afm.received_aa_emar OR afm.received_aa_drip AS received_antiarrhythmic,
    afm.received_rate_emar OR afm.received_rate_drip AS received_rate_control,

    -- Demographics
    age.age,
    p.gender,
    ad.race,
    ad.admission_type,
    ad.admission_location,

    -- ICU details
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime,
    TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR)/24.0 AS icu_los_days,
    icu.first_careunit,

    -- Outcomes
    ad.hospital_expire_flag,
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR)/24.0 AS hosp_los_days,
    CASE
      WHEN p.dod IS NOT NULL AND ad.dischtime IS NOT NULL
        AND TIMESTAMP_DIFF(p.dod, ad.dischtime, DAY) <= 30
      THEN TRUE
      ELSE FALSE
    END AS mortality_30day,

    -- Severity
    sofa.sofa_24hours

  FROM af_with_meds afm
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON afm.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON icu.hadm_id = ad.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ad.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_derived.age` age
    ON p.subject_id = age.subject_id AND ad.hadm_id = age.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_sofa` sofa ON afm.stay_id = sofa.stay_id
)

SELECT * FROM final_cohort
ORDER BY subject_id, hadm_id, stay_id, episode_number;
