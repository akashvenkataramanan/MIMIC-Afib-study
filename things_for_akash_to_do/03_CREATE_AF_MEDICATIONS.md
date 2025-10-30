# Step 3: Create AF Medications Table

## What This Does

This query finds all medications used for AF management and electrolyte repletion, including:
- Antiarrhythmics (amiodarone, etc.)
- Rate control agents (beta blockers, calcium channel blockers, digoxin)
- Electrolyte replacement (magnesium sulfate, potassium chloride)

Data comes from **two sources**:
1. **eMAR** - Barcode-scanned medication administration (most precise)
2. **inputevents** - IV drips and continuous infusions

---

## Why This Matters

To answer: "Did medications help?"

You need to know:
- What medications were given?
- When were they given (during AF? before? after?)
- Did the patient receive electrolyte repletion?
- Did they receive rate control or rhythm control?

---

## Medication Classes Included

### 1. Antiarrhythmics
- Amiodarone
- Diltiazem (also rate control)

### 2. Rate Control
- Beta blockers: metoprolol, esmolol, propranolol
- Calcium channel blockers: diltiazem, verapamil
- Digoxin

### 3. Electrolyte Repletion
- Magnesium sulfate
- Potassium chloride

---

## SQL Query to Run

**Copy and paste this into BigQuery Console:**

```sql
-- Create table with all AF-related medications
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications` AS

-- Define medication lists
WITH med_definitions AS (
  SELECT 'amiodarone' as med_name, 'Antiarrhythmic' as med_class UNION ALL
  SELECT 'diltiazem', 'Calcium Channel Blocker' UNION ALL
  SELECT 'metoprolol', 'Beta Blocker' UNION ALL
  SELECT 'esmolol', 'Beta Blocker' UNION ALL
  SELECT 'digoxin', 'Cardiac Glycoside' UNION ALL
  SELECT 'propranolol', 'Beta Blocker' UNION ALL
  SELECT 'verapamil', 'Calcium Channel Blocker' UNION ALL
  SELECT 'magnesium sulfate', 'Electrolyte' UNION ALL
  SELECT 'magnesium', 'Electrolyte' UNION ALL
  SELECT 'potassium chloride', 'Electrolyte' UNION ALL
  SELECT 'potassium', 'Electrolyte'
),

-- Get medications from eMAR (barcode scans - most precise)
emar_meds AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime as admin_time,
    LOWER(ed.medication) as medication,
    ed.dose_given,
    ed.dose_given_unit,
    'eMAR' as source
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
  WHERE e.charttime IS NOT NULL
),

-- Get IV drips from inputevents
iv_drips AS (
  SELECT
    ie.subject_id,
    icu.hadm_id,
    ie.stay_id,
    ie.starttime as admin_time,
    ie.endtime as end_time,
    LOWER(di.label) as medication,
    ie.amount,
    ie.amountuom as dose_given_unit,
    'IV_Drip' as source
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ie.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime IS NOT NULL
),

-- Match eMAR to medications
emar_matched AS (
  SELECT
    em.subject_id,
    em.hadm_id,
    em.admin_time,
    em.admin_time as end_time,  -- Point in time for eMAR
    md.med_name,
    md.med_class,
    em.medication as med_full_name,
    CAST(em.dose_given AS STRING) as dose,
    em.dose_given_unit,
    em.source
  FROM emar_meds em
  CROSS JOIN med_definitions md
  WHERE em.medication LIKE CONCAT('%', md.med_name, '%')
),

-- Match IV drips to medications
iv_matched AS (
  SELECT
    iv.subject_id,
    iv.hadm_id,
    iv.admin_time,
    iv.end_time,
    md.med_name,
    md.med_class,
    iv.medication as med_full_name,
    CAST(iv.amount AS STRING) as dose,
    iv.dose_given_unit,
    iv.source
  FROM iv_drips iv
  CROSS JOIN med_definitions md
  WHERE iv.medication LIKE CONCAT('%', md.med_name, '%')
),

-- Combine all medications
all_meds AS (
  SELECT * FROM emar_matched
  UNION ALL
  SELECT * FROM iv_matched
)

-- Link to ICU stays
SELECT
  icu.stay_id,
  am.subject_id,
  am.hadm_id,
  am.admin_time,
  am.end_time,
  TIMESTAMP_DIFF(am.admin_time, icu.intime, HOUR) as hours_from_icu_admit,
  am.med_name,
  am.med_class,
  am.med_full_name,
  am.dose,
  am.dose_given_unit,
  am.source
FROM all_meds am
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON am.hadm_id = icu.hadm_id
WHERE am.admin_time BETWEEN icu.intime AND icu.outtime
ORDER BY icu.stay_id, am.admin_time;
```

---

## Verification Queries

### Check 1: Medication summary

```sql
-- What medications did we find?
SELECT
  med_class,
  med_name,
  COUNT(*) as num_administrations,
  COUNT(DISTINCT stay_id) as num_icu_stays
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
GROUP BY med_class, med_name
ORDER BY med_class, num_administrations DESC;
```

**Expected**:
- Metoprolol: Most common beta blocker
- Magnesium/Potassium: Very common (electrolyte repletion)
- Amiodarone: Less common but significant

---

### Check 2: eMAR vs IV Drips

```sql
-- Compare sources
SELECT
  source,
  med_class,
  COUNT(*) as num_administrations
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
GROUP BY source, med_class
ORDER BY source, num_administrations DESC;
```

**What to look for**:
- eMAR: Mostly pills/boluses (metoprolol, digoxin, oral K)
- IV_Drip: Mostly infusions (amiodarone drip, esmolol drip, IV Mg)

---

### Check 3: Sample medications

```sql
-- Look at first 20 administrations
SELECT
  stay_id,
  admin_time,
  hours_from_icu_admit,
  med_class,
  med_name,
  dose,
  dose_given_unit,
  source
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
ORDER BY stay_id, admin_time
LIMIT 20;
```

---

### Check 4: Medications per patient

```sql
-- How many ICU stays received each medication class?
SELECT
  med_class,
  COUNT(DISTINCT stay_id) as num_icu_stays,
  ROUND(COUNT(DISTINCT stay_id) / (
    SELECT COUNT(DISTINCT stay_id)
    FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
  ) * 100, 1) as pct_of_patients
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications`
GROUP BY med_class
ORDER BY num_icu_stays DESC;
```

**Expected**:
- Electrolytes: 60-90% (very common)
- Beta blockers: 40-70%
- Antiarrhythmics: 10-30%

---

## Understanding the Output

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `stay_id` | INTEGER | ICU stay identifier |
| `subject_id` | INTEGER | Patient identifier |
| `hadm_id` | INTEGER | Hospital admission identifier |
| `admin_time` | TIMESTAMP | When medication was given |
| `end_time` | TIMESTAMP | When infusion ended (same as admin_time for bolus) |
| `hours_from_icu_admit` | INTEGER | Hours since ICU admission |
| `med_name` | STRING | Standardized medication name |
| `med_class` | STRING | Medication class |
| `med_full_name` | STRING | Full medication name from MIMIC |
| `dose` | STRING | Dose given (varies by med) |
| `dose_given_unit` | STRING | Unit of dose |
| `source` | STRING | "eMAR" or "IV_Drip" |

### Example Data

| stay_id | admin_time | med_name | med_class | dose | source |
|---------|------------|----------|-----------|------|--------|
| 30000102 | 2020-01-15 08:00 | metoprolol | Beta Blocker | 25 | eMAR |
| 30000102 | 2020-01-15 10:00 | magnesium sulfate | Electrolyte | 2 | eMAR |
| 30000102 | 2020-01-15 14:00 | amiodarone | Antiarrhythmic | 150 | IV_Drip |

**Interpretation**:
- Patient got metoprolol (oral/IV) at 8am
- Then magnesium repletion at 10am
- Then amiodarone drip started at 2pm

---

## Key Insights This Table Enables

With this table you can answer:

1. **What % of patients get electrolyte repletion?**
   - Count distinct stay_ids with magnesium or potassium

2. **When are meds given relative to AF?**
   - Join to `af_episodes`
   - Compare `admin_time` to `af_start`

3. **Do patients get multiple medication classes?**
   - Group by stay_id
   - Count distinct med_classes

4. **What's the time to first medication?**
   - Use MIN(admin_time) per stay_id
   - Compare to AF onset

---

## Important Notes

### eMAR Caveat
- eMAR is most reliable from **2016 onward**
- Before 2016, coverage is spotty
- For older data, rely more on inputevents

### Medication Matching
- Uses LIKE matching (fuzzy)
- "magnesium" will catch "Magnesium Sulfate", "Mag Oxide", etc.
- Check `med_full_name` to see exactly what was caught

### Drip Duration
- `end_time` tells you when drip stopped
- Can calculate drip duration: `TIMESTAMP_DIFF(end_time, admin_time, HOUR)`

### Multiple Doses
- Same medication given multiple times = multiple rows
- This is correct! Each administration is one row

---

## Adding More Medications

To add more medications, edit the `med_definitions` CTE:

```sql
WITH med_definitions AS (
  SELECT 'amiodarone' as med_name, 'Antiarrhythmic' as med_class UNION ALL
  SELECT 'diltiazem', 'Calcium Channel Blocker' UNION ALL
  -- ADD YOUR MEDICATIONS HERE:
  SELECT 'flecainide', 'Antiarrhythmic' UNION ALL
  SELECT 'sotalol', 'Antiarrhythmic' UNION ALL
  ...
),
```

---

## Troubleshooting

### Issue: Few medications found
**Solution**:
1. Check your medication names are correct
2. Try searching d_items or emar_detail for variations:
```sql
SELECT DISTINCT medication
FROM `physionet-data.mimiciv_3_1_hosp.emar_detail`
WHERE LOWER(medication) LIKE '%amiodarone%'
LIMIT 20;
```

### Issue: Duplicate rows
**Solution**: This is expected! Each administration is one row. If you want unique medications per patient, use DISTINCT or GROUP BY in your analysis.

### Issue: End_time is NULL
**Solution**: For eMAR, end_time = admin_time (point in time). For drips, some may not have recorded end times.

---

## Cost Estimate

**BigQuery cost**: ~$0.50-1.50

---

## Next Step

✅ Once verified, proceed to:

**04_CREATE_ANALYSIS_COHORT.md**
