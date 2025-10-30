# Electrolytes and Atrial Fibrillation Study - Overview

## Research Questions

**Primary Question**: Do low magnesium/potassium levels associate with AF in ICU patients?

**Secondary Question**: Does electrolyte repletion improve outcomes (AF resolution, mortality, LOS)?

---

## Overall Strategy

We will create **5 tables** in your BigQuery dataset: `tactical-grid-454202-h6.mimic_af_electrolytes`

### Table Creation Order

1. **`af_episodes`** - AF episodes with start/end times and duration
2. **`electrolyte_labs`** - Magnesium and potassium labs during ICU stays
3. **`af_medications`** - Medications given during/around AF episodes
4. **`analysis_cohort`** - Final table combining everything for analysis (one row per ICU stay)
5. **`af_episode_medications`** - Medications linked to specific AF episodes

---

## Data Sources Map

| What You Need | Where It Lives | MIMIC Table |
|---------------|----------------|-------------|
| **Magnesium labs** | Lab results | `labevents` |
| **Potassium labs** | Lab results | `labevents` |
| **AF episodes** | Rhythm charting | `chartevents` |
| **Electrolyte administration** | Medications | `emar` + `inputevents` |
| **Patient demographics** | Hospital data | `patients` + `admissions` |
| **ICU stays** | ICU data | `icustays` |
| **Outcomes (mortality, LOS)** | Hospital data | `admissions` |

---

## The Analysis Flow

```
1. Detect AF episodes from chartevents
   ↓
2. Extract magnesium/potassium labs from labevents
   ↓
3. Match labs to AF episodes by time
   ↓
4. Find electrolyte/medication administrations
   ↓
5. Analyze if repletion helped AF resolution
   ↓
6. Add outcomes (mortality, LOS)
   ↓
7. Statistical analysis
```

---

## Prerequisites

**Before starting, ensure you have:**

✅ Created dataset: `tactical-grid-454202-h6.mimic_af_electrolytes` in BigQuery Console
✅ Completed exploration queries (Steps 1-7 from previous discussion)
✅ Access to BigQuery console: https://console.cloud.google.com/bigquery

---

## File Guide

Each numbered file contains the SQL code and instructions for one table:

- **01_CREATE_AF_EPISODES.md** - Build AF episode detection table
- **02_CREATE_ELECTROLYTE_LABS.md** - Extract magnesium and potassium labs
- **03_CREATE_AF_MEDICATIONS.md** - Find all AF-related medications
- **04_CREATE_ANALYSIS_COHORT.md** - Combine everything into master table
- **05_CREATE_EPISODE_MEDICATIONS.md** - Link medications to specific episodes
- **06_ANALYSIS_QUERIES.md** - Statistical analysis queries
- **07_STATISTICAL_PITFALLS.md** - Important considerations

---

## How to Use These Files

**For each numbered file:**

1. Open the file
2. Read the explanation
3. Copy the SQL query
4. Paste into BigQuery console
5. Run the query
6. Verify the results with the verification query provided
7. Move to the next file

**Important**: Create tables **in order** (01 → 05) because later tables depend on earlier ones.

---

## Expected Timeline

- **Table 1 (AF Episodes)**: 5-10 minutes (scans chartevents - largest table)
- **Table 2 (Electrolyte Labs)**: 2-5 minutes
- **Table 3 (Medications)**: 3-7 minutes
- **Table 4 (Analysis Cohort)**: 1-2 minutes (uses tables 1-3)
- **Table 5 (Episode Medications)**: 1-2 minutes

**Total**: ~15-30 minutes for all tables

---

## What You'll Get

After completing all steps, you'll have a comprehensive dataset ready for analysis:

**Analysis-ready tables:**
- One row per ICU stay with AF status, electrolytes, medications, outcomes
- Episode-level data linking specific medications to AF episodes
- Full medication administration records
- Complete electrolyte lab histories

**Ready to answer:**
- Do low electrolytes predict AF?
- Does electrolyte repletion shorten AF duration?
- Do medications affect outcomes?
- What are the mortality/LOS differences?

---

## Next Steps After Table Creation

Once all tables are created:

1. **Exploratory Analysis** - Run queries from file 06
2. **Statistical Testing** - Apply appropriate tests for your hypotheses
3. **Visualization** - Create charts in Python/R using exported data
4. **Consider Confounders** - Review file 07 for statistical pitfalls

---

## Getting Help

If you encounter errors:
- Check that previous tables completed successfully
- Verify dataset name matches: `tactical-grid-454202-h6.mimic_af_electrolytes`
- Ensure you have BigQuery permissions
- Review the verification queries to debug issues

---

**Ready?** Start with **01_CREATE_AF_EPISODES.md**
