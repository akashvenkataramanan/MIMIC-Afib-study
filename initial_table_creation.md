import bigframes.pandas as bpd
# sql_engine: bigquery
# output_variable: df
# start _sql
_sql = """
-- Making the table
CREATE OR REPLACE TABLE `tactical-grid-454202-h6.mimic_af_electrolytes.af_episodes` AS

--Identifying the label IDs which are stored in the itemid column of icu.d_items
WITH rhythm_itemids AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE LOWER(label) IN ('rhythm', 'heart rhythm')
),

--This creates a table which takes the itemids from the above step, takes chart items with those itemids, throws out the rows where either the value is null or charttime is nulll
--and puts the values in lower case as value_lc as a new column in this temporary table
rhythm_obs AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE ce.itemid IN (SELECT itemid FROM rhythm_itemids)
    AND ce.value IS NOT NULL
    AND ce.charttime iS NOT NULL
),

--labelling as Atrial fibrillation or no atrial fibrillation
labeled AS (
  SELECT
    stay_id,
    charttime,
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]fib|afib)') AS is_af,
    value_lc as rhythm_value
  FROM rhythm_obs
),

--removing duplicate observations
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

-- find out where the rhythm changes - first calculate LAG
lagged_dedup AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    rhythm_value,
    LAG(is_af) OVER (PARTITION BY stay_id ORDER BY charttime) AS prev_is_af
  FROM dedup
),
segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    rhythm_value,
    SUM(CASE
    WHEN is_af != prev_is_af
      OR prev_is_af IS NULL
    THEN 1
    ELSE 0
    END) OVER (PARTITION BY stay_id ORDER BY charttime) AS segment_id
  FROM lagged_dedup
),

--Find out the AF episodes by segment id. So here, we collapse the rows to get a single row that shows the duration of the segment and whether it was AF or not AF.
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

--ICU boundaries - sets the end time to ICU discharge.
af_episodes_raw AS (
  SELECT
    seg.stay_id,
    seg.segment_start AS af_start,
    --AF ends at next observation or ICU discharge
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

-- Final table: AF episodes with duration and episode number
SELECT
  stay_id,
  af_start,
  af_end,
  TIMESTAMP_DIFF(af_end, af_start, MINUTE)/60.0 AS af_duration_hours,
  ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY af_start) AS episode_number,
  num_observations
FROM af_episodes_raw
WHERE TIMESTAMP_DIFF(af_end, af_start, MINUTE) > 0
ORDER BY stay_id, af_start;

""" # end _sql
from google.colab.sql import bigquery as _bqsqlcell
df = _bqsqlcell.run(_sql)
df