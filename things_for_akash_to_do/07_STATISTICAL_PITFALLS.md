# Step 7: Statistical Pitfalls and Important Considerations

Before you publish or draw conclusions, carefully consider these statistical and methodological issues!

---

## Major Pitfall #1: Confounding by Indication

### What Is It?

**Confounding by indication** = Treatment decisions are based on patient severity, which also affects outcomes.

### Example in Your Study

**Scenario:**
- Sicker patients → More likely to have low Mg/K → Get more aggressive repletion → Still have worse outcomes
- Did repletion fail? Or were these patients just sicker to begin with?

**Result**: You might conclude "Mg repletion doesn't help" when actually it does, but sicker patients need it more!

### How to Address

**Option 1: Adjustment**
- Add severity measures to your model (SOFA scores, vasopressor use, mechanical ventilation)
- Multivariate regression

**Option 2: Propensity Score Matching**
- Match treated and untreated patients with similar baseline characteristics
- Compare outcomes in matched pairs

**Option 3: Stratification**
- Stratify by severity
- Compare within severity groups

**Option 4: Sensitivity Analysis**
- Restrict to less severe patients only
- See if effect persists

---

## Major Pitfall #2: Time-Dependent Bias (Immortal Time Bias)

### What Is It?

**Problem**: Timing matters! When treatment is given affects the interpretation.

### Example

**Scenario A (BAD)**:
- AF starts at 2pm
- Mg given at 6pm (4 hours into AF)
- AF ends at 8pm
- **Conclusion**: "Mg given during AF, AF lasted only 2 more hours after Mg"

**But wait!**
- AF was already present for 4 hours before Mg
- Maybe AF was naturally resolving
- Mg might not have helped at all

**Scenario B (BETTER)**:
- Only count Mg given in FIRST hour of AF
- Compare outcomes

### How to Address

**Option 1: Landmark Analysis**
- Define a time point (e.g., 1 hour after AF onset)
- Only include patients who survived to that point
- Classify treatment based on what they got by then

**Option 2: Time-Varying Cox Model**
- Model medication as a time-varying covariate
- Accounts for when treatment was given
- Requires R or SAS

**Option 3: Restrict Analysis**
- Only include medications given within first X hours of AF
- Makes timing more uniform

---

## Major Pitfall #3: Missing Data

### What's Missing?

In MIMIC-IV:
1. **Not all patients have all labs**
   - Some stays have no Mg labs
   - Some have no K labs
   - Some have neither

2. **Lab timing varies**
   - Some get labs every 6 hours
   - Some once daily
   - Some only on admission

3. **Medication data**
   - eMAR incomplete before 2016
   - Some medications only in prescriptions, not eMAR

### Why It Matters

**Missing not at random (MNAR):**
- Sicker patients → More frequent labs
- Healthier patients → Fewer labs
- If you only include patients with labs, you're selecting sicker patients!

### How to Address

**Option 1: Report Missingness**
```sql
SELECT
  COUNT(*) as total_stays,
  COUNT(min_mag_icu) as stays_with_mag,
  ROUND(COUNT(min_mag_icu) / COUNT(*) * 100, 1) as pct_with_mag
FROM analysis_cohort;
```

**Option 2: Sensitivity Analysis**
- Compare patients WITH labs vs WITHOUT labs
- Are they systematically different?

**Option 3: Multiple Imputation**
- Advanced technique to fill in missing values
- Requires specialized software (R: mice, Python: sklearn)
- Be very careful with this!

**Option 4: Complete Case Analysis**
- Only include patients with complete data
- Clearly state this in methods
- Acknowledge limitation

---

## Major Pitfall #4: Multiple Testing

### The Problem

**If you test 20 hypotheses at α = 0.05, you expect 1 false positive by chance!**

In your study, you might test:
1. Mg vs AF (p = 0.03)
2. K vs AF (p = 0.04)
3. Mg+K vs AF (p = 0.02)
4. Mg repletion vs duration (p = 0.045)
5. K repletion vs duration (p = 0.06)
6. Combined repletion vs mortality (p = 0.03)
... and so on

**By test #20, you'll probably find something significant by chance!**

### How to Address

**Option 1: Pre-specify Primary Hypothesis**
- Decide BEFORE looking at data: "Our primary question is X"
- Secondary analyses clearly labeled as exploratory

**Option 2: Bonferroni Correction**
- If testing 10 hypotheses, use α = 0.05/10 = 0.005
- Very conservative

**Option 3: False Discovery Rate (FDR)**
- Benjamini-Hochberg procedure
- Less conservative than Bonferroni
- Controls expected proportion of false positives

**Example in R:**
```r
p_values <- c(0.03, 0.04, 0.02, 0.045, 0.06, 0.03)
p.adjust(p_values, method = "BH")  # Benjamini-Hochberg
```

---

## Major Pitfall #5: Selection Bias

### The Problem

**You're only studying ICU patients who:**
1. Had rhythm charted (not all do)
2. Survived long enough to develop AF
3. Had labs drawn
4. Were admitted to certain ICUs

**This is NOT representative of all AF patients!**

### Examples

**Survivor bias:**
- Patients who die in first 6 hours → No time to develop AF
- You miss early deaths
- Your "AF group" is survivors

**Documentation bias:**
- Some ICUs chart rhythm more than others
- You'll find more AF where documentation is better
- Doesn't mean AF is actually more common there

### How to Address

**Option 1: Clearly Define Population**
- "ICU patients with documented rhythm charting"
- NOT "all ICU patients with AF"

**Option 2: Sensitivity Analysis**
- Compare documented rhythm rates across ICUs
- If very different, be cautious

**Option 3: Acknowledge Limitation**
- In discussion: "Our findings apply to ICU patients with rhythm documentation"

---

## Major Pitfall #6: Reverse Causation

### The Problem

**Which came first?**

**Example:**
- You find: AF patients have low Mg
- **Interpretation A**: Low Mg caused AF ✓
- **Interpretation B**: AF caused low Mg through renal loss, stress response ✗

### How to Address

**Option 1: Temporal Analysis**
- Only look at Mg BEFORE AF onset
- Use `min_mag_before_af` not `min_mag_icu`

**Option 2: Exclude Early AF**
- Exclude AF in first 6-12 hours of ICU
- Ensures labs were drawn first

---

## Major Pitfall #7: Measurement Error

### Sources of Error in MIMIC-IV

**1. Charted rhythm ≠ ECG rhythm**
- Nurses document what they see
- May lag actual rhythm by minutes to hours
- Some AF may be missed

**2. Lab values have variability**
- Point-of-care vs lab
- Different assays
- Hemolysis affects K

**3. Medication timing**
- eMAR = scan time, not infusion time
- Drips may have been running before charting
- Some doses may be charted but not given

### How to Address

**Option 1: Validation Substudy**
- Manually review 50-100 patients
- Check ECGs vs charted rhythm
- Calculate sensitivity/specificity

**Option 2: Use Conservative Definitions**
- Only include clear AF (not "possible AF")
- Only use first AF episode
- Reduce noise

**Option 3: Sensitivity Analysis**
- Try different thresholds (e.g., Mg < 1.5 vs < 1.6)
- See if results are robust

---

## Major Pitfall #8: Overfitting

### The Problem

**Too many variables in your model relative to events**

**Rule of thumb**: Need 10 events (e.g., deaths) per predictor variable

**Example:**
- 500 deaths
- Can include ~50 predictors max
- If you include 100, you're overfitting!

### Signs of Overfitting

- Model fits training data perfectly but fails on new data
- Coefficients are huge or implausible
- Wide confidence intervals

### How to Address

**Option 1: Limit Variables**
- Only include clinically important predictors
- Use domain knowledge

**Option 2: Variable Selection**
- Stepwise regression (use cautiously!)
- LASSO regression (penalized regression)

**Option 3: Cross-Validation**
- Split data: training (70%) and test (30%)
- Build model on training
- Test on held-out data

---

## Statistical Best Practices

### 1. Pre-register Your Hypotheses

**Before looking at data:**
- Write down primary hypothesis
- Write down analysis plan
- Specify primary outcome

**Prevents:**
- P-hacking
- HARKing (Hypothesizing After Results are Known)

---

### 2. Report Effect Sizes, Not Just P-Values

**Bad**: "p < 0.05, significant!"

**Good**: "Mg repletion associated with 2.5 hour reduction in AF duration (95% CI: 1.2-3.8 hours, p=0.003)"

**Includes:**
- Effect size (2.5 hours)
- Confidence interval (precision)
- P-value (statistical significance)

---

### 3. Check Your Assumptions

**For t-tests:**
```sql
-- Export for normality testing
SELECT min_mag_icu
FROM analysis_cohort
WHERE had_af = TRUE AND min_mag_icu IS NOT NULL;
```

**In Python:**
```python
from scipy.stats import shapiro
stat, p = shapiro(df['min_mag_icu'])
print(f'Shapiro-Wilk test: p = {p}')
# If p < 0.05, data is not normal → use Mann-Whitney instead of t-test
```

---

### 4. Use Appropriate Tests

| Scenario | Test |
|----------|------|
| Compare 2 groups, continuous, normal | Independent t-test |
| Compare 2 groups, continuous, non-normal | Mann-Whitney U |
| Compare 2 groups, categorical | Chi-square or Fisher's exact |
| Compare 3+ groups, continuous | ANOVA or Kruskal-Wallis |
| Adjust for confounders, binary outcome | Logistic regression |
| Adjust for confounders, continuous outcome | Linear regression |
| Time-to-event with censoring | Cox proportional hazards |

---

### 5. Report Negative Results

**Don't only report what "worked"!**

If you find:
- Mg repletion doesn't shorten AF (p = 0.42)
- K repletion doesn't reduce mortality (p = 0.63)

**Report it!** Negative results are valuable.

---

## Checklist Before Publishing

- [ ] Primary hypothesis clearly stated
- [ ] Confounders identified and adjusted for
- [ ] Missing data pattern described
- [ ] Sensitivity analyses performed
- [ ] Effect sizes with 95% CIs reported
- [ ] Statistical assumptions checked
- [ ] Multiple testing addressed if applicable
- [ ] Limitations clearly discussed
- [ ] Code and data available (if journal requires)

---

## Recommended Reading

1. **Confounding**: "Causal Inference" by Miguel Hernán and James Robins (free online)
2. **Time-dependent bias**: Suissa S. "Immortal time bias in pharmaco-epidemiology." Am J Epidemiol. 2008
3. **Missing data**: Sterne et al. "Multiple imputation for missing data in epidemiological and clinical research." BMJ. 2009
4. **Multiple testing**: Benjamini & Hochberg. "Controlling the False Discovery Rate." J R Stat Soc B. 1995

---

## Final Advice

### Things to Emphasize in Your Paper

1. **This is observational** - Cannot prove causation, only association
2. **Hypothesis-generating** - Findings need validation in RCT
3. **Large sample** - MIMIC-IV provides good statistical power
4. **Rich temporal data** - Hour-by-hour tracking is strength

### Things to Acknowledge

1. **Unmeasured confounding** - Can't measure everything
2. **Selection bias** - ICU patients with documentation
3. **Generalizability** - Single healthcare system, US only
4. **Missing data** - Not all patients have all labs

### The Golden Rule

**Be honest about limitations!**

Reviewers will find them anyway. Better to acknowledge upfront and discuss how you addressed them.

---

## You're Ready!

You now have:
✅ Complete dataset
✅ Analysis queries
✅ Understanding of major pitfalls
✅ Best practices checklist

**Go forth and do rigorous science!** 🔬📊
