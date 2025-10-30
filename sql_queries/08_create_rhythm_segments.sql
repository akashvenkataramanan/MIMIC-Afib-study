-- Query 8: Create Comprehensive Rhythm Segments Table
-- This creates a table with ALL rhythm segments (not just AF episodes)
-- Each segment is classified using the comprehensive rhythm classification schema
--
-- USE CASE: Analyze rhythm transitions, identify proarrhythmic events, track
-- antiarrhythmic drug effects beyond just AF suppression
--
-- COST: ~$1-3 (similar to AF episodes query)
-- TIME: 10-15 minutes

CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments` AS

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
    LOWER(TRIM(ce.value)) AS rhythm_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND TRIM(ce.value) != ''
    AND ce.charttime IS NOT NULL
),

-- Step 3: Classify each rhythm observation using comprehensive schema
classified AS (
  SELECT
    stay_id,
    charttime,
    rhythm_value,

    -- Apply rhythm classification (from 07_rhythm_classification_schema.sql)
    CASE
      -- PRIORITY 1: LIFE-THREATENING VENTRICULAR ARRHYTHMIAS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|torsades)') THEN 'TORSADES_DE_POINTES'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?fib|ventricular.?fib(rillation)?|vf\b)') THEN 'VENTRICULAR_FIBRILLATION'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?tach|ventricular.?tach(ycardia)?|vt\b|polymorphic|monomorphic)') THEN 'VENTRICULAR_TACHYCARDIA'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)idioventricular') THEN 'IDIOVENTRICULAR'

      -- PRIORITY 2: HEART BLOCKS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(3rd.?degree|third.?degree|complete.?(heart.?)?block|chb)') THEN '3RD_DEGREE_BLOCK'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(2nd.?degree|second.?degree|mobitz|wenckebach)') THEN '2ND_DEGREE_BLOCK'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(av.?block|a-v.?block|heart.?block)') THEN 'AV_BLOCK_UNSPECIFIED'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(1st.?degree|first.?degree)') THEN '1ST_DEGREE_BLOCK'

      -- PRIORITY 3: SEVERE BRADYCARDIA
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)sinus.?brad') THEN 'SINUS_BRADYCARDIA'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)brad') THEN 'BRADYCARDIA'

      -- PRIORITY 4: ATRIAL FIBRILLATION & FLUTTER
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?fibrillation|a[- ]?fib\b|afib|af\b)') THEN 'ATRIAL_FIBRILLATION'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?flutter|a[- ]?flutter\b|aflutter)') THEN 'ATRIAL_FLUTTER'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(rvr|rapid.?ventricular)') THEN 'RAPID_VENTRICULAR_RESPONSE'

      -- PRIORITY 5: OTHER SUPRAVENTRICULAR ARRHYTHMIAS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(svt|supraventricular.?tach)') THEN 'SVT'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)atrial.?tach') THEN 'ATRIAL_TACHYCARDIA'

      -- PRIORITY 6: JUNCTIONAL RHYTHMS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)junctional.?tach') THEN 'JUNCTIONAL_TACHYCARDIA'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)junctional') THEN 'JUNCTIONAL'

      -- PRIORITY 7: NORMAL SINUS RHYTHMS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)sinus.?tach') THEN 'SINUS_TACHYCARDIA'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(normal.?sinus|sinus.?rhythm|nsr)') THEN 'SINUS_RHYTHM'

      -- PRIORITY 8: PACED RHYTHMS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(av.?paced|a-v.?paced|dual.?chamber.?pac)') THEN 'AV_PACED'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v.?paced|ventricular.?pac)') THEN 'V_PACED'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(a.?paced|atrial.?pac)') THEN 'A_PACED'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(paced|pacing|pacer)') THEN 'PACED'

      -- PRIORITY 9: OTHER CLINICAL EVENTS
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)asystole') THEN 'ASYSTOLE'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(pvc|premature.?ventricular)') THEN 'PVC'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(pac|premature.?atrial)') THEN 'PAC'

      ELSE 'OTHER_UNCLASSIFIED'
    END AS rhythm_category,

    -- Severity classification
    CASE
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|v[- ]?fib|ventricular.?fib|asystole)')
        THEN 'LIFE_THREATENING'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?tach|ventricular.?tach|3rd.?degree|third.?degree|complete.?block)')
        THEN 'CRITICAL'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(2nd.?degree|mobitz|av.?block|idioventricular|sinus.?brad)')
        THEN 'WARNING'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?fib|atrial.?flutter|sinus.?tach)')
        THEN 'MONITORED'
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(normal.?sinus|sinus.?rhythm|nsr)')
        THEN 'NORMAL'
      ELSE 'OTHER'
    END AS severity_level,

    -- Proarrhythmic event flag
    CASE
      WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|v[- ]?fib|v[- ]?tach|ventricular|3rd.?degree|2nd.?degree|complete.?block|av.?block|idioventricular)')
        THEN TRUE
      ELSE FALSE
    END AS is_proarrhythmic_event

  FROM rhythm_obs
),

-- Step 4: Remove duplicate observations at same timestamp (prefer proarrhythmic events)
dedup AS (
  SELECT
    stay_id,
    charttime,
    rhythm_value,
    rhythm_category,
    severity_level,
    is_proarrhythmic_event
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY stay_id, charttime
        ORDER BY is_proarrhythmic_event DESC, severity_level
      ) as rn
    FROM classified
  )
  WHERE rn = 1
),

-- Step 5: Create segments when rhythm CATEGORY changes
segmented AS (
  SELECT
    stay_id,
    charttime,
    rhythm_value,
    rhythm_category,
    severity_level,
    is_proarrhythmic_event,
    -- Create new segment ID when rhythm category changes
    SUM(CASE
      WHEN rhythm_category != LAG(rhythm_category) OVER (PARTITION BY stay_id ORDER BY charttime)
        OR LAG(rhythm_category) OVER (PARTITION BY stay_id ORDER BY charttime) IS NULL
      THEN 1
      ELSE 0
    END) OVER (PARTITION BY stay_id ORDER BY charttime) AS segment_id
  FROM dedup
),

-- Step 6: Compress into rhythm segments
segments AS (
  SELECT
    stay_id,
    segment_id,
    MIN(charttime) AS segment_start,
    MAX(charttime) AS segment_end,
    ANY_VALUE(rhythm_category) AS rhythm_category,
    ANY_VALUE(severity_level) AS severity_level,
    ANY_VALUE(is_proarrhythmic_event) AS is_proarrhythmic_event,
    -- Collect sample rhythm values for this segment
    STRING_AGG(DISTINCT rhythm_value, '; ' LIMIT 5) AS sample_rhythm_values,
    COUNT(*) as num_observations
  FROM segmented
  GROUP BY stay_id, segment_id
),

-- Step 7: Add segment endpoints and ICU boundaries
segments_with_endpoints AS (
  SELECT
    seg.stay_id,
    seg.segment_id,
    seg.segment_start,
    -- Segment ends at next observation or ICU discharge
    COALESCE(
      LEAD(seg.segment_start) OVER (PARTITION BY seg.stay_id ORDER BY seg.segment_start),
      icu.outtime
    ) AS segment_end,
    seg.rhythm_category,
    seg.severity_level,
    seg.is_proarrhythmic_event,
    seg.sample_rhythm_values,
    seg.num_observations,
    -- Add next rhythm for transition analysis
    LEAD(seg.rhythm_category) OVER (PARTITION BY seg.stay_id ORDER BY seg.segment_start) AS next_rhythm_category
  FROM segments seg
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON seg.stay_id = icu.stay_id
)

-- Final output: All rhythm segments with classification and transitions
SELECT
  stay_id,
  segment_id,
  segment_start,
  segment_end,
  TIMESTAMP_DIFF(segment_end, segment_start, MINUTE) / 60.0 AS duration_hours,
  rhythm_category,
  severity_level,
  is_proarrhythmic_event,
  sample_rhythm_values,
  num_observations,
  next_rhythm_category,
  -- Flagging specific concerning transitions
  CASE
    WHEN next_rhythm_category IN ('TORSADES_DE_POINTES', 'VENTRICULAR_FIBRILLATION', 'VENTRICULAR_TACHYCARDIA')
      THEN TRUE
    ELSE FALSE
  END AS transitions_to_vt_vf,
  CASE
    WHEN next_rhythm_category IN ('3RD_DEGREE_BLOCK', '2ND_DEGREE_BLOCK')
      THEN TRUE
    ELSE FALSE
  END AS transitions_to_heart_block
FROM segments_with_endpoints
WHERE TIMESTAMP_DIFF(segment_end, segment_start, MINUTE) > 0  -- Only positive duration
ORDER BY stay_id, segment_start;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check 1: Basic counts
SELECT
  COUNT(*) as total_segments,
  COUNT(DISTINCT stay_id) as unique_stays,
  SUM(CASE WHEN is_proarrhythmic_event THEN 1 ELSE 0 END) as proarrhythmic_segments
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`;

-- Check 2: Distribution by rhythm category
SELECT
  rhythm_category,
  COUNT(*) as num_segments,
  COUNT(DISTINCT stay_id) as num_patients,
  ROUND(AVG(duration_hours), 1) as mean_duration_hours
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
GROUP BY rhythm_category
ORDER BY num_segments DESC;

-- Check 3: Proarrhythmic events
SELECT
  rhythm_category,
  severity_level,
  COUNT(*) as num_events,
  COUNT(DISTINCT stay_id) as num_patients
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE is_proarrhythmic_event = TRUE
GROUP BY rhythm_category, severity_level
ORDER BY num_events DESC;

-- Check 4: Concerning rhythm transitions
SELECT
  rhythm_category AS from_rhythm,
  next_rhythm_category AS to_rhythm,
  COUNT(*) as num_transitions,
  COUNT(DISTINCT stay_id) as num_patients
FROM `tactical-grid-454202-h6.mimic_af_electrolytes.rhythm_segments`
WHERE transitions_to_vt_vf = TRUE OR transitions_to_heart_block = TRUE
GROUP BY rhythm_category, next_rhythm_category
ORDER BY num_transitions DESC;
