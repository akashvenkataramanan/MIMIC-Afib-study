# Step 5: Create AF Episode Medications Table (Optional but Powerful!)

## What This Does

This table links medications to **specific AF episodes** rather than just ICU stays.

**Why this matters:**
- Step 4 tells you: "Patient had AF and received magnesium during ICU"
- Step 5 tells you: "Patient had AF from 2pm-8pm, received magnesium at 3pm during that episode"

This allows time-based analysis: "Did medication given DURING AF affect that episode's duration?"

---

## When to Use This Table

Use this table if you want to answer:
- Did medications given during AF shorten that episode?
- How quickly were medications given after AF onset?
- Did patients who got meds during AF have better outcomes than those who got meds after?

**If you only care about overall outcomes, you can skip this step and use Table 4 (analysis_cohort).**

---

## SQL Query to Run

**Copy and paste this into BigQuery Console:**

```sql
-- Create table linking medications to specific AF episodes
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications` AS

SELECT
  af.stay_id,
  af.episode_number,
  af.af_start,
  af.af_end,
  af.af_duration_hours,

  -- Medications given DURING this AF episode
  STRING_AGG(DISTINCT CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
    THEN med.med_name
  END) as meds_during_af,

  -- Specific medication flags during AF
  MAX(CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
      AND med.med_class = 'Antiarrhythmic'
    THEN 1 ELSE 0
  END) = 1 as got_antiarrhythmic_during_af,

  MAX(CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
      AND med.med_class = 'Beta Blocker'
    THEN 1 ELSE 0
  END) = 1 as got_bb_during_af,

  MAX(CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
      AND med.med_name LIKE '%magnesium%'
    THEN 1 ELSE 0
  END) = 1 as got_mag_during_af,

  MAX(CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
      AND med.med_name LIKE '%potassium%'
    THEN 1 ELSE 0
  END) = 1 as got_k_during_af,

  -- Time to first medication during AF
  MIN(CASE
    WHEN med.admin_time BETWEEN af.af_start AND af.af_end
    THEN TIMESTAMP_DIFF(med.admin_time, af.af_start, MINUTE)
  END) as minutes_to_first_med

FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes` af
LEFT JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications` med
  ON af.stay_id = med.stay_id

GROUP BY af.stay_id, af.episode_number, af.af_start, af.af_end, af.af_duration_hours
ORDER BY af.stay_id, af.episode_number;
```

---

## Verification Queries

### Check 1: Basic summary

```sql
-- Overall summary
SELECT
  COUNT(*) as total_af_episodes,
  COUNTIF(got_mag_during_af) as episodes_with_mag,
  COUNTIF(got_k_during_af) as episodes_with_k,
  COUNTIF(got_antiarrhythmic_during_af) as episodes_with_aa,
  ROUND(AVG(minutes_to_first_med), 1) as mean_minutes_to_first_med
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
WHERE minutes_to_first_med IS NOT NULL;
```

**Expected**:
- 10-30% of episodes get magnesium during AF
- 5-15% get antiarrhythmics
- Mean time to first med: 60-180 minutes

---

### Check 2: Duration by medication

```sql
-- Compare AF duration by whether meds were given during episode
SELECT
  got_mag_during_af,
  COUNT(*) as num_episodes,
  ROUND(AVG(af_duration_hours), 1) as mean_duration_hours,
  ROUND(STDDEV(af_duration_hours), 1) as sd_duration,
  ROUND(PERCENTILE_CONT(af_duration_hours, 0.5) OVER(PARTITION BY got_mag_during_af), 1) as median_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
GROUP BY got_mag_during_af;
```

**This is a key analysis!**

---

### Check 3: Sample episodes

```sql
-- Look at first 20 episodes that received medications
SELECT
  stay_id,
  episode_number,
  af_duration_hours,
  meds_during_af,
  got_mag_during_af,
  got_k_during_af,
  minutes_to_first_med
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
WHERE meds_during_af IS NOT NULL
LIMIT 20;
```

---

### Check 4: Time to medication analysis

```sql
-- Distribution of time to first medication
SELECT
  CASE
    WHEN minutes_to_first_med < 30 THEN '<30 min'
    WHEN minutes_to_first_med < 60 THEN '30-60 min'
    WHEN minutes_to_first_med < 120 THEN '1-2 hours'
    WHEN minutes_to_first_med < 360 THEN '2-6 hours'
    ELSE '>6 hours'
  END as time_category,
  COUNT(*) as num_episodes,
  ROUND(AVG(af_duration_hours), 1) as mean_af_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
WHERE minutes_to_first_med IS NOT NULL
GROUP BY time_category
ORDER BY MIN(minutes_to_first_med);
```

**Hypothesis**: Earlier treatment → shorter AF duration?

---

## Understanding the Output

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `stay_id` | INTEGER | ICU stay identifier |
| `episode_number` | INTEGER | Episode number (1 = first, 2 = second, etc.) |
| `af_start` | TIMESTAMP | When AF episode started |
| `af_end` | TIMESTAMP | When AF episode ended |
| `af_duration_hours` | FLOAT | Duration in hours |
| `meds_during_af` | STRING | Comma-separated list of meds given during episode |
| `got_antiarrhythmic_during_af` | BOOLEAN | Got AA during this episode? |
| `got_bb_during_af` | BOOLEAN | Got beta blocker? |
| `got_mag_during_af` | BOOLEAN | Got magnesium? |
| `got_k_during_af` | BOOLEAN | Got potassium? |
| `minutes_to_first_med` | INTEGER | Minutes from AF start to first med |

### Example Data

| stay_id | episode_number | af_duration_hours | got_mag_during_af | minutes_to_first_med |
|---------|----------------|-------------------|-------------------|----------------------|
| 30000102 | 1 | 8.0 | TRUE | 120 |
| 30000102 | 2 | 4.0 | FALSE | NULL |
| 30000345 | 1 | 24.5 | TRUE | 30 |

**Interpretation**:
- Patient 30000102, episode 1: Got mag 2 hours after AF started, AF lasted 8 hours total
- Patient 30000102, episode 2: No meds during AF, AF lasted 4 hours
- Patient 30000345: Got mag quickly (30 min), but AF still lasted 24 hours

---

## Key Analyses This Enables

### Analysis 1: Does magnesium shorten AF?

```sql
-- Compare duration: Mag during AF vs no Mag
SELECT
  got_mag_during_af,
  COUNT(*) as n,
  ROUND(AVG(af_duration_hours), 1) as mean_hours,
  ROUND(PERCENTILE_CONT(af_duration_hours, 0.5) OVER(PARTITION BY got_mag_during_af), 1) as median_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
GROUP BY got_mag_during_af;
```

**Statistical test**: Mann-Whitney U test (non-parametric)

---

### Analysis 2: Does timing matter?

```sql
-- Early vs late medication
SELECT
  CASE
    WHEN minutes_to_first_med < 60 THEN 'Early (<1h)'
    WHEN minutes_to_first_med < 240 THEN 'Moderate (1-4h)'
    ELSE 'Late (>4h)'
  END as treatment_timing,
  COUNT(*) as n,
  ROUND(AVG(af_duration_hours), 1) as mean_af_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
WHERE minutes_to_first_med IS NOT NULL
  AND got_mag_during_af = TRUE
GROUP BY treatment_timing
ORDER BY MIN(minutes_to_first_med);
```

**Hypothesis**: Earlier treatment → shorter episodes?

---

### Analysis 3: Multiple medications

```sql
-- Effect of medication combinations
SELECT
  got_mag_during_af,
  got_k_during_af,
  got_antiarrhythmic_during_af,
  COUNT(*) as n,
  ROUND(AVG(af_duration_hours), 1) as mean_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
GROUP BY got_mag_during_af, got_k_during_af, got_antiarrhythmic_during_af
HAVING COUNT(*) >= 10  -- At least 10 episodes
ORDER BY mean_duration;
```

---

## Important Caveats

### 1. Confounding by Indication
**Problem**: Sicker patients get more aggressive treatment AND have longer AF

**Example**:
- Hemodynamically unstable → get amiodarone drip
- Also have severe underlying disease
- AF lasts longer because they're sicker, NOT because amiodarone failed

**Solution**: Need to adjust for severity (would need SOFA scores, vasopressors, etc.)

---

### 2. Time-Dependent Bias
**Problem**: Medications given "during AF" might have been given because AF was already resolving

**Example**:
- AF starts at 2pm
- At 6pm, nurse notes "AF improving, give PO metoprolol"
- AF ends at 8pm
- Did metoprolol help? Or was AF already ending?

**Solution**: Look at timing very carefully. Consider only meds given in first hour of AF.

---

### 3. Censoring
**Problem**: Some AF episodes end at ICU discharge (right-censored)

**Example**:
- Patient in AF at ICU discharge
- We don't know true AF duration
- `af_end` = ICU outtime, but AF may have continued

**Solution**: Sensitivity analysis excluding censored episodes

---

## Advanced Analysis: Survival Analysis

For more sophisticated analysis, you could do:

**Kaplan-Meier survival curves:**
- "Survival" = remaining in AF
- "Event" = conversion to sinus rhythm
- Compare curves: Mag given vs not given

**Cox proportional hazards:**
- Adjust for confounders
- Medication as time-varying covariate

(This requires exporting to R/Python)

---

## Troubleshooting

### Issue: Most `meds_during_af` are NULL
**Solution**: This is expected! Many AF episodes don't get meds during the episode. Medications may have been given before AF or after.

### Issue: `minutes_to_first_med` has many NULLs
**Solution**: NULL means no meds during that episode. This is normal.

### Issue: Very short `minutes_to_first_med` (like 2 minutes)
**Solution**: Could be:
1. Medication was already running (drip started before AF)
2. Very responsive treatment
3. Data artifact

Check `meds_during_af` to see what was given.

---

## Cost Estimate

**BigQuery cost**: ~$0.05-0.10 (uses your smaller tables)

---

## Next Step

✅ Once verified (or if you skipped this), proceed to:

**06_ANALYSIS_QUERIES.md** - Run statistical analyses!
