# Step 6: Statistical Analysis Queries

Now that you have all your tables built, here are the key analyses to run to answer your research questions!

---

## Primary Research Questions

1. **Do low electrolytes predict AF?**
2. **Does electrolyte repletion shorten AF duration?**
3. **Does electrolyte repletion improve outcomes (mortality, LOS)?**

---

## Analysis 1: Do Low Electrolytes Associate with AF?

### 1A: Descriptive Statistics by AF Status

```sql
-- Compare electrolytes between AF and non-AF patients
SELECT
  had_af,
  COUNT(*) as n,

  -- Magnesium
  COUNT(min_mag_icu) as n_with_mag_labs,
  ROUND(AVG(min_mag_icu), 2) as mean_min_mag,
  ROUND(STDDEV(min_mag_icu), 2) as sd_min_mag,
  COUNTIF(had_low_mag_icu) as n_low_mag,
  ROUND(COUNTIF(had_low_mag_icu) / COUNT(*) * 100, 1) as pct_low_mag,

  -- Potassium
  COUNT(min_k_icu) as n_with_k_labs,
  ROUND(AVG(min_k_icu), 2) as mean_min_k,
  ROUND(STDDEV(min_k_icu), 2) as sd_min_k,
  COUNTIF(had_low_k_icu) as n_low_k,
  ROUND(COUNTIF(had_low_k_icu) / COUNT(*) * 100, 1) as pct_low_k

FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL OR min_k_icu IS NOT NULL
GROUP BY had_af;
```

**Expected output:**
| had_af | n | mean_min_mag | pct_low_mag | mean_min_k | pct_low_k |
|--------|---|--------------|-------------|------------|-----------|
| FALSE | 35000 | 2.0 | 25% | 3.9 | 35% |
| TRUE | 8000 | 1.9 | 32% | 3.8 | 42% |

**Interpretation**: If AF patients have lower values and higher % low → supports hypothesis!

---

### 1B: Chi-Square Test Setup for Low Magnesium

```sql
-- 2x2 contingency table: Low Mg vs AF
SELECT
  had_low_mag_icu,
  COUNTIF(had_af) as with_af,
  COUNTIF(NOT had_af) as without_af,
  COUNT(*) as total
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL
GROUP BY had_low_mag_icu;
```

**Export this and run chi-square test in Python/R:**

Python example:
```python
from scipy.stats import chi2_contingency
import pandas as pd

# Your data from BigQuery
data = [[2560, 7440],   # Low Mg: 2560 with AF, 7440 without AF
        [5440, 27560]]  # Normal Mg: 5440 with AF, 27560 without AF

chi2, p_value, dof, expected = chi2_contingency(data)
print(f"Chi-square: {chi2:.2f}, p-value: {p_value:.4f}")
```

---

### 1C: T-Test Setup for Continuous Values

```sql
-- Get mean and SD for t-test (or export for Mann-Whitney U)
SELECT
  had_af,
  AVG(min_mag_icu) as mean_mag,
  STDDEV(min_mag_icu) as sd_mag,
  COUNT(min_mag_icu) as n
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL
GROUP BY had_af;
```

**For non-parametric test (Mann-Whitney U), export full data:**

```sql
-- Export for Mann-Whitney U test
SELECT
  stay_id,
  had_af,
  min_mag_icu,
  min_k_icu
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL OR min_k_icu IS NOT NULL;
```

---

## Analysis 2: Does Electrolyte Repletion Shorten AF Duration?

### 2A: Episode-Level Analysis

```sql
-- Compare AF duration with vs without Mg repletion during episode
SELECT
  got_mag_during_af,
  COUNT(*) as num_episodes,
  ROUND(AVG(af_duration_hours), 1) as mean_duration_hours,
  ROUND(STDDEV(af_duration_hours), 1) as sd_duration,
  ROUND(MIN(af_duration_hours), 1) as min_duration,
  ROUND(PERCENTILE_CONT(af_duration_hours, 0.25) OVER(PARTITION BY got_mag_during_af), 1) as q1,
  ROUND(PERCENTILE_CONT(af_duration_hours, 0.5) OVER(PARTITION BY got_mag_during_af), 1) as median,
  ROUND(PERCENTILE_CONT(af_duration_hours, 0.75) OVER(PARTITION BY got_mag_during_af), 1) as q3,
  ROUND(MAX(af_duration_hours), 1) as max_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episode_medications`
GROUP BY got_mag_during_af;
```

**Statistical test**: Mann-Whitney U (non-parametric) because durations are likely skewed

---

### 2B: Total AF Time Per Stay

```sql
-- Stay-level: Total AF hours with vs without repletion
SELECT
  received_mag_repletion,
  COUNT(*) as n,
  ROUND(AVG(total_af_hours), 1) as mean_total_af_hours,
  ROUND(STDDEV(total_af_hours), 1) as sd,
  ROUND(PERCENTILE_CONT(total_af_hours, 0.5) OVER(PARTITION BY received_mag_repletion), 1) as median
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
GROUP BY received_mag_repletion;
```

---

### 2C: Combined Effect (Low Mg + Repletion)

```sql
-- 2x2 analysis: Low Mg vs Repletion
SELECT
  had_low_mag_icu,
  received_mag_repletion,
  COUNT(*) as n,
  ROUND(AVG(total_af_hours), 1) as mean_af_hours,
  ROUND(AVG(CASE WHEN died_in_hospital THEN 1.0 ELSE 0.0 END) * 100, 1) as mortality_pct
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
  AND min_mag_icu IS NOT NULL
GROUP BY had_low_mag_icu, received_mag_repletion
ORDER BY had_low_mag_icu, received_mag_repletion;
```

**Hypotheses:**
- Low Mg + No repletion → Worst outcomes
- Low Mg + Repletion → Better than no repletion
- Normal Mg → Best outcomes regardless

---

## Analysis 3: Does Repletion Affect Mortality and LOS?

### 3A: Mortality by Medication Exposure (AF Patients Only)

```sql
-- Mortality in AF patients by medication exposure
SELECT
  received_mag_repletion,
  received_k_repletion,
  COUNT(*) as n,

  -- Mortality
  COUNTIF(died_in_hospital) as n_died,
  ROUND(COUNTIF(died_in_hospital) / COUNT(*) * 100, 1) as mortality_pct,

  -- Length of stay
  ROUND(AVG(icu_los_days), 1) as mean_icu_los,
  ROUND(AVG(hospital_los_days), 1) as mean_hosp_los,

  -- AF burden
  ROUND(AVG(total_af_hours), 1) as mean_total_af_hours

FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
GROUP BY received_mag_repletion, received_k_repletion
ORDER BY received_mag_repletion, received_k_repletion;
```

---

### 3B: Logistic Regression Setup

```sql
-- Export data for multivariate logistic regression
-- Outcome: mortality
SELECT
  stay_id,

  -- Outcome
  died_in_hospital,

  -- Primary exposures
  had_low_mag_icu,
  had_low_k_icu,
  received_mag_repletion,
  received_k_repletion,

  -- Confounders
  age,
  gender,
  icu_los_days,
  total_af_hours,
  received_antiarrhythmic,
  received_beta_blocker,

  -- Severity indicators
  CASE WHEN first_careunit IN ('Medical Intensive Care Unit (MICU)',
                                 'Surgical Intensive Care Unit (SICU)')
       THEN first_careunit
       ELSE 'Other'
  END as icu_type

FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
  AND min_mag_icu IS NOT NULL
  AND min_k_icu IS NOT NULL;
```

**In Python/R, run:**
```python
import statsmodels.api as sm
import pandas as pd

# Load exported data
df = pd.read_csv('your_export.csv')

# Prepare variables
X = df[['had_low_mag_icu', 'received_mag_repletion', 'age', 'icu_los_days', ...]]
X = sm.add_constant(X)  # Add intercept
y = df['died_in_hospital']

# Logistic regression
model = sm.Logit(y, X).fit()
print(model.summary())
```

---

## Analysis 4: Stratified Analyses

### 4A: By ICU Type

```sql
-- Does effect differ by ICU type?
SELECT
  first_careunit,
  received_mag_repletion,
  COUNT(*) as n,
  ROUND(AVG(total_af_hours), 1) as mean_af_hours,
  ROUND(COUNTIF(died_in_hospital) / COUNT(*) * 100, 1) as mortality_pct
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
  AND first_careunit IN ('Medical Intensive Care Unit (MICU)',
                         'Surgical Intensive Care Unit (SICU)',
                         'Cardiac Vascular Intensive Care Unit (CVICU)')
GROUP BY first_careunit, received_mag_repletion
HAVING COUNT(*) >= 20
ORDER BY first_careunit, received_mag_repletion;
```

---

### 4B: By Age Groups

```sql
-- Age-stratified analysis
SELECT
  CASE
    WHEN age < 50 THEN '<50'
    WHEN age < 65 THEN '50-64'
    WHEN age < 80 THEN '65-79'
    ELSE '80+'
  END as age_group,
  had_low_mag_icu,
  COUNT(*) as n,
  ROUND(COUNTIF(had_af) / COUNT(*) * 100, 1) as pct_with_af
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL
GROUP BY age_group, had_low_mag_icu
ORDER BY age_group, had_low_mag_icu;
```

---

## Analysis 5: Time-to-Event Analysis

### 5A: Time to First Medication

```sql
-- Distribution of time to medication
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

**Hypothesis**: Earlier medication → Shorter AF?

---

## Analysis 6: Propensity Score Matching Setup

To reduce confounding bias, use propensity score matching:

```sql
-- Export for propensity score analysis
SELECT
  stay_id,

  -- Treatment (what you want to match on)
  received_mag_repletion as treatment,

  -- Outcome
  total_af_hours,
  died_in_hospital,

  -- Covariates for matching
  age,
  CASE WHEN gender = 'M' THEN 1 ELSE 0 END as male,
  had_low_mag_icu,
  had_low_k_icu,
  icu_los_days,
  num_af_episodes,
  received_antiarrhythmic,
  CASE WHEN first_careunit = 'Medical Intensive Care Unit (MICU)' THEN 1 ELSE 0 END as micu

FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE had_af = TRUE
  AND min_mag_icu IS NOT NULL;
```

**In R:**
```r
library(MatchIt)

# Load data
df <- read.csv('your_export.csv')

# Propensity score matching
m.out <- matchit(treatment ~ age + male + had_low_mag_icu + had_low_k_icu +
                 icu_los_days + num_af_episodes,
                 data = df, method = "nearest", ratio = 1)

# Get matched data
matched_data <- match.data(m.out)

# Compare outcomes
t.test(total_af_hours ~ treatment, data = matched_data)
```

---

## Quick Summary Table

Here's a template for your manuscript:

```sql
-- Table 1: Baseline characteristics by AF status
SELECT
  had_af,
  COUNT(*) as n,
  ROUND(AVG(age), 1) as mean_age,
  ROUND(AVG(CASE WHEN gender = 'M' THEN 1.0 ELSE 0.0 END) * 100, 1) as pct_male,
  ROUND(AVG(min_mag_icu), 2) as mean_min_mag,
  ROUND(AVG(min_k_icu), 2) as mean_min_k,
  ROUND(COUNTIF(had_low_mag_icu) / COUNT(*) * 100, 1) as pct_low_mag,
  ROUND(COUNTIF(had_low_k_icu) / COUNT(*) * 100, 1) as pct_low_k,
  ROUND(AVG(icu_los_days), 1) as mean_icu_los,
  ROUND(COUNTIF(died_in_hospital) / COUNT(*) * 100, 1) as mortality_pct
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL OR min_k_icu IS NOT NULL
GROUP BY had_af;
```

---

## Visualization Queries

### For plotting in Python/R:

```sql
-- Scatter plot: Mg vs K by AF status
SELECT
  had_af,
  min_mag_icu,
  min_k_icu,
  died_in_hospital,
  total_af_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.analysis_cohort`
WHERE min_mag_icu IS NOT NULL AND min_k_icu IS NOT NULL
  AND min_mag_icu BETWEEN 0.5 AND 4.0
  AND min_k_icu BETWEEN 2.0 AND 7.0;
```

**Python visualization:**
```python
import matplotlib.pyplot as plt
import seaborn as sns

# Create scatter plot
plt.figure(figsize=(10, 6))
sns.scatterplot(data=df, x='min_mag_icu', y='min_k_icu',
                hue='had_af', style='died_in_hospital', alpha=0.6)
plt.xlabel('Minimum Magnesium (mEq/L)')
plt.ylabel('Minimum Potassium (mEq/L)')
plt.title('Electrolytes by AF Status')
plt.show()
```

---

## Important Statistical Considerations

1. **Multiple comparisons**: If testing many hypotheses, adjust p-values (Bonferroni, FDR)
2. **Effect size**: Report not just p-values, but also effect sizes (Cohen's d, odds ratios)
3. **Confidence intervals**: Always report 95% CIs
4. **Check assumptions**: Normality (Shapiro-Wilk), equal variances, etc.

---

## Next Step

✅ Review **07_STATISTICAL_PITFALLS.md** for important caveats before publishing!
