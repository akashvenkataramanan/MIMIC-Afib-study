-- Query 3: Extract Antiarrhythmic and Rate Control Medications
-- This query captures medication administrations from eMAR and ICU drips

-- Medication concept lists (customize as needed)
DECLARE AA_RX ARRAY<STRING> DEFAULT [
  'amiodarone','ibutilide','procainamide','dofetilide','sotalol','flecainide','propafenone'
];
DECLARE RATE_RX ARRAY<STRING> DEFAULT [
  'metoprolol','esmolol','diltiazem','verapamil','digoxin'
];

-- eMAR: Precise barcode-scanned administrations (most reliable 2016+)
WITH emar AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime AS admin_time,
    LOWER(ed.medication) AS med_string,
    ed.dose_given,
    ed.dose_given_unit
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
  WHERE e.charttime IS NOT NULL
),

emar_aa AS (
  SELECT
    subject_id,
    hadm_id,
    admin_time,
    med_string,
    dose_given,
    dose_given_unit,
    'AA' AS drug_class
  FROM emar
  WHERE EXISTS (
    SELECT 1 FROM UNNEST(AA_RX) g
    WHERE med_string LIKE CONCAT('%', g, '%')
  )
),

emar_rate AS (
  SELECT
    subject_id,
    hadm_id,
    admin_time,
    med_string,
    dose_given,
    dose_given_unit,
    'RATE' AS drug_class
  FROM emar
  WHERE EXISTS (
    SELECT 1 FROM UNNEST(RATE_RX) g
    WHERE med_string LIKE CONCAT('%', g, '%')
  )
),

-- ICU drips (continuous infusions)
icu_drips AS (
  SELECT
    ie.subject_id,
    i.hadm_id,
    ie.stay_id,
    ie.starttime,
    ie.endtime,
    LOWER(di.label) AS item_label,
    ie.amount,
    ie.amountuom,
    ie.rate,
    ie.rateuom
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i USING (stay_id)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  WHERE (
    EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
    OR EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
  )
),

-- Union all medication sources
meds_union AS (
  -- eMAR antiarrhythmics (point-in-time)
  SELECT
    subject_id,
    hadm_id,
    NULL AS stay_id,
    admin_time AS t_start,
    admin_time AS t_end,
    med_string AS med_name,
    drug_class,
    CAST(dose_given AS STRING) AS dose,
    dose_given_unit AS dose_unit,
    'eMAR' AS source
  FROM emar_aa

  UNION ALL

  -- eMAR rate control (point-in-time)
  SELECT
    subject_id,
    hadm_id,
    NULL AS stay_id,
    admin_time,
    admin_time,
    med_string,
    drug_class,
    CAST(dose_given AS STRING),
    dose_given_unit,
    'eMAR'
  FROM emar_rate

  UNION ALL

  -- ICU drips (time windows)
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    starttime,
    endtime,
    item_label AS med_name,
    CASE
      WHEN EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE item_label LIKE CONCAT('%', g, '%'))
      THEN 'AA'
      ELSE 'RATE'
    END AS drug_class,
    CONCAT(CAST(rate AS STRING), ' ', rateuom) AS dose,
    'infusion' AS dose_unit,
    'ICU_drip'
  FROM icu_drips
)

SELECT
  subject_id,
  hadm_id,
  stay_id,
  t_start,
  t_end,
  med_name,
  drug_class,
  dose,
  dose_unit,
  source
FROM meds_union
ORDER BY subject_id, hadm_id, t_start;
