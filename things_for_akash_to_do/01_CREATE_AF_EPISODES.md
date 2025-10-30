# Step 1: Create AF Episodes Table

## What This Does

This query creates a table with all AF episodes detected from bedside rhythm charting, including:
- Start and end time of each AF episode
- Duration in hours
- Episode number (for patients with multiple episodes)
- Number of rhythm observations in the episode

## The Algorithm

1. **Find rhythm itemids** - Identify which chartevents items contain rhythm data
2. **Extract observations** - Get all rhythm charting from chartevents
3. **Label as AF/non-AF** - Use regex to identify AF documentation
4. **Deduplicate** - Remove duplicate observations at same timestamp
5. **Segment** - Create new segments when rhythm changes (AF → Sinus or vice versa)
6. **Compress** - Group observations into episodes
7. **Calculate duration** - Compute AF duration using ICU discharge as endpoint if needed

## Expected Results

- **10,000-20,000 AF episodes** across all ICU stays
- **5,000-10,000 unique ICU stays** with at least one AF episode
- Episode durations ranging from <1 hour to >48 hours

---

## SQL Query to Run

**Copy and paste this into BigQuery Console:**

```sql
-- Create AF episodes table with timing and duration
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes` AS

-- Step 1: Get validated rhythm itemids
WITH rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- Step 2: Extract all rhythm observations
rhythm_obs AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND ce.charttime IS NOT NULL
),

-- Step 3: Label each observation as AF or non-AF
labeled AS (
  SELECT
    stay_id,
    charttime,
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]?fib|afib)') AS is_af,
    value_lc as rhythm_value
  FROM rhythm_obs
),

-- Step 4: Remove duplicate observations at same timestamp
dedup AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    rhythm_value
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY stay_id, charttime ORDER BY is_af DESC) as rn
    FROM labeled
  )
  WHERE rn = 1
),

-- Step 5: Create segments when rhythm changes
segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    rhythm_value,
    -- Create new segment ID when rhythm changes
    SUM(CASE
      WHEN is_af != LAG(is_af) OVER (PARTITION BY stay_id ORDER BY charttime)
        OR LAG(is_af) OVER (PARTITION BY stay_id ORDER BY charttime) IS NULL
      THEN 1
      ELSE 0
    END) OVER (PARTITION BY stay_id ORDER BY charttime) AS segment_id
  FROM dedup
),

-- Step 6: Compress into AF episodes
af_segments AS (
  SELECT
    stay_id,
    segment_id,
    MIN(charttime) AS segment_start,
    MAX(charttime) AS segment_end,
    ANY_VALUE(is_af) AS is_af,
    COUNT(*) as num_observations
  FROM segmented
  GROUP BY stay_id, segment_id
),

-- Step 7: Get AF episodes only with ICU boundaries
af_episodes_raw AS (
  SELECT
    seg.stay_id,
    seg.segment_start AS af_start,
    -- AF ends at next observation or ICU discharge
    COALESCE(
      LEAD(seg.segment_start) OVER (PARTITION BY seg.stay_id ORDER BY seg.segment_start),
      icu.outtime
    ) AS af_end,
    seg.num_observations
  FROM af_segments seg
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON seg.stay_id = icu.stay_id
  WHERE seg.is_af = TRUE
)

-- Final output: AF episodes with duration and episode number
SELECT
  stay_id,
  af_start,
  af_end,
  TIMESTAMP_DIFF(af_end, af_start, MINUTE) / 60.0 AS af_duration_hours,
  ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY af_start) AS episode_number,
  num_observations
FROM af_episodes_raw
WHERE TIMESTAMP_DIFF(af_end, af_start, MINUTE) > 0  -- Only episodes with positive duration
ORDER BY stay_id, af_start;
```

---

## Verification Queries

### Check 1: Did the table create successfully?

```sql
-- Basic counts
SELECT
  COUNT(*) as total_af_episodes,
  COUNT(DISTINCT stay_id) as icu_stays_with_af
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes`;
```

**Expected**:
- Total episodes: 10,000-20,000
- Unique stays: 5,000-10,000

---

### Check 2: Look at sample episodes

```sql
-- Preview first 20 episodes
SELECT
  stay_id,
  af_start,
  af_end,
  af_duration_hours,
  episode_number,
  num_observations
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes`
LIMIT 20;
```

**What to look for**:
- `af_start` should be before `af_end`
- `af_duration_hours` should be positive
- `episode_number` should start at 1 for each stay_id

---

### Check 3: AF duration distribution

```sql
-- Distribution of AF episode durations
SELECT
  CASE
    WHEN af_duration_hours < 1 THEN '<1 hour'
    WHEN af_duration_hours < 6 THEN '1-6 hours'
    WHEN af_duration_hours < 24 THEN '6-24 hours'
    WHEN af_duration_hours < 48 THEN '24-48 hours'
    ELSE '>48 hours'
  END as duration_category,
  COUNT(*) as num_episodes,
  ROUND(AVG(af_duration_hours), 1) as mean_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes`
GROUP BY duration_category
ORDER BY MIN(af_duration_hours);
```

**Expected distribution**:
- Most episodes: 1-24 hours
- Some brief episodes (<1 hour)
- Some prolonged episodes (>48 hours)

---

### Check 4: Patients with multiple episodes

```sql
-- How many patients have multiple AF episodes?
SELECT
  MAX(episode_number) as max_episodes_per_stay,
  COUNT(*) as num_stays
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes`
GROUP BY stay_id
HAVING MAX(episode_number) > 1
ORDER BY max_episodes_per_stay DESC
LIMIT 10;
```

**What to look for**:
- Some patients should have 2-5+ episodes
- Episode numbers should be sequential (1, 2, 3...)

---

## Understanding the Output

### Column Descriptions

| Column | Type | Description |
|--------|------|-------------|
| `stay_id` | INTEGER | Unique ICU stay identifier |
| `af_start` | TIMESTAMP | When AF episode started (first AF observation) |
| `af_end` | TIMESTAMP | When AF episode ended (next non-AF obs or ICU discharge) |
| `af_duration_hours` | FLOAT | Duration of AF episode in hours |
| `episode_number` | INTEGER | Episode number within this ICU stay (1 = first) |
| `num_observations` | INTEGER | Number of rhythm observations in this episode |

### Example Data

| stay_id | af_start | af_end | af_duration_hours | episode_number |
|---------|----------|--------|-------------------|----------------|
| 30000102 | 2020-01-15 14:00 | 2020-01-15 22:00 | 8.0 | 1 |
| 30000102 | 2020-01-16 06:00 | 2020-01-16 10:00 | 4.0 | 2 |
| 30000345 | 2019-06-22 08:30 | 2019-06-22 20:00 | 11.5 | 1 |

**Interpretation**:
- Patient 30000102 had 2 separate AF episodes
- First episode lasted 8 hours
- Second episode lasted 4 hours

---

## Troubleshooting

### Issue: "Table not found" error
**Solution**: Make sure you created the dataset first:
- Dataset name: `mimic_af_electrolytes`
- In project: `tactical-grid-454202-h6`

### Issue: "No AF episodes found" or very few
**Solution**: Check rhythm itemids - may need to adjust the WHERE clause in `rhythm_itemids` CTE

### Issue: Query timeout
**Solution**: This query scans chartevents (large table). It may take 5-10 minutes. Be patient!

### Issue: Negative durations
**Solution**: Should not happen with the `WHERE` filter. If you see this, check your data.

---

## Cost Estimate

**BigQuery cost**: ~$1-3 (scans chartevents table)

This is the most expensive query in the series because chartevents is huge. Subsequent queries will be cheaper!

---

## Next Step

✅ Once this table is created and verified, proceed to:

**02_CREATE_ELECTROLYTE_LABS.md**
