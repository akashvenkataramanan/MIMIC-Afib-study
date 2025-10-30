# MIMIC-IV Atrial Fibrillation ICU Study

A comprehensive analysis pipeline for identifying and characterizing patients admitted to the ICU with atrial fibrillation using the MIMIC-IV database on Google BigQuery.

## Project Overview

This project identifies all patients admitted to the ICU with atrial fibrillation (AF) and analyzes their characteristics, treatment patterns, and outcomes. The analysis uses bedside rhythm charting from the `chartevents` table, which provides reliable hour-scale onset/offset timing for AF episodes.

### Key Features

- **AF Detection**: Identifies AF episodes from ICU rhythm charting (chartevents)
- **Episode Tracking**: Tracks all AF episodes per patient and flags first occurrences
- **Medication Analysis**: Links antiarrhythmic and rate control medication administrations to AF episodes
- **Comprehensive Outcomes**: Analyzes mortality, length of stay, and severity scores
- **Interactive Visualizations**: Generates publication-ready figures and interactive dashboards

## Project Structure

```
MIMIC Afib study/
├── config.py                          # Configuration file with dataset paths and parameters
├── README.md                          # This file
├── how_to_find_AF_CHATGPT.md         # Detailed methodology guide
│
├── notebooks/                         # Jupyter notebooks for analysis
│   ├── 01_rhythm_itemid_discovery.ipynb    # Identify rhythm itemids
│   ├── 02_af_cohort_construction.ipynb     # Build AF cohort
│   ├── 03_statistical_analysis.ipynb       # Statistical summaries
│   └── 04_visualization_dashboard.ipynb    # Create visualizations
│
├── sql_queries/                       # Reusable SQL query templates
│   ├── 01_discover_rhythm_itemids.sql      # Find rhythm itemids
│   ├── 02_af_episodes_timeline.sql         # Build AF episodes
│   ├── 03_medications.sql                  # Extract medications
│   ├── 04_demographics_outcomes.sql        # Get demographics/outcomes
│   └── 05_complete_cohort.sql              # Complete cohort query
│
├── outputs/                           # Analysis outputs
│   ├── cohorts/                       # Cohort CSV files
│   └── figures/                       # Visualizations
│
└── data/                              # Intermediate data files
    └── validated_rhythm_itemids.csv   # Validated itemids from step 1
```

## Prerequisites

### 1. MIMIC-IV Access

- Complete CITI training and obtain PhysioNet credentialing
- Request access to MIMIC-IV on BigQuery via PhysioNet
- Ensure you have access to `physionet-data` project with MIMIC-IV v3.1 datasets

### 2. Software Requirements

```bash
# Python packages
pip install pandas numpy matplotlib seaborn plotly google-cloud-bigquery jupyter scipy

# Google Cloud SDK (already installed and updated)
gcloud version
```

### 3. Authentication

Already completed - authenticated with `akashvenkataramanan2@gmail.com`

## Getting Started

### Step 1: Rhythm ItemID Discovery

Run `notebooks/01_rhythm_itemid_discovery.ipynb` to identify which `itemid` values in `chartevents` contain rhythm information.

**What it does:**
- Queries chartevents to find itemids with AF-related values
- Validates quality by examining sample values
- Saves validated itemids to `data/validated_rhythm_itemids.csv`

**Expected output:**
- List of 2-5 validated rhythm itemids
- Typically includes itemid 220045 (Rhythm) and 223257 (Heart Rhythm)

### Step 2: Cohort Construction

Run `notebooks/02_af_cohort_construction.ipynb` to build the complete AF cohort.

**What it does:**
- Constructs AF episodes from validated rhythm itemids
- Links medication administrations (eMAR + ICU drips)
- Adds demographics, severity scores, and outcomes
- Exports cohort to CSV files

**Expected outputs:**
- `outputs/cohorts/af_cohort_complete.csv` - All AF episodes
- `outputs/cohorts/af_cohort_first_episodes.csv` - First episodes only
- `outputs/cohorts/af_cohort_patient_level.csv` - One row per patient

**Runtime:** 5-15 minutes (queries chartevents table)

### Step 3: Statistical Analysis

Run `notebooks/03_statistical_analysis.ipynb` for comprehensive statistics.

**What it does:**
- Generates Table 1 (patient characteristics)
- Analyzes AF episode patterns
- Examines medication usage
- Compares outcomes by treatment
- Performs statistical tests

**Expected outputs:**
- Console output with formatted tables
- `outputs/cohorts/summary_statistics.csv`

### Step 4: Visualization Dashboard

Run `notebooks/04_visualization_dashboard.ipynb` to create visualizations.

**What it does:**
- Creates cohort flow diagram
- Generates demographics charts
- Visualizes AF characteristics
- Shows medication patterns
- Compares outcomes

**Expected outputs:**
- Static PNG files in `outputs/figures/`
- Interactive HTML plots for exploration

## Methodology

### AF Identification Approach

This project uses **bedside rhythm charting** from `chartevents` rather than diagnosis codes (ICD-9/ICD-10) because:

1. **Better timing**: Charting provides hour-scale onset/offset times
2. **More reliable**: Direct observation vs administrative coding
3. **Episode detection**: Can identify multiple episodes per stay

### Algorithm

1. **Rhythm Extraction**: Extract all rhythm observations from chartevents
2. **Labeling**: Classify each observation as AF or non-AF using regex
3. **Segmentation**: Create contiguous segments when rhythm changes
4. **Episode Construction**: Compress segments into AF episodes with start/end times
5. **Duration Calculation**: Compute AF duration in hours
6. **Medication Matching**: Overlap medications with AF episode time windows
7. **Outcomes Linkage**: Join demographics and outcomes

### Data Sources

| Data Type | Source Table | Purpose |
|-----------|-------------|---------|
| Rhythm charting | `mimiciv_3_1_icu.chartevents` | AF detection |
| ICU stays | `mimiciv_3_1_icu.icustays` | Episode boundaries |
| Medications (precise) | `mimiciv_3_1_hosp.emar` | Medication timing (2016+) |
| Medications (drips) | `mimiciv_3_1_icu.inputevents` | Continuous infusions |
| Demographics | `mimiciv_3_1_hosp.patients` | Age, gender, mortality |
| Admissions | `mimiciv_3_1_hosp.admissions` | Outcomes, LOS |
| Severity scores | `mimiciv_3_1_derived.first_day_sofa` | SOFA scores |

## Configuration

Edit `config.py` to customize:

```python
# BigQuery datasets (usually no need to change)
PROJECT_ID = "physionet-data"
MIMIC_ICU_DATASET = "mimiciv_3_1_icu"
MIMIC_HOSP_DATASET = "mimiciv_3_1_hosp"
MIMIC_DERIVED_DATASET = "mimiciv_3_1_derived"

# Your project for results
OUTPUT_PROJECT_ID = "tactical-grid-454202-h6"

# AF detection parameters
AF_REGEX = r'(atrial.?fibrillation|a[- ]?fib|afib)'
MIN_AF_DURATION_HOURS = 0.0

# Medication lists (add/remove as needed)
ANTIARRHYTHMIC_MEDS = ['amiodarone', 'ibutilide', 'procainamide', ...]
RATE_CONTROL_MEDS = ['metoprolol', 'esmolol', 'diltiazem', ...]
```

## Expected Results

Based on MIMIC-IV v3.1, you should expect approximately:

- **Total AF episodes**: 10,000-20,000
- **Unique patients**: 5,000-10,000
- **Median age**: 65-75 years
- **Hospital mortality**: 15-25%
- **Antiarrhythmic use**: 20-40% of patients
- **Median AF duration**: 6-24 hours

*Exact numbers depend on your rhythm itemid selection and inclusion criteria*

## Validation and Quality Checks

### Recommended Validation Steps

1. **Sample chart review**: Manually review 20-30 patients in MIMIC to verify AF detection accuracy
2. **Compare with published studies**: Compare demographics and outcomes with published MIMIC-IV AF papers
3. **Temporal checks**: Verify AF episodes fall within ICU stay boundaries
4. **Medication timing**: Check that eMAR coverage is adequate (should be good for 2016+)

### Known Limitations

1. **Charting quality**: Nurse-charted rhythm may miss some AF episodes or have delays
2. **eMAR coverage**: Most reliable from 2016 onward
3. **New-onset vs chronic AF**: This analysis doesn't distinguish between them (requires additional logic)
4. **Paroxysmal AF**: Brief episodes (<1 hour) may be under-detected

## Troubleshooting

### Common Issues

**Issue**: "No rhythm itemids found"
- **Solution**: Lower the threshold in rhythm discovery (try `af_hits > 50`)

**Issue**: "BigQuery quota exceeded"
- **Solution**: Run queries during off-peak hours, or use LIMIT clause for testing

**Issue**: "No medication data"
- **Solution**: Check date ranges - eMAR is most complete 2016+

**Issue**: "SOFA scores missing for many patients"
- **Solution**: This is expected - derived tables don't cover all patients

## Cost Management

BigQuery charges for data scanned. To minimize costs:

1. **Use the MIMIC-IV demo** first (100 patients) to test queries
2. **Always include WHERE clauses** to limit data scanned
3. **Avoid SELECT *** - specify only needed columns
4. **Materialize intermediate results** if running iterative analyses
5. **Monitor query costs** in BigQuery console

**Estimated costs for full analysis**: $5-20 depending on query efficiency

## Citation and References

### MIMIC-IV Dataset

```
Johnson, A., Bulgarelli, L., Pollard, T., Horng, S., Celi, L. A., & Mark, R. (2023).
MIMIC-IV (version 3.1). PhysioNet. https://doi.org/10.13026/kpb9-mt58
```

### PhysioNet

```
Goldberger, A., Amaral, L., Glass, L., Hausdorff, J., Ivanov, P. C., Mark, R., ... &
Stanley, H. E. (2000). PhysioNet: Components of a new research resource for complex
physiologic signals. Circulation, 101(23), e215-e220.
```

### Related Publications

- [MIMIC-IV documentation](https://physionet.org/content/mimiciv/)
- [eMAR timing paper](https://www.nature.com/articles/s41597-022-01899-x)
- [NOAF in ICU with MIMIC](https://pmc.ncbi.nlm.nih.gov/articles/PMC11523862/)

## Support

For issues with:
- **MIMIC-IV access**: Contact PhysioNet support
- **BigQuery errors**: Check [Google Cloud documentation](https://cloud.google.com/bigquery/docs)
- **Analysis questions**: Refer to `how_to_find_AF_CHATGPT.md` for detailed methodology

## License

This analysis code is provided as-is for research purposes. MIMIC-IV data usage must comply with PhysioNet Data Use Agreement.

## Acknowledgments

- MIT Laboratory for Computational Physiology for MIMIC-IV
- PhysioNet for data hosting and access infrastructure
- Google Cloud for BigQuery infrastructure

---

**Project Status**: ✅ Ready for analysis

**Last Updated**: October 26, 2025

**Contact**: akashvenkataramanan2@gmail.com
