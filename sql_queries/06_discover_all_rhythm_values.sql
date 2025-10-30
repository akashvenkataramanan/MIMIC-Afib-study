-- Query 6: Discover All Rhythm Values
-- This query identifies ALL unique rhythm values documented in chartevents
-- Run this to understand the full range of rhythm documentation patterns
-- This helps build a comprehensive rhythm classification system

-- Step 1: Get validated rhythm itemids (same as AF detection)
WITH rhythm_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

-- Step 2: Extract ALL unique rhythm values with counts
all_rhythm_values AS (
  SELECT
    LOWER(TRIM(ce.value)) AS rhythm_value,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT ce.stay_id) AS num_patients,
    -- Calculate percentage of total observations
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND TRIM(ce.value) != ''
  GROUP BY rhythm_value
)

-- Step 3: Output sorted by frequency
SELECT
  rhythm_value,
  observation_count,
  num_patients,
  pct_of_total,
  -- Add preliminary classification hints
  CASE
    -- Atrial Fibrillation
    WHEN REGEXP_CONTAINS(rhythm_value, r'(atrial.?fibrillation|a[- ]?fib\b|afib)') THEN 'AF'
    -- Atrial Flutter
    WHEN REGEXP_CONTAINS(rhythm_value, r'(atrial.?flutter|a[- ]?flutter\b|aflutter)') THEN 'AFLUTTER'
    -- Sinus Rhythms
    WHEN REGEXP_CONTAINS(rhythm_value, r'(normal.?sinus|sinus.?rhythm|nsr)') THEN 'SINUS'
    WHEN REGEXP_CONTAINS(rhythm_value, r'sinus.?tach') THEN 'SINUS_TACH'
    WHEN REGEXP_CONTAINS(rhythm_value, r'sinus.?brad') THEN 'SINUS_BRADY'
    -- Ventricular Arrhythmias (CRITICAL - Proarrhythmic)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(torsade|torsades)') THEN 'TORSADES (!!)'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(v[- ]?tach|ventricular.?tach|vt\b)') THEN 'VT (!!)'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(v[- ]?fib|ventricular.?fib|vf\b)') THEN 'VF (!!)'
    WHEN REGEXP_CONTAINS(rhythm_value, r'idioventricular') THEN 'IDIOVENTRICULAR (!!)'
    -- SVT
    WHEN REGEXP_CONTAINS(rhythm_value, r'(svt|supraventricular.?tach)') THEN 'SVT'
    -- Junctional
    WHEN REGEXP_CONTAINS(rhythm_value, r'junctional') THEN 'JUNCTIONAL'
    -- Heart Blocks (CRITICAL - Proarrhythmic)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(3rd.?degree|third.?degree|complete.?heart.?block|chb)') THEN '3RD_DEGREE_BLOCK (!!)'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(2nd.?degree|second.?degree|mobitz|wenckeback)') THEN '2ND_DEGREE_BLOCK (!!)'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(1st.?degree|first.?degree)') THEN '1ST_DEGREE_BLOCK'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(av.?block|a-v.?block|heart.?block)') THEN 'AV_BLOCK (!!)'
    -- Paced Rhythms
    WHEN REGEXP_CONTAINS(rhythm_value, r'(paced|pacing|pacer)') THEN 'PACED'
    -- Bradycardia (CRITICAL - Antiarrhythmic side effect)
    WHEN REGEXP_CONTAINS(rhythm_value, r'brad') THEN 'BRADYCARDIA'
    -- Asystole
    WHEN REGEXP_CONTAINS(rhythm_value, r'asystole') THEN 'ASYSTOLE (!!)'
    ELSE 'OTHER'
  END AS preliminary_category
FROM all_rhythm_values
WHERE observation_count >= 10  -- Filter out very rare entries
ORDER BY observation_count DESC
LIMIT 500;

-- INTERPRETATION GUIDE:
-- (!!) = CRITICAL: Potential proarrhythmic event from antiarrhythmic drugs
--
-- Expected Results:
-- - Most common: Sinus rhythm, AF, sinus tachycardia
-- - Important to capture: VT, VF, torsades, heart blocks (proarrhythmic)
-- - Moderate frequency: Atrial flutter, paced rhythms, junctional
-- - Rare but critical: Torsades de pointes, complete heart block
--
-- Next Steps:
-- 1. Review the actual rhythm_value text to refine regex patterns
-- 2. Build comprehensive classification in rhythm_classification_schema.sql
-- 3. Create rhythm_segments table with full classification
