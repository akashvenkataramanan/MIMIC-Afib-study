# Step 8: Comprehensive Rhythm Classification

## What This Does

Expands beyond binary AF/non-AF classification to capture **ALL cardiac rhythms** with special focus on **proarrhythmic events** — life-threatening arrhythmias caused by antiarrhythmic drugs.

This enables analysis of:
- ⚠️ **Drug safety**: VT, VF, torsades, heart blocks from antiarrhythmics
- 📊 **All rhythm transitions**: Not just AF episodes, but complete rhythm phenotyping
- 🔬 **Risk factors**: Do low Mg/K predict proarrhythmic events?
- 💊 **Medication effects**: Which drugs cause which side effects?

---

## Quick Start (3 Steps)

### Step 1: Discover What Rhythms Are Documented (Optional but Recommended)

Run this query to see all actual rhythm values in the database:

```bash
# Open BigQuery Console
# Copy and paste: sql_queries/06_discover_all_rhythm_values.sql
```

**Output**: List of rhythm text values with preliminary classification
**Time**: 5-10 minutes
**Cost**: ~$1
**Purpose**: Validate that regex patterns capture real documentation

---

### Step 2: Create Comprehensive Rhythm Segments Table (MAIN QUERY)

This is the **primary deliverable** - creates a table with ALL rhythm segments classified:

```bash
# Open BigQuery Console
# Copy and paste: sql_queries/08_create_rhythm_segments.sql
```

**Output**: New table `rhythm_segments` with ~50,000-200,000 segments
**Time**: 10-15 minutes
**Cost**: ~$1-3
**What you get**:
- Every rhythm segment with start/end times
- Classification into 25+ rhythm categories
- Severity levels (LIFE_THREATENING to NORMAL)
- Proarrhythmic event flags
- Rhythm transitions (what rhythm came next)

---

### Step 3: Verify Table Creation

```sql
-- Basic counts
SELECT
  COUNT(*) as total_segments,
  COUNT(DISTINCT stay_id) as unique_stays,
  SUM(CASE WHEN is_proarrhythmic_event THEN 1 ELSE 0 END) as proarrhythmic_events
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`;
```

**Expected Results**:
- Total segments: 50,000-200,000
- Unique stays: 20,000-40,000
- Proarrhythmic events: 500-2,000 (<1-2%)

---

## What Rhythms Are Captured?

### 🔴 Priority 1: Life-Threatening (Proarrhythmic)
- **Torsades de Pointes** - Polymorphic VT from QT prolongation (Class Ia/III drugs)
- **Ventricular Fibrillation** - Cardiac arrest rhythm
- **Ventricular Tachycardia** - Wide complex tachycardia (Class Ic in structural heart disease)
- **Idioventricular Rhythm** - Escape rhythm suggesting severe conduction disease

### 🟠 Priority 2: Heart Blocks (Conduction Toxicity)
- **3rd Degree / Complete Heart Block** - Complete AV dissociation
- **2nd Degree Heart Block** - Intermittent dropped beats (Mobitz I/II)
- **1st Degree Heart Block** - Prolonged PR interval

### 🟡 Priority 3: Bradycardia (Drug Side Effects)
- **Sinus Bradycardia** - From beta-blockers, CCBs, digoxin, amiodarone
- **Bradycardia** - General slow heart rate

### 🔵 Priority 4: Atrial Arrhythmias (Target Rhythms)
- **Atrial Fibrillation** - Primary arrhythmia being treated
- **Atrial Flutter** - Organized atrial macroreentry
- **Supraventricular Tachycardia** - Narrow complex tachycardia

### 🟢 Priority 5: Normal & Other
- **Sinus Rhythm** - Goal rhythm (treatment success)
- **Sinus Tachycardia** - Physiologic response
- **Junctional Rhythms** - AV node rhythms
- **Paced Rhythms** - From pacemakers

---

## Files Created

| File | Purpose | When to Use |
|------|---------|-------------|
| **sql_queries/06_discover_all_rhythm_values.sql** | Explore actual rhythm text in database | Before creating rhythm_segments (validation) |
| **sql_queries/07_rhythm_classification_schema.sql** | Reference showing classification logic | Documentation / understanding the system |
| **sql_queries/08_create_rhythm_segments.sql** | **MAIN QUERY** - Creates rhythm_segments table | Primary data creation step |
| **rhythm_classifier.py** | Python module for classification | Jupyter notebooks, post-processing |
| **RHYTHM_CLASSIFICATION_GUIDE.md** | Complete documentation (20+ pages) | Understanding classifications, examples, clinical interpretation |

---

## Example Analyses You Can Now Do

### 1. Find All Torsades de Pointes Events

```sql
SELECT
  stay_id,
  segment_start AS event_time,
  duration_hours,
  sample_rhythm_values
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE rhythm_category = 'TORSADES_DE_POINTES'
ORDER BY stay_id, segment_start;
```

### 2. Link Proarrhythmic Events to Antiarrhythmic Drugs

```sql
-- Find VT/VF/Torsades and check what meds patient was on
SELECT
  rs.stay_id,
  rs.segment_start AS event_time,
  rs.rhythm_category,
  med.medication_name,
  TIMESTAMP_DIFF(rs.segment_start, med.admin_time, HOUR) AS hours_since_drug
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments` rs
JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications` med
  ON rs.stay_id = med.stay_id
WHERE rs.is_proarrhythmic_event = TRUE
  AND med.medication_class = 'antiarrhythmic'
  AND rs.segment_start >= med.admin_time
  AND TIMESTAMP_DIFF(rs.segment_start, med.admin_time, HOUR) <= 48
ORDER BY rs.stay_id;
```

### 3. Check Mg/K Levels Before Torsades

```sql
-- Do low electrolytes predict torsades?
WITH torsades_events AS (
  SELECT stay_id, segment_start AS event_time
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
  WHERE rhythm_category = 'TORSADES_DE_POINTES'
)
SELECT
  te.stay_id,
  te.event_time,
  el.magnesium,
  el.potassium,
  CASE WHEN el.magnesium < 1.6 THEN 'LOW' ELSE 'NORMAL' END AS mg_status,
  CASE WHEN el.potassium < 3.5 THEN 'LOW' ELSE 'NORMAL' END AS k_status
FROM torsades_events te
JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs` el
  ON te.stay_id = el.stay_id
WHERE el.lab_time <= te.event_time
  AND TIMESTAMP_DIFF(te.event_time, el.lab_time, HOUR) <= 24  -- Within 24 hours before
ORDER BY te.stay_id;
```

### 4. Rhythm Transitions Leading to Proarrhythmic Events

```sql
-- What rhythm was patient in BEFORE they went into VT?
SELECT
  rhythm_category AS from_rhythm,
  next_rhythm_category AS to_rhythm,
  COUNT(*) as num_transitions,
  COUNT(DISTINCT stay_id) as num_patients
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE transitions_to_vt_vf = TRUE
GROUP BY rhythm_category, next_rhythm_category
ORDER BY num_transitions DESC;
```

---

## Python Usage (In Notebooks)

```python
# Import the classifier
from rhythm_classifier import classify_rhythm, classify_rhythm_df

# Classify a single rhythm
result = classify_rhythm("ventricular tachycardia")
print(result['rhythm_category'])  # 'VENTRICULAR_TACHYCARDIA'
print(result['is_proarrhythmic_event'])  # True

# Classify a DataFrame
import pandas as pd
df = pd.read_gbq("SELECT * FROM rhythm_segments LIMIT 1000")
df = classify_rhythm_df(df, rhythm_col='sample_rhythm_values')

# Get only proarrhythmic events
from rhythm_classifier import get_proarrhythmic_events
dangerous_rhythms = get_proarrhythmic_events(df)
print(dangerous_rhythms['rhythm_category'].value_counts())
```

---

## Key Insights From Research

### Antiarrhythmic Drug Proarrhythmic Effects

| Drug Class | Proarrhythmic Risk | Incidence | Risk Factors |
|------------|-------------------|-----------|--------------|
| **Class Ia** (quinidine, procainamide) | Torsades de pointes | 2-8% | Low Mg/K, female, QTc >500ms |
| **Class Ic** (flecainide, propafenone) | VT | ~5% | Structural heart disease, prior MI |
| **Class III** (sotalol, dofetilide) | Torsades de pointes | 2-5% | Low Mg/K, renal dysfunction |
| **Beta-blockers** | Bradycardia, heart block | 2-5% | Combination with CCB/digoxin |
| **CCBs** (diltiazem, verapamil) | Bradycardia, AV block | 1-3% | Combination with beta-blockers |

### Why This Matters for Your Research

Your primary research question: **Do low Mg/K predict AF?**

But now you can also ask:
1. **Do low Mg/K predict TORSADES?** (Critical for drug safety)
2. **Which antiarrhythmics are safest in low Mg/K patients?**
3. **Does electrolyte repletion prevent proarrhythmic events?**
4. **What's the time course from drug → electrolyte change → proarrhythmia?**

These are **high-impact clinical questions** that could influence prescribing practices.

---

## Validation Checklist

After running Query 8 (create rhythm_segments), verify:

- [ ] **Total segments**: 50,000-200,000 ✓
- [ ] **Top rhythm**: SINUS_RHYTHM (40-60%) ✓
- [ ] **AF segments**: 10-20% of total ✓
- [ ] **Proarrhythmic events**: 500-2,000 (<2%) ✓
- [ ] **VT events**: 50-200 (rare but captured) ✓
- [ ] **Torsades events**: 10-50 (very rare) ✓
- [ ] **Duration >0 for all segments**: TRUE ✓
- [ ] **No NULL rhythm_category**: TRUE ✓

---

## Next Steps

1. ✅ **Run Query 8** - Create rhythm_segments table
2. **Verify** - Check counts and distributions look reasonable
3. **Link to existing tables**:
   - Join with `af_episodes` (from Step 1)
   - Join with `electrolyte_labs` (from Step 2)
   - Join with `af_medications` (from Step 3)
4. **Analyze associations**:
   - Low Mg/K → Proarrhythmic events?
   - Specific drugs → Specific side effects?
   - Time course of drug initiation → adverse event?

---

## Troubleshooting

**Issue**: Too many "OTHER_UNCLASSIFIED" rhythms (>10%)
**Fix**: Run Query 6 and examine the actual rhythm text, add new regex patterns

**Issue**: VT/VF seem too rare (<10 events)
**Expected**: This is accurate - true VT/VF is rare in ICU telemetry

**Issue**: Proarrhythmic events seem high (>5% of segments)
**Check**: Sinus bradycardia is common and flagged as proarrhythmic - this may be physiologic in some patients

---

## References

- **RHYTHM_CLASSIFICATION_GUIDE.md** - Complete 20-page documentation
- **sql_queries/07_rhythm_classification_schema.sql** - Full classification logic
- **AHA/ACC/HRS 2017 Guidelines** - Ventricular arrhythmia management
- **Drug-Induced Arrhythmias (AHA 2022)** - Proarrhythmic effects

---

## Questions?

This rhythm classification transforms your study from "AF vs no-AF" to comprehensive rhythm phenotyping with emphasis on **antiarrhythmic drug safety**. This opens up multiple high-impact research directions beyond the original Mg/K-AF association.

For detailed clinical interpretation, medication-specific risks, and example analyses, see **RHYTHM_CLASSIFICATION_GUIDE.md**.
