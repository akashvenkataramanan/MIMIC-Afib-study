# Comprehensive Cardiac Rhythm Classification Guide

## Overview

This guide documents the comprehensive rhythm classification system for MIMIC-IV bedside telemetry data. Unlike the basic binary AF/non-AF classification, this system classifies all cardiac rhythms with special emphasis on **proarrhythmic events** — life-threatening arrhythmias caused by antiarrhythmic drugs.

## Why This Matters

### The Proarrhythmic Paradox

Antiarrhythmic drugs, while treating atrial fibrillation, can paradoxically cause **worse arrhythmias** than the ones being treated:

- **Class Ia & III drugs** (quinidine, sotalol, dofetilide) → Torsades de pointes (2-5% incidence)
- **Class Ic drugs** (flecainide, propafenone) → Ventricular tachycardia in structural heart disease
- **Rate control drugs** (beta-blockers, CCBs, digoxin) → Severe bradycardia, heart blocks
- **All antiarrhythmics** → Conduction system toxicity

### Clinical Importance

Detecting these events is critical for:
1. **Safety monitoring** of antiarrhythmic therapy
2. **Risk stratification** for patients receiving these medications
3. **Identifying predictors** of proarrhythmic events (e.g., low Mg/K)
4. **Understanding real-world outcomes** of AF treatment strategies

---

## Rhythm Classification Schema

### Classification Hierarchy

The classification follows a **priority hierarchy** where more specific/dangerous rhythms are identified first:

```
1. Life-threatening ventricular arrhythmias (VT, VF, torsades)
2. Heart blocks (1st, 2nd, 3rd degree)
3. Severe bradycardia
4. Atrial fibrillation & flutter (target arrhythmias)
5. Other supraventricular arrhythmias (SVT, AT)
6. Junctional rhythms
7. Normal sinus rhythms
8. Paced rhythms
9. Other clinical events (asystole, PVCs, PACs)
```

---

## Rhythm Categories

### 🔴 Priority 1: Life-Threatening Ventricular Arrhythmias

#### **Torsades de Pointes** (`TORSADES_DE_POINTES`)
- **Definition**: Polymorphic ventricular tachycardia with QT prolongation
- **Appearance**: "Twisting of the points" - QRS axis rotates around baseline
- **Antiarrhythmic causes**:
  - Class Ia: Quinidine, procainamide, disopyramide
  - Class III: Sotalol (2-3%), dofetilide, ibutilide
- **Risk factors**: Low Mg, low K, female sex, baseline QTc >500ms
- **Severity**: `LIFE_THREATENING`
- **Proarrhythmic flag**: `TRUE`

#### **Ventricular Fibrillation** (`VENTRICULAR_FIBRILLATION`)
- **Definition**: Chaotic ventricular electrical activity, no cardiac output
- **Antiarrhythmic causes**: Degeneration from VT or torsades
- **Clinical significance**: Cardiac arrest, requires immediate defibrillation
- **Severity**: `LIFE_THREATENING`
- **Proarrhythmic flag**: `TRUE`

#### **Ventricular Tachycardia** (`VENTRICULAR_TACHYCARDIA`)
- **Definition**: Wide-complex tachycardia (QRS >120ms) at >100 bpm
- **Types**: Monomorphic (uniform QRS) or polymorphic (varying QRS)
- **Antiarrhythmic causes**:
  - Class Ic (flecainide, propafenone) in patients with CAD or structural heart disease
  - Proarrhythmic effect in ~5% of patients with prior MI
- **Severity**: `CRITICAL`
- **Proarrhythmic flag**: `TRUE`

#### **Idioventricular Rhythm** (`IDIOVENTRICULAR`)
- **Definition**: Ventricular escape rhythm (30-40 bpm, wide QRS)
- **Significance**: Indicates severe conduction system disease or drug toxicity
- **Severity**: `CRITICAL`
- **Proarrhythmic flag**: `TRUE`

---

### 🟠 Priority 2: Heart Blocks (Conduction System Toxicity)

#### **Third Degree / Complete Heart Block** (`3RD_DEGREE_BLOCK`)
- **Definition**: Complete AV dissociation - atria and ventricles beat independently
- **Antiarrhythmic causes**:
  - Class Ia drugs (quinidine, procainamide)
  - Class Ic drugs (flecainide, propafenone)
  - Class IV (verapamil, diltiazem)
  - Beta-blockers (especially in combination)
- **Clinical significance**: Can progress to asystole, often requires pacing
- **Severity**: `CRITICAL`
- **Proarrhythmic flag**: `TRUE`

#### **Second Degree Heart Block** (`2ND_DEGREE_BLOCK`)
- **Types**:
  - **Mobitz I (Wenckebach)**: Progressive PR prolongation then dropped QRS
  - **Mobitz II**: Intermittent dropped QRS without PR prolongation (more dangerous)
- **Antiarrhythmic causes**: Class Ia, Ic, beta-blockers, CCBs, digoxin
- **Severity**: `WARNING`
- **Proarrhythmic flag**: `TRUE`

#### **First Degree Heart Block** (`1ST_DEGREE_BLOCK`)
- **Definition**: Prolonged PR interval (>200ms) but all beats conducted
- **Significance**: Mild conduction delay, usually benign but monitor for progression
- **Severity**: `WARNING`
- **Proarrhythmic flag**: `FALSE`

---

### 🟡 Priority 3: Severe Bradycardia

#### **Sinus Bradycardia** (`SINUS_BRADYCARDIA`)
- **Definition**: Sinus rhythm <60 bpm (pathologic if <40-50 bpm with symptoms)
- **Antiarrhythmic causes**:
  - Beta-blockers (metoprolol, esmolol)
  - Calcium channel blockers (diltiazem, verapamil)
  - Digoxin
  - Amiodarone
- **Risk**: Can progress to sinus arrest or junctional escape
- **Severity**: `WARNING`
- **Proarrhythmic flag**: `TRUE` (if severe)

---

### 🔵 Priority 4: Atrial Fibrillation & Flutter (Target Arrhythmias)

#### **Atrial Fibrillation** (`ATRIAL_FIBRILLATION`)
- **Definition**: Chaotic atrial electrical activity, irregularly irregular ventricular response
- **Clinical role**: **Primary arrhythmia being treated**
- **Monitoring goal**: Detect AF episodes, measure AF burden, assess treatment efficacy
- **Severity**: `MONITORED`
- **Proarrhythmic flag**: `FALSE`

#### **Atrial Flutter** (`ATRIAL_FLUTTER`)
- **Definition**: Organized atrial macroreentry, typically 300 bpm with 2:1 or variable block
- **Clinical note**: Can occur paradoxically with Class Ic drugs (organized AF → AFL)
- **Significance**: May be harder to rate-control than AF
- **Severity**: `MONITORED`
- **Proarrhythmic flag**: `FALSE` (but monitor for 1:1 conduction)

---

### 🟢 Priority 5-7: Other Rhythms

#### Supraventricular Arrhythmias
- `SVT` - Supraventricular tachycardia
- `ATRIAL_TACHYCARDIA` - Organized atrial rhythm >100 bpm

#### Junctional Rhythms
- `JUNCTIONAL` - AV node escape rhythm (40-60 bpm)
- `JUNCTIONAL_TACHYCARDIA` - Accelerated junctional rhythm >100 bpm

#### Sinus Rhythms
- `SINUS_RHYTHM` - Normal sinus rhythm (goal of AF treatment)
- `SINUS_TACHYCARDIA` - Sinus rhythm >100 bpm

#### Paced Rhythms
- `AV_PACED` - Dual chamber pacing
- `V_PACED` - Ventricular pacing
- `A_PACED` - Atrial pacing
- `PACED` - Unspecified pacing

---

## Severity Classification

| Severity | Description | Examples | Action |
|----------|-------------|----------|--------|
| **LIFE_THREATENING** | Immediate risk of death | VF, torsades, asystole | Code blue, ACLS |
| **CRITICAL** | Serious arrhythmia requiring urgent treatment | VT, 3rd degree block | Urgent cardiology, ICU |
| **WARNING** | Concerning rhythm suggesting drug toxicity | 2nd degree block, severe bradycardia | Hold/reduce meds, monitor |
| **MONITORED** | Arrhythmia being treated or physiologic | AF, AFL, sinus tachycardia | Continue current plan |
| **NORMAL** | Desired rhythm state | Sinus rhythm | Treatment success |

---

## Database Schema

### `rhythm_segments` Table

| Column | Type | Description |
|--------|------|-------------|
| `stay_id` | INTEGER | ICU stay identifier |
| `segment_id` | INTEGER | Sequential segment number within stay |
| `segment_start` | TIMESTAMP | When rhythm segment started |
| `segment_end` | TIMESTAMP | When rhythm segment ended (next obs or ICU discharge) |
| `duration_hours` | FLOAT | Duration of rhythm segment in hours |
| `rhythm_category` | STRING | Classified rhythm category (see above) |
| `severity_level` | STRING | Clinical severity (LIFE_THREATENING to NORMAL) |
| `is_proarrhythmic_event` | BOOLEAN | TRUE if rhythm suggests antiarrhythmic toxicity |
| `sample_rhythm_values` | STRING | Sample of raw rhythm text values in this segment |
| `num_observations` | INTEGER | Number of rhythm observations in segment |
| `next_rhythm_category` | STRING | Next rhythm after this segment (for transitions) |
| `transitions_to_vt_vf` | BOOLEAN | TRUE if next rhythm is VT/VF/torsades |
| `transitions_to_heart_block` | BOOLEAN | TRUE if next rhythm is 2nd/3rd degree block |

---

## Query Files

### 1. **06_discover_all_rhythm_values.sql**
**Purpose**: Explore all unique rhythm values in the MIMIC database
**When to run**: First, before creating rhythm_segments table
**Output**: List of rhythm text values with preliminary classification
**Use case**: Validate regex patterns, identify undocumented rhythm types

### 2. **07_rhythm_classification_schema.sql**
**Purpose**: Reference document showing the complete classification logic
**When to run**: Don't run directly - use as copy/paste reference
**Output**: Example showing how classification works
**Use case**: Understand the regex patterns and hierarchy

### 3. **08_create_rhythm_segments.sql**
**Purpose**: **MAIN QUERY** - Creates comprehensive rhythm_segments table
**When to run**: After validating classification with Query 6
**Output**: `rhythm_segments` table with all rhythm segments classified
**Cost**: ~$1-3 BigQuery
**Time**: 10-15 minutes
**Use case**: Primary data table for rhythm analysis

---

## Example Analyses

### 1. Find All Proarrhythmic Events

```sql
SELECT
  stay_id,
  segment_start,
  rhythm_category,
  severity_level,
  duration_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE is_proarrhythmic_event = TRUE
ORDER BY severity_level, stay_id, segment_start;
```

### 2. Analyze Rhythm Transitions to VT/VF

```sql
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

### 3. Link Proarrhythmic Events to Medications

```sql
-- Find proarrhythmic events and check what antiarrhythmics patient received
SELECT
  rs.stay_id,
  rs.segment_start AS event_time,
  rs.rhythm_category AS proarrhythmic_rhythm,
  med.medication_name,
  med.medication_class,
  TIMESTAMP_DIFF(rs.segment_start, med.admin_time, HOUR) AS hours_since_med
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments` rs
JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.af_medications` med
  ON rs.stay_id = med.stay_id
WHERE rs.is_proarrhythmic_event = TRUE
  AND med.medication_class = 'antiarrhythmic'
  AND rs.segment_start >= med.admin_time  -- Event after medication
  AND TIMESTAMP_DIFF(rs.segment_start, med.admin_time, HOUR) <= 48  -- Within 48 hours
ORDER BY rs.stay_id, rs.segment_start;
```

### 4. Electrolyte Levels Before Proarrhythmic Events

```sql
-- Check Mg/K levels before torsades or VT events
WITH proarrhythmic_events AS (
  SELECT
    stay_id,
    segment_start AS event_time,
    rhythm_category
  FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
  WHERE rhythm_category IN ('TORSADES_DE_POINTES', 'VENTRICULAR_TACHYCARDIA', 'VENTRICULAR_FIBRILLATION')
)
SELECT
  pe.stay_id,
  pe.event_time,
  pe.rhythm_category,
  el.lab_time,
  el.magnesium,
  el.potassium,
  TIMESTAMP_DIFF(pe.event_time, el.lab_time, HOUR) AS hours_before_event
FROM proarrhythmic_events pe
JOIN `tactical-grid-454202-h6.mimic_af_electrolytes.electrolyte_labs` el
  ON pe.stay_id = el.stay_id
WHERE el.lab_time <= pe.event_time  -- Lab before event
  AND TIMESTAMP_DIFF(pe.event_time, el.lab_time, HOUR) <= 24  -- Within 24 hours
ORDER BY pe.stay_id, pe.event_time;
```

---

## Clinical Interpretation Guidelines

### Evaluating Proarrhythmic Risk

**High-Risk Scenario**:
```
Patient receives Class III antiarrhythmic (sotalol or dofetilide)
+ Low magnesium (<1.6 mg/dL) or low potassium (<3.5 mEq/L)
+ Female sex
+ Baseline QTc >450ms
→ 5-10% risk of torsades de pointes
```

**Monitoring Strategy**:
1. Check Mg/K levels before starting Class Ia/III drugs
2. Replete to Mg >2.0 and K >4.0
3. Monitor rhythm closely for 48-72 hours after initiation
4. Watch for rhythm transitions: NSR → VT/VF or NSR → heart block

### Medication-Specific Considerations

| Drug Class | Primary Risk | Monitoring Focus |
|------------|--------------|------------------|
| **Class Ia** (quinidine, procainamide) | Torsades (2-8%) | QTc, Mg/K, VT/VF |
| **Class Ic** (flecainide, propafenone) | VT in structural heart disease | Look for VT, avoid if CAD/CHF |
| **Class III** (sotalol, dofetilide, ibutilide) | Torsades (2-5%) | QTc, Mg/K, torsades |
| **Beta-blockers** | Bradycardia, heart block | HR <40, 2nd/3rd degree block |
| **CCBs** (diltiazem, verapamil) | Bradycardia, heart block | HR <40, AV blocks |
| **Digoxin** | Bradycardia, AV block, junctional | HR, junctional rhythm, blocks |
| **Amiodarone** | Bradycardia (chronic) | HR <50, may be acceptable |

---

## Validation & Quality Checks

### After Creating rhythm_segments Table

```sql
-- 1. Check overall counts
SELECT
  COUNT(*) as total_segments,
  COUNT(DISTINCT stay_id) as unique_stays,
  ROUND(AVG(duration_hours), 1) as mean_duration
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`;
```

**Expected**:
- Total segments: 50,000-200,000 (depends on rhythm change frequency)
- Unique stays: 20,000-40,000 (most ICU patients have rhythm monitoring)

```sql
-- 2. Distribution by rhythm category
SELECT
  rhythm_category,
  COUNT(*) as num_segments,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) as pct_of_total
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
GROUP BY rhythm_category
ORDER BY num_segments DESC
LIMIT 20;
```

**Expected Top Rhythms**:
1. `SINUS_RHYTHM` - 40-60% (most common)
2. `ATRIAL_FIBRILLATION` - 10-20%
3. `SINUS_TACHYCARDIA` - 10-15%
4. `SINUS_BRADYCARDIA` - 3-5%
5. `PACED` - 2-5%
6. `ATRIAL_FLUTTER` - 1-3%
7. `VENTRICULAR_TACHYCARDIA` - <1% (rare but critical)

```sql
-- 3. Proarrhythmic events (should be rare)
SELECT
  rhythm_category,
  COUNT(*) as num_events,
  COUNT(DISTINCT stay_id) as num_patients
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE is_proarrhythmic_event = TRUE
GROUP BY rhythm_category
ORDER BY num_events DESC;
```

**Expected**:
- Total proarrhythmic events: 500-2,000 (<1-2% of segments)
- Most common: Sinus bradycardia, 2nd degree block
- Rare but critical: VT (~50-200 events), torsades (~10-50 events)

---

## References

### Clinical Guidelines
1. **2017 AHA/ACC/HRS Guideline for Management of Patients With Ventricular Arrhythmias** - JACC 2017
2. **Drug-Induced Arrhythmias: A Scientific Statement From the AHA** - Circulation 2022
3. **Antiarrhythmic Medications** - StatPearls 2024

### Proarrhythmic Effects Literature
1. Roden DM. "Drug-induced prolongation of the QT interval." NEJM 2004
2. Cardiac Arrhythmia Suppression Trial (CAST) - increased mortality with Class Ic drugs post-MI
3. "Proarrhythmia associated with antiarrhythmic drugs" - Frontiers in Pharmacology 2023

### MIMIC-IV Documentation
- PhysioNet MIMIC-IV documentation: https://mimic.mit.edu/
- Chartevents table structure and itemid definitions

---

## Troubleshooting

### Issue: Too many "OTHER_UNCLASSIFIED" rhythms

**Solution**: Run `06_discover_all_rhythm_values.sql` and examine the unclassified rhythm text. Add new regex patterns to the classification schema for common undocumented patterns.

### Issue: Proarrhythmic events seem too frequent

**Check**: Some rhythms may be physiologic (e.g., sinus bradycardia in athletes). Consider adjusting the proarrhythmic flag logic or adding heart rate thresholds.

### Issue: Missing rhythm transitions

**Explanation**: Bedside charting may be sparse. Some transitions may occur without documentation. This is a limitation of observational data - focus on captured events.

### Issue: VT/VF events seem rare

**Expected**: True VT/VF is rare in ICU telemetry (~0.1-0.5% of patients). Most are brief runs terminated quickly. Torsades is especially rare (~10-50 events in entire MIMIC database).

---

## Next Steps

1. ✅ **Run Query 6** - Discover actual rhythm values in your data
2. ✅ **Run Query 8** - Create rhythm_segments table
3. **Link to medications** - Join with af_medications table
4. **Link to electrolytes** - Join with electrolyte_labs table
5. **Analyze associations** - Does low Mg/K predict proarrhythmic events?
6. **Build risk models** - Predict who will develop VT/torsades/blocks

---

## Questions?

This rhythm classification system transforms binary AF/non-AF tracking into comprehensive rhythm phenotyping with focus on antiarrhythmic safety. The emphasis on proarrhythmic events enables research into:

- **Safety** of antiarrhythmic drugs in real-world ICU populations
- **Predictors** of life-threatening arrhythmias (electrolytes, drug combinations)
- **Risk stratification** for patients receiving Class I/III antiarrhythmics
- **Treatment patterns** after proarrhythmic events occur

For questions or to report issues with rhythm classification, open an issue in the project repository.
