# Quick Start Guide - MIMIC-IV AF Study

Get started analyzing atrial fibrillation in ICU patients in 4 steps.

## Before You Begin

Ensure you have:
- ✅ MIMIC-IV access on BigQuery (physionet-data project)
- ✅ Google Cloud SDK installed and authenticated
- ✅ Python 3.8+ with Jupyter

## Installation

### 1. Install Python Dependencies

```bash
# Navigate to project directory
cd "MIMIC Afib study"

# Install required packages
pip install -r requirements.txt
```

### 2. Verify BigQuery Access

```bash
# Test connection
bq ls --project_id=physionet-data

# You should see datasets like:
# - mimiciv_3_1_icu
# - mimiciv_3_1_hosp
# - mimiciv_3_1_derived
```

## Running the Analysis

### Step 1: Discover Rhythm ItemIDs (5-10 minutes)

```bash
jupyter notebook notebooks/01_rhythm_itemid_discovery.ipynb
```

**What to do:**
1. Run all cells sequentially
2. Review the discovered rhythm itemids (typically 2-5 itemids)
3. Check that `data/validated_rhythm_itemids.csv` is created
4. Note the itemid list printed at the end

**Expected output:**
```
Loaded 3 validated rhythm itemids:
[220045, 223257, 224650]
```

### Step 2: Build AF Cohort (10-20 minutes)

```bash
jupyter notebook notebooks/02_af_cohort_construction.ipynb
```

**What to do:**
1. Run all cells sequentially
2. Wait for BigQuery queries to complete (may take 5-15 minutes)
3. Review the cohort summary statistics
4. Check that CSV files are created in `outputs/cohorts/`

**Expected output:**
```
Cohort construction complete!
Total AF episodes: 15,234
Unique ICU stays with AF: 8,456
Unique patients: 7,123
```

### Step 3: Generate Statistics (2-5 minutes)

```bash
jupyter notebook notebooks/03_statistical_analysis.ipynb
```

**What to do:**
1. Run all cells sequentially
2. Review Table 1 and summary statistics
3. Check `outputs/cohorts/summary_statistics.csv`

### Step 4: Create Visualizations (2-5 minutes)

```bash
jupyter notebook notebooks/04_visualization_dashboard.ipynb
```

**What to do:**
1. Run all cells sequentially
2. Review generated figures
3. Check `outputs/figures/` for PNG and HTML files

## What You Get

After running all notebooks, you'll have:

### Data Files
- `outputs/cohorts/af_cohort_complete.csv` - All AF episodes with demographics, medications, outcomes
- `outputs/cohorts/af_cohort_first_episodes.csv` - First episode per ICU stay only
- `outputs/cohorts/af_cohort_patient_level.csv` - One row per unique patient
- `outputs/cohorts/summary_statistics.csv` - Key summary statistics

### Visualizations
- `outputs/figures/cohort_flow.html` - Interactive cohort flow diagram
- `outputs/figures/demographics.png` - Age, gender, race, ICU type
- `outputs/figures/af_characteristics.png` - AF duration, timing, episodes
- `outputs/figures/medication_usage.png` - Medication patterns
- `outputs/figures/outcomes.png` - Mortality and length of stay
- `outputs/figures/summary_dashboard.png` - Comprehensive overview
- `outputs/figures/interactive_scatter.html` - Interactive exploration

### SQL Queries
Reusable templates in `sql_queries/` for:
- Rhythm itemid discovery
- AF episode construction
- Medication extraction
- Demographics and outcomes

## Troubleshooting

### "No validated rhythm itemids found"

**Problem**: Step 1 didn't find enough rhythm itemids
**Solution**:
- Lower the threshold: Change `af_hits > 100` to `af_hits > 50` in the notebook
- Or manually add known rhythm itemids: `[220045, 223257]`

### "BigQuery authentication error"

**Problem**: Not authenticated with Google Cloud
**Solution**:
```bash
gcloud auth login
gcloud config set project tactical-grid-454202-h6
```

### "Query timeout or too expensive"

**Problem**: BigQuery query taking too long
**Solution**:
- Test on MIMIC-IV demo first (100 patients)
- Add LIMIT clause to test queries
- Run during off-peak hours

### "Missing packages"

**Problem**: Import errors
**Solution**:
```bash
pip install --upgrade -r requirements.txt
```

## Next Steps

Once you have the basic cohort:

### 1. Refine Analysis
- Filter for new-onset AF only (exclude first 2 hours)
- Stratify by ICU type or admission source
- Add additional medications or outcomes

### 2. Statistical Modeling
- Logistic regression for mortality prediction
- Cox proportional hazards for time-to-event
- Propensity score matching for treatment effects

### 3. Temporal Analysis
- Trends over admission years
- Seasonal patterns
- Time-of-day effects

### 4. Subgroup Analyses
- By age groups
- By ICU type
- By medication exposure

## Tips for Success

1. **Start Small**: Test queries on MIMIC demo before running on full dataset
2. **Monitor Costs**: Check BigQuery console for query costs
3. **Save Intermediate Results**: Export cohort CSVs to avoid re-running expensive queries
4. **Validate Results**: Compare your numbers with published MIMIC-IV AF studies
5. **Document Changes**: Keep notes on any modifications to queries or inclusion criteria

## Key Variables in Your Cohort

| Variable | Description | Use Case |
|----------|-------------|----------|
| `subject_id` | Unique patient ID | Patient-level analysis |
| `hadm_id` | Hospital admission ID | Admission-level analysis |
| `stay_id` | ICU stay ID | ICU stay-level analysis |
| `episode_number` | AF episode number within stay | Track recurrence |
| `is_first_episode` | Boolean flag for first episode | New-onset AF proxy |
| `af_hours` | AF duration in hours | Episode severity |
| `received_antiarrhythmic` | Boolean for AA medication | Treatment analysis |
| `hospital_expire_flag` | In-hospital death | Primary outcome |
| `sofa_24hours` | First 24h SOFA score | Severity adjustment |

## Time Estimates

- **Total initial setup**: 30-60 minutes
- **First complete run**: 20-40 minutes
- **Subsequent analyses**: 5-10 minutes (using saved cohorts)

## Getting Help

1. **README.md** - Comprehensive documentation
2. **how_to_find_AF_CHATGPT.md** - Detailed methodology
3. **SQL comments** - Each query is well-documented
4. **Notebook markdown** - Step-by-step explanations

## Success Checklist

- [ ] All 4 notebooks run without errors
- [ ] Cohort CSV files created in `outputs/cohorts/`
- [ ] Figures generated in `outputs/figures/`
- [ ] Summary statistics look reasonable
- [ ] Cohort size is in expected range (5,000-10,000 patients)
- [ ] Demographics match published literature

Once all items are checked, you're ready to start your analysis!

---

**Questions?** Review the main README.md or check individual notebook documentation.
