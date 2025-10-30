-- Query 1: Discover Rhythm ItemIDs
-- This query identifies which itemid values in chartevents contain rhythm information
-- Run this first to determine which itemids to use for AF detection

WITH rhythm_candidates AS (
  SELECT
    ce.itemid,
    di.label AS item_label,
    di.category AS item_category,
    COUNTIF(REGEXP_CONTAINS(LOWER(ce.value), r'(atrial.?fibrillation|a[- ]?fib|afib|atrial.?flutter|a[- ]?flutter)')) AS af_hits,
    COUNT(*) AS total_count,
    ROUND(COUNTIF(REGEXP_CONTAINS(LOWER(ce.value), r'(atrial.?fibrillation|a[- ]?fib|afib)')) / COUNT(*) * 100, 2) AS af_percentage
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di USING (itemid)
  WHERE ce.value IS NOT NULL
  GROUP BY ce.itemid, item_label, item_category
)
SELECT *
FROM rhythm_candidates
WHERE af_hits > 100
ORDER BY af_hits DESC
LIMIT 50;
