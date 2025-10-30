# Step 4: Create Analysis Cohort (Master Table)

## What This Does

This is the **master analysis table** that combines everything into one row per ICU stay:
- AF status and episode details
- Electrolyte values (before AF and during ICU)
- Medication exposures
- Demographics
- Outcomes (mortality, length of stay)

This is the table you'll use for your main statistical analyses!

---

## What Each Row Represents

**One row = One ICU stay**

Each row tells you:
- Did this patient have AF? (yes/no)
- If yes, when and for how long?
- What were their electrolyte levels?
- What medications did they receive?
- Did they survive?
- How long were they in ICU/hospital?

---

## SQL Query to Run

**Copy and paste this into BigQuery Console:**

```sql
-- Create comprehensive analysis cohort
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort` AS

WITH
-- Get ICU stays that had AF
af_stays AS (
  SELECT DISTINCT
    stay_id,
    MIN(af_start) as first_af_time,
    SUM(af_duration_hours) as total_af_hours,
    COUNT(*) as num_af_episodes
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes`
  GROUP BY stay_id
),

-- Get lowest electrolyte values BEFORE first AF
electrolytes_before_af AS (
  SELECT
    el.stay_id,
    MIN(CASE WHEN el.electrolyte_type = 'Magnesium' THEN el.lab_value END) as min_mag_before_af,
    MIN(CASE WHEN el.electrolyte_type = 'Potassium' THEN el.lab_value END) as min_k_before_af,
    -- Flag if any low values before AF
    MAX(CASE WHEN el.electrolyte_type = 'Magnesium' AND el.is_low THEN 1 ELSE 0 END) = 1 as had_low_mag_before_af,
    MAX(CASE WHEN el.electrolyte_type = 'Potassium' AND el.is_low THEN 1 ELSE 0 END) = 1 as had_low_k_before_af
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs` el
  JOIN af_stays af ON el.stay_id = af.stay_id
  WHERE el.lab_time < af.first_af_time  -- Before first AF
  GROUP BY el.stay_id
),

-- Get all electrolyte values during ICU (for non-AF comparison)
all_electrolytes AS (
  SELECT
    stay_id,
    MIN(CASE WHEN electrolyte_type = 'Magnesium' THEN lab_value END) as min_mag_icu,
    MIN(CASE WHEN electrolyte_type = 'Potassium' THEN lab_value END) as min_k_icu,
    MAX(CASE WHEN electrolyte_type = 'Magnesium' AND is_low THEN 1 ELSE 0 END) = 1 as had_low_mag_icu,
    MAX(CASE WHEN electrolyte_type = 'Potassium' AND is_low THEN 1 ELSE 0 END) = 1 as had_low_k_icu
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs`
  GROUP BY stay_id
),

-- Get medication exposures
med_exposures AS (
  SELECT
    stay_id,
    MAX(CASE WHEN med_class = 'Antiarrhythmic' THEN 1 ELSE 0 END) = 1 as received_antiarrhythmic,
    MAX(CASE WHEN med_class = 'Beta Blocker' THEN 1 ELSE 0 END) = 1 as received_beta_blocker,
    MAX(CASE WHEN med_class = 'Calcium Channel Blocker' THEN 1 ELSE 0 END) = 1 as received_ccb,
    MAX(CASE WHEN med_name LIKE '%magnesium%' THEN 1 ELSE 0 END) = 1 as received_mag_repletion,
    MAX(CASE WHEN med_name LIKE '%potassium%' THEN 1 ELSE 0 END) = 1 as received_k_repletion
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
  GROUP BY stay_id
)

-- Combine everything
SELECT
  icu.stay_id,
  icu.subject_id,
  icu.hadm_id,

  -- ICU timing
  icu.intime as icu_admit,
  icu.outtime as icu_discharge,
  TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR) / 24.0 as icu_los_days,
  icu.first_careunit,

  -- AF status
  CASE WHEN af.stay_id IS NOT NULL THEN TRUE ELSE FALSE END as had_af,
  af.first_af_time,
  af.total_af_hours,
  af.num_af_episodes,
  TIMESTAMP_DIFF(af.first_af_time, icu.intime, HOUR) as hours_to_first_af,

  -- Electrolytes before AF (for AF patients)
  eb.min_mag_before_af,
  eb.min_k_before_af,
  eb.had_low_mag_before_af,
  eb.had_low_k_before_af,

  -- Electrolytes during entire ICU stay
  ae.min_mag_icu,
  ae.min_k_icu,
  ae.had_low_mag_icu,
  ae.had_low_k_icu,

  -- Medications
  COALESCE(me.received_antiarrhythmic, FALSE) as received_antiarrhythmic,
  COALESCE(me.received_beta_blocker, FALSE) as received_beta_blocker,
  COALESCE(me.received_ccb, FALSE) as received_ccb,
  COALESCE(me.received_mag_repletion, FALSE) as received_mag_repletion,
  COALESCE(me.received_k_repletion, FALSE) as received_k_repletion,

  -- Demographics
  p.gender,
  CAST(FLOOR(DATE_DIFF(DATE(icu.intime), DATE(p.anchor_year, 1, 1), DAY) / 365.25) + p.anchor_age AS INT64) as age,

  -- Outcomes
  ad.hospital_expire_flag as died_in_hospital,
  TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 as hospital_los_days,
  ad.admission_type,
  ad.race

FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
LEFT JOIN af_stays af ON icu.stay_id = af.stay_id
LEFT JOIN electrolytes_before_af eb ON icu.stay_id = eb.stay_id
LEFT JOIN all_electrolytes ae ON icu.stay_id = ae.stay_id
LEFT JOIN med_exposures me ON icu.stay_id = me.stay_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON icu.hadm_id = ad.hadm_id

ORDER BY icu.stay_id;
```

---

## Verification Queries

### Check 1: Overall summary

```sql
-- High-level summary of the cohort
SELECT
  COUNT(*) as total_icu_stays,
  COUNTIF(had_af) as stays_with_af,
  ROUND(COUNTIF(had_af) / COUNT(*) * 100, 1) as pct_with_af,
  COUNTIF(had_low_mag_icu) as stays_with_low_mag,
  COUNTIF(had_low_k_icu) as stays_with_low_k,
  ROUND(AVG(icu_los_days), 1) as mean_icu_los,
  ROUND(AVG(CASE WHEN died_in_hospital THEN 1.0 ELSE 0.0 END) * 100, 1) as mortality_pct
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`;
```

**Expected**:
- Total ICU stays: 50,000-70,000
- % with AF: 10-20%
- % with low Mg: 20-40%
- % with low K: 30-50%
- Mortality: 10-20%

---

### Check 2: AF vs non-AF comparison

```sql
-- Compare AF vs non-AF patients
SELECT
  had_af,
  COUNT(*) as n,
  ROUND(AVG(age), 1) as mean_age,
  ROUND(AVG(min_mag_icu), 2) as mean_min_mag,
  ROUND(AVG(min_k_icu), 2) as mean_min_k,
  ROUND(AVG(CASE WHEN died_in_hospital THEN 1.0 ELSE 0.0 END) * 100, 1) as mortality_pct,
  ROUND(AVG(icu_los_days), 1) as mean_icu_los
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
GROUP BY had_af;
```

**What to look for**:
- AF patients: Older, lower electrolytes, higher mortality
- This is your first research finding!

---

### Check 3: Sample the data

```sql
-- Look at 10 AF patients and 10 non-AF patients
(
  SELECT *
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
  WHERE had_af = TRUE
  LIMIT 10
)
UNION ALL
(
  SELECT *
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
  WHERE had_af = FALSE
  LIMIT 10
)
ORDER BY had_af DESC, stay_id;
```

---

### Check 4: Medication usage by AF status

```sql
-- Medication usage patterns
SELECT
  had_af,
  COUNTIF(received_mag_repletion) as n_received_mag,
  ROUND(COUNTIF(received_mag_repletion) / COUNT(*) * 100, 1) as pct_mag,
  COUNTIF(received_k_repletion) as n_received_k,
  ROUND(COUNTIF(received_k_repletion) / COUNT(*) * 100, 1) as pct_k,
  COUNTIF(received_antiarrhythmic) as n_received_aa,
  ROUND(COUNTIF(received_antiarrhythmic) / COUNT(*) * 100, 1) as pct_aa
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
GROUP BY had_af;
```

**Expected**:
- AF patients get MORE medications (especially antiarrhythmics)
- Both groups get electrolyte repletion

---

## Understanding the Output

### Key Columns Explained

**Identifiers:**
- `stay_id`, `subject_id`, `hadm_id` - Unique identifiers

**AF Status:**
- `had_af` - Boolean: Did this ICU stay have AF?
- `first_af_time` - When first AF episode started
- `total_af_hours` - Total time in AF during ICU stay
- `num_af_episodes` - Number of separate AF episodes
- `hours_to_first_af` - Time from ICU admission to first AF

**Electrolytes Before AF:**
- `min_mag_before_af` - Lowest Mg before first AF (AF patients only)
- `min_k_before_af` - Lowest K before first AF (AF patients only)
- `had_low_mag_before_af` - Boolean: Low Mg before AF?
- `had_low_k_before_af` - Boolean: Low K before AF?

**Electrolytes During ICU:**
- `min_mag_icu` - Lowest Mg during entire ICU stay
- `min_k_icu` - Lowest K during entire ICU stay
- `had_low_mag_icu` - Boolean: Ever low Mg?
- `had_low_k_icu` - Boolean: Ever low K?

**Medications:**
- `received_antiarrhythmic` - Got amiodarone/similar
- `received_beta_blocker` - Got metoprolol/esmolol/etc
- `received_ccb` - Got diltiazem/verapamil
- `received_mag_repletion` - Got IV/oral magnesium
- `received_k_repletion` - Got IV/oral potassium

**Outcomes:**
- `died_in_hospital` - Boolean
- `icu_los_days` - ICU length of stay
- `hospital_los_days` - Total hospital length of stay

---

## This Table Powers Your Research Questions!

### Question 1: Do low electrolytes predict AF?

```sql
-- Chi-square test setup
SELECT
  had_low_mag_icu,
  COUNTIF(had_af) as with_af,
  COUNTIF(NOT had_af) as without_af
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL
GROUP BY had_low_mag_icu;
```

### Question 2: Does electrolyte repletion help?

```sql
-- AF patients only: repletion vs no repletion
SELECT
  received_mag_repletion,
  COUNT(*) as n,
  ROUND(AVG(total_af_hours), 1) as mean_af_hours,
  ROUND(AVG(CASE WHEN died_in_hospital THEN 1.0 ELSE 0.0 END) * 100, 1) as mortality_pct
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
GROUP BY received_mag_repletion;
```

### Question 3: Combined effects

```sql
-- Low Mg + Repletion combinations
SELECT
  had_low_mag_icu,
  received_mag_repletion,
  COUNT(*) as n,
  ROUND(AVG(total_af_hours), 1) as mean_af_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
GROUP BY had_low_mag_icu, received_mag_repletion
ORDER BY had_low_mag_icu, received_mag_repletion;
```

---

## Important Notes

### NULL Values
- `min_mag_before_af` is NULL if:
  - Patient didn't have AF, OR
  - Patient had AF but no Mg labs before first AF
- This is expected! Not all patients have all labs.

### LEFT JOINs
- Used LEFT JOIN so ALL ICU stays are included
- Even if no AF, no labs, or no medications
- This avoids selection bias

### COALESCE for Medications
- Converts NULL to FALSE for medication flags
- Makes analysis easier (TRUE/FALSE vs TRUE/NULL)

---

## Export for External Analysis

To analyze in Python/R/Excel:

```sql
-- Export the full cohort
SELECT *
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`;
```

Then click "SAVE RESULTS" → "CSV" in BigQuery Console

---

## Troubleshooting

### Issue: Very few rows
**Solution**: Check that previous tables (af_episodes, electrolyte_labs, af_medications) were created successfully.

### Issue: All medication flags are FALSE
**Solution**: Check that af_medications table has data. If empty, revisit Step 3.

### Issue: Age seems wrong
**Solution**: MIMIC anonymizes dates. Age is approximate based on anchor_year. This is normal.

---

## Cost Estimate

**BigQuery cost**: ~$0.10-0.30 (uses already-created tables, minimal scanning)

This is cheap because it queries YOUR tables, not the huge MIMIC tables!

---

## Next Step

✅ Once verified, proceed to:

**05_CREATE_EPISODE_MEDICATIONS.md**

(Or skip to **06_ANALYSIS_QUERIES.md** if you want to start analyzing!)
