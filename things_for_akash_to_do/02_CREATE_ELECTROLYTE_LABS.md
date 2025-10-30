# Step 2: Create Electrolyte Labs Table

## What This Does

This query extracts all magnesium and potassium lab values drawn during ICU stays, including:
- Lab values and units
- Timing relative to ICU admission
- Flags for abnormally low values
- Reference ranges

## Why This Matters

You need to know:
- What were the electrolyte levels BEFORE AF started?
- How low did electrolytes get during the ICU stay?
- Were labs abnormal when AF occurred?

---

## Clinical Context

**Normal Ranges:**
- Magnesium: 1.6-2.6 mEq/L (or 1.7-2.2 mg/dL)
- Potassium: 3.5-5.0 mEq/L

**Low values (hypo-):**
- Magnesium < 1.6 mEq/L
- Potassium < 3.5 mEq/L

Both are arrhythmogenic (can trigger AF)!

---

## SQL Query to Run

**Copy and paste this into BigQuery Console:**

```sql
-- Create table with all Mg and K labs during ICU stays
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs` AS

-- Step 1: Find Mg and K itemids
WITH electrolyte_items AS (
  SELECT
    itemid,
    label,
    CASE
      WHEN LOWER(label) LIKE '%magnesium%' THEN 'Magnesium'
      WHEN LOWER(label) LIKE '%potassium%' AND fluid = 'Blood' THEN 'Potassium'
    END as electrolyte_type
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (LOWER(label) LIKE '%magnesium%' OR LOWER(label) LIKE '%potassium%')
    AND fluid = 'Blood'
),

-- Step 2: Get all electrolyte labs
electrolyte_labs AS (
  SELECT
    lab.subject_id,
    lab.hadm_id,
    lab.charttime as lab_time,
    ei.electrolyte_type,
    lab.valuenum as lab_value,
    lab.valueuom as lab_unit,
    lab.ref_range_lower,
    lab.ref_range_upper,
    -- Flag if abnormally low
    CASE
      WHEN ei.electrolyte_type = 'Magnesium' AND lab.valuenum < 1.6 THEN TRUE
      WHEN ei.electrolyte_type = 'Potassium' AND lab.valuenum < 3.5 THEN TRUE
      ELSE FALSE
    END as is_low
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  JOIN electrolyte_items ei ON lab.itemid = ei.itemid
  WHERE lab.valuenum IS NOT NULL
)

-- Step 3: Link to ICU stays and add timing relative to ICU admission
SELECT
  icu.stay_id,
  el.subject_id,
  el.hadm_id,
  icu.intime as icu_admit_time,
  icu.outtime as icu_discharge_time,
  el.lab_time,
  TIMESTAMP_DIFF(el.lab_time, icu.intime, HOUR) as hours_from_icu_admit,
  el.electrolyte_type,
  el.lab_value,
  el.lab_unit,
  el.is_low,
  -- Flag if this is the first lab of this type
  ROW_NUMBER() OVER (
    PARTITION BY icu.stay_id, el.electrolyte_type
    ORDER BY el.lab_time
  ) = 1 as is_first_lab
FROM electrolyte_labs el
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON el.hadm_id = icu.hadm_id
WHERE el.lab_time BETWEEN icu.intime AND icu.outtime  -- During ICU stay only
ORDER BY icu.stay_id, el.lab_time;
```

---

## Verification Queries

### Check 1: Summary by electrolyte type

```sql
-- Summary statistics
SELECT
  electrolyte_type,
  COUNT(*) as num_labs,
  COUNT(DISTINCT stay_id) as icu_stays,
  ROUND(AVG(lab_value), 2) as mean_value,
  ROUND(MIN(lab_value), 2) as min_value,
  ROUND(MAX(lab_value), 2) as max_value,
  COUNTIF(is_low) as num_low_values,
  ROUND(COUNTIF(is_low) / COUNT(*) * 100, 1) as pct_low
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs`
GROUP BY electrolyte_type;
```

**Expected**:
- Magnesium: mean ~2.0-2.2 mEq/L, 10-30% low values
- Potassium: mean ~4.0-4.2 mEq/L, 20-40% low values

---

### Check 2: Sample labs

```sql
-- Look at first 20 labs
SELECT
  stay_id,
  lab_time,
  hours_from_icu_admit,
  electrolyte_type,
  lab_value,
  lab_unit,
  is_low,
  is_first_lab
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs`
LIMIT 20;
```

**What to look for**:
- `hours_from_icu_admit` should be positive (after ICU admission)
- `lab_value` should be reasonable (Mg: 0.5-5, K: 2-7)
- Some `is_low` should be TRUE

---

### Check 3: Labs per ICU stay

```sql
-- Distribution of labs per patient
SELECT
  electrolyte_type,
  COUNT(*) as num_stays,
  ROUND(AVG(num_labs), 1) as mean_labs_per_stay,
  MAX(num_labs) as max_labs_per_stay
FROM (
  SELECT
    stay_id,
    electrolyte_type,
    COUNT(*) as num_labs
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs`
  GROUP BY stay_id, electrolyte_type
)
GROUP BY electrolyte_type;
```

**Expected**:
- Mean: 3-8 labs per stay (depends on ICU length)
- Some patients may have 20+ labs if long ICU stay

---

### Check 4: Timing distribution

```sql
-- When are labs drawn relative to ICU admission?
SELECT
  CASE
    WHEN hours_from_icu_admit < 0 THEN 'Before ICU (ERROR)'
    WHEN hours_from_icu_admit < 6 THEN '0-6 hours'
    WHEN hours_from_icu_admit < 24 THEN '6-24 hours'
    WHEN hours_from_icu_admit < 48 THEN '24-48 hours'
    ELSE '>48 hours'
  END as timing_category,
  COUNT(*) as num_labs,
  COUNTIF(is_first_lab) as num_first_labs
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs`
GROUP BY timing_category
ORDER BY MIN(hours_from_icu_admit);
```

**What to look for**:
- NO "Before ICU" entries (would indicate error)
- Most first labs in 0-6 hours (admission labs)
- Some labs throughout ICU stay

---

## Understanding the Output

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `stay_id` | INTEGER | ICU stay identifier |
| `subject_id` | INTEGER | Patient identifier |
| `hadm_id` | INTEGER | Hospital admission identifier |
| `icu_admit_time` | TIMESTAMP | ICU admission time |
| `icu_discharge_time` | TIMESTAMP | ICU discharge time |
| `lab_time` | TIMESTAMP | When lab was drawn |
| `hours_from_icu_admit` | INTEGER | Hours since ICU admission |
| `electrolyte_type` | STRING | "Magnesium" or "Potassium" |
| `lab_value` | FLOAT | Lab value |
| `lab_unit` | STRING | Unit of measure |
| `is_low` | BOOLEAN | TRUE if below normal range |
| `is_first_lab` | BOOLEAN | TRUE if first lab of this type during ICU stay |

### Example Data

| stay_id | lab_time | hours_from_icu_admit | electrolyte_type | lab_value | is_low |
|---------|----------|----------------------|------------------|-----------|--------|
| 30000102 | 2020-01-15 08:00 | 2 | Magnesium | 1.4 | TRUE |
| 30000102 | 2020-01-15 08:00 | 2 | Potassium | 3.2 | TRUE |
| 30000102 | 2020-01-16 06:00 | 24 | Magnesium | 2.1 | FALSE |
| 30000102 | 2020-01-16 06:00 | 24 | Potassium | 4.0 | FALSE |

**Interpretation**:
- On admission (2 hours after ICU), both Mg and K were low
- 24 hours later, both normalized (likely after repletion)

---

## Key Insights This Table Enables

With this table you can answer:

1. **What were baseline electrolytes?**
   - Filter: `is_first_lab = TRUE`

2. **What's the lowest value during ICU?**
   - Use `MIN(lab_value)` grouped by `stay_id` and `electrolyte_type`

3. **Did they have low values before AF?**
   - Join to `af_episodes` table
   - Filter: `lab_time < af_start`

4. **How common are low electrolytes in ICU?**
   - Count `is_low = TRUE`

---

## Important Notes

### Multiple labs per day
- Critically ill patients get frequent labs
- Some may have labs every 4-6 hours
- Use timing to understand trajectory

### Units may vary
- Magnesium: mEq/L vs mg/dL (conversion: 1 mEq/L = ~2.4 mg/dL)
- Most MIMIC uses mEq/L, but check `lab_unit` column

### Not all patients have both
- Some only have K checked
- Some only have Mg checked
- Most have both

---

## Troubleshooting

### Issue: Very few labs found
**Solution**: Check that `d_labitems` query found itemids. Try:
```sql
SELECT * FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
WHERE LOWER(label) LIKE '%magnesium%' OR LOWER(label) LIKE '%potassium%';
```

### Issue: Negative `hours_from_icu_admit`
**Solution**: Should be filtered out by `WHERE el.lab_time BETWEEN icu.intime AND icu.outtime`. If you see this, there's a data issue.

### Issue: Implausible lab values (e.g., Mg = 50)
**Solution**: MIMIC has some erroneous values. Consider adding filters:
```sql
AND lab.valuenum BETWEEN 0.3 AND 6.0  -- For Magnesium
AND lab.valuenum BETWEEN 1.5 AND 8.0  -- For Potassium
```

---

## Cost Estimate

**BigQuery cost**: ~$0.50-1.00 (labevents is moderate size)

---

## Next Step

✅ Once verified, proceed to:

**03_CREATE_AF_MEDICATIONS.md**
