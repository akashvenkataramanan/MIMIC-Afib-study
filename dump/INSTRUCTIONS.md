# How to Use the Diagnostic Audit Query

## Quick Steps

1. **Open BigQuery Console**
   - Go to https://console.cloud.google.com/bigquery

2. **Run the Query**
   - Open `diagnostic_audit_query.sql`
   - Copy the ENTIRE file
   - Paste into BigQuery Console
   - Click "Run"

3. **Download Results as CSV**
   - After query completes, click "Save Results"
   - Choose "CSV (local file)"
   - Save as `stay_30000831_diagnostic.csv`

4. **Share with Me**
   - Upload the CSV to the dump folder
   - I'll analyze it to find exactly where the algorithm breaks

---

## What This Query Shows

**One row per rhythm observation** with columns showing:

### Raw Data
- `charttime`: When rhythm was observed
- `original_value`: Exact rhythm text (e.g., "AF (Atrial Fibrillation)")
- `storetime`: When it was documented
- `caregiver_id`: Who documented it

### Pipeline Steps
- `labeled_as_af`: Did regex classify this as AF? (TRUE/FALSE)
- `dedup_rank`: 1 = KEPT, 2+ = DISCARDED
- `obs_at_charttime`: How many observations at this same time?
- `has_conflict`: YES if multiple rhythms charted at same time
- `dedup_decision`: KEPT or DISCARDED

### Segmentation
- `segment_id`: Which segment this belongs to (NULL if discarded)
- `prev_is_af`: Previous observation's is_af value
- `segment_change`: NEW_SEGMENT or CONTINUES

### Final Results
- `episode_number`: Which AF episode (1, 2, 3...)
- `episode_start/end`: Episode boundaries
- `episode_duration_hours`: How long it lasted

---

## What to Look For (Red Flags)

### 🚩 Red Flag 1: Conflicting Observations
Look for rows where:
- `has_conflict = 'YES'`
- `dedup_decision = 'DISCARDED'`
- `labeled_as_af = FALSE`

**This means**: A non-AF rhythm was charted but got thrown away because an AF observation existed at the same time!

### 🚩 Red Flag 2: Wrong Regex Labeling
Look for rows where:
- `original_value` contains "Flut" (Flutter)
- BUT `labeled_as_af = TRUE`

**This means**: The regex is wrongly matching flutter as fibrillation!

### 🚩 Red Flag 3: Long Episodes Spanning Different Rhythms
Look at the `episode_duration_hours` column:
- If you see episodes lasting 13+ hours
- But the raw observations show different rhythms (1st AV, A Flut) in that timespan
- **This confirms the algorithm is broken**

---

## Expected Size

- **Rows**: ~50-100 observations for this patient
- **File size**: <50 KB
- **Time to run**: <30 seconds

---

## Next Steps

After you share the CSV, I'll:
1. Identify the exact charttimes where conflicts occur
2. Show which observations got discarded incorrectly
3. Confirm whether the regex or dedup logic is the problem
4. Provide the fixed code

Then we can re-run the corrected query and verify it produces the right episodes!
