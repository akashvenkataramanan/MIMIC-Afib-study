# Electrolytes & Atrial Fibrillation Study - Step-by-Step Guide

This folder contains everything you need to build and analyze your dataset studying the relationship between electrolytes (magnesium and potassium) and atrial fibrillation in ICU patients.

---

## 📚 File Guide

Read and execute files **in order**:

### Setup & Planning
- **00_OVERVIEW.md** - START HERE! Overview of the entire project, research questions, and workflow

### Data Creation (Run in BigQuery)
- **01_CREATE_AF_EPISODES.md** - Detect AF episodes from rhythm charting (15-20 min)
- **02_CREATE_ELECTROLYTE_LABS.md** - Extract magnesium and potassium labs (5 min)
- **03_CREATE_AF_MEDICATIONS.md** - Find all AF-related medications (5-10 min)
- **04_CREATE_ANALYSIS_COHORT.md** - Combine everything into master analysis table (2 min)
- **05_CREATE_EPISODE_MEDICATIONS.md** - Link meds to specific episodes [OPTIONAL] (2 min)

### Analysis & Interpretation
- **06_ANALYSIS_QUERIES.md** - Statistical analysis queries for your research questions
- **07_STATISTICAL_PITFALLS.md** - **MUST READ** before drawing conclusions!

---

## ⚡ Quick Start

**Step 1**: Read `00_OVERVIEW.md`

**Step 2**: Open BigQuery Console: https://console.cloud.google.com/bigquery

**Step 3**: Execute SQL from files 01-05 in order

**Step 4**: Run analysis queries from file 06

**Step 5**: Review pitfalls in file 07 before publishing

---

## 🎯 Research Questions You'll Answer

1. **Do low magnesium/potassium levels predict AF in ICU patients?**
2. **Does electrolyte repletion shorten AF duration?**
3. **Does repletion improve outcomes (mortality, length of stay)?**

---

## 📊 What You'll Get

**5 Tables in BigQuery:**
1. `af_episodes` - All AF episodes with timing
2. `electrolyte_labs` - All Mg/K labs during ICU
3. `af_medications` - All medications administered
4. `analysis_cohort` - **MAIN TABLE** - One row per ICU stay
5. `af_episode_medications` - Medications linked to specific episodes

**Ready for Analysis:**
- Export to CSV for Python/R
- Run statistical tests
- Create visualizations
- Write your paper!

---

## ⏱️ Time Investment

- **Data creation**: 30-45 minutes total
- **Analysis**: Hours to days (depending on depth)
- **Statistical review**: Critical - take your time!

---

## 💰 Cost Estimate

**Total BigQuery costs**: ~$5-10

- File 01 (AF episodes): $1-3 (scans chartevents - largest)
- File 02 (Labs): $0.50-1
- File 03 (Meds): $0.50-1.50
- File 04 (Cohort): $0.10-0.30
- File 05 (Episode meds): $0.05-0.10
- Analysis queries: Minimal (use your tables)

---

## ⚠️ Important Notes

### Before You Start
- Ensure you have access to MIMIC-IV on BigQuery
- Create dataset: `tactical-grid-454202-h6.mimic_af_electrolytes`
- Have Python/R ready for advanced statistics

### While Working
- Run verification queries after EACH table creation
- Check row counts and sample data
- Don't skip the verification steps!

### Before Publishing
- **READ FILE 07** - Statistical Pitfalls
- Run sensitivity analyses
- Consider confounders
- Acknowledge limitations

---

## 📖 Documentation

Each file contains:
- ✅ Clear explanation of what the query does
- ✅ Complete SQL code ready to copy/paste
- ✅ Verification queries to check results
- ✅ Troubleshooting tips
- ✅ Expected outputs

---

## 🆘 Troubleshooting

**Query fails?**
- Check that previous tables were created successfully
- Verify dataset name matches: `tactical-grid-454202-h6.mimic_af_electrolytes`
- Review error message - often points to the issue

**Unexpected results?**
- Run verification queries in each file
- Compare with expected outputs
- Check for NULL values or missing data

**Need help?**
- Review the troubleshooting section in each file
- Check BigQuery error messages
- Verify MIMIC-IV access

---

## 🎓 Learning Path

**If you're new to SQL:**
- Start with file 00 for overview
- Read each file thoroughly before running queries
- Understand what each CTE (WITH clause) does
- Check results at each step

**If you're experienced:**
- Skim file 00
- Run files 01-05 sequentially
- Focus on files 06-07 for analysis

---

## 📝 Citation

If you use this framework for publication, consider citing:

- **MIMIC-IV**: Johnson et al. (2023). MIMIC-IV (version 3.1). PhysioNet.
- **This methodology**: Based on chartevents rhythm detection approach

---

## 🚀 You're All Set!

Everything you need is in this folder. Work through the files in order, take your time with the statistical considerations, and do great science!

**Questions?** Each file has detailed explanations and troubleshooting tips.

**Ready to start?** Open `00_OVERVIEW.md` now!

---

*Last updated: October 29, 2025*
