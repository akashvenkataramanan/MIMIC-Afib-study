-- Query 4: Demographics and Outcomes
-- This query extracts patient demographics and outcome variables

SELECT
  -- Patient identifiers
  p.subject_id,
  ad.hadm_id,
  icu.stay_id,

  -- Demographics
  age.age,
  p.gender,
  p.anchor_age,
  p.anchor_year,

  -- Admission details
  ad.admission_type,
  ad.admission_location,
  ad.insurance,
  ad.race,
  ad.marital_status,
  ad.admittime,
  ad.dischtime,
  ad.deathtime,

  -- ICU details
  icu.intime AS icu_intime,
  icu.outtime AS icu_outtime,
  TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR)/24.0 AS icu_los_days,
  icu.first_careunit,
  icu.last_careunit,

  -- Hospital outcomes
  ad.hospital_expire_flag,
  TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR)/24.0 AS hosp_los_days,

  -- Death information
  p.dod AS date_of_death,
  CASE
    WHEN p.dod IS NOT NULL AND ad.dischtime IS NOT NULL
    THEN TIMESTAMP_DIFF(p.dod, ad.dischtime, DAY)
    ELSE NULL
  END AS days_to_death_after_discharge,

  -- 30-day mortality flag
  CASE
    WHEN p.dod IS NOT NULL AND ad.dischtime IS NOT NULL
      AND TIMESTAMP_DIFF(p.dod, ad.dischtime, DAY) <= 30
    THEN TRUE
    ELSE FALSE
  END AS mortality_30day,

  -- Severity scores
  sofa.sofa_24hours,
  sofa.respiration_24hours,
  sofa.coagulation_24hours,
  sofa.liver_24hours,
  sofa.cardiovascular_24hours,
  sofa.cns_24hours,
  sofa.renal_24hours

FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
  ON p.subject_id = ad.subject_id
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON ad.hadm_id = icu.hadm_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.age` age
  ON p.subject_id = age.subject_id AND ad.hadm_id = age.hadm_id
LEFT JOIN `physionet-data.mimiciv_3_1_derived.first_day_sofa` sofa
  ON icu.stay_id = sofa.stay_id

ORDER BY p.subject_id, ad.hadm_id, icu.stay_id;
