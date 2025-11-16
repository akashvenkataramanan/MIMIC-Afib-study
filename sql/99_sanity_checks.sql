-- Sanity checks and quick explorations

-- 1) How many unique stays and CV events?
SELECT
  COUNT(*) AS n_rows,
  COUNT(DISTINCT stay_id) AS n_stays,
  COUNT(DISTINCT FORMAT('%d|%d|%d|%s', subject_id, hadm_id, stay_id, cv_time)) AS n_distinct_cv
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib`;

-- 2) Check for duplicate CV rows (exact duplicates)
SELECT
  subject_id, hadm_id, stay_id, cv_time, cv_endtime,
  COUNT(*) AS dup_count
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib`
GROUP BY subject_id, hadm_id, stay_id, cv_time, cv_endtime
HAVING COUNT(*) > 1
ORDER BY dup_count DESC;

-- 3) Confirm lab table join cardinality
SELECT COUNT(*) AS n_labs24
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_labs24`;

-- 4) Quick distribution of potassium/magnesium bins
SELECT potassium_bin, COUNT(*) AS n
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_labs24`
GROUP BY potassium_bin
ORDER BY n DESC;

SELECT magnesium_bin, COUNT(*) AS n
FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib_labs24`
GROUP BY magnesium_bin
ORDER BY n DESC;

-- 5) Minimum minutes to nearest arrest per stay (sanity compare against notes)
SELECT
  COUNT(*) AS n_stays,
  SUM(CASE WHEN min_mins <= 120 THEN 1 ELSE 0 END) AS n_stays_arrest_within_2h
FROM (
  SELECT stay_id, MIN(mins_to_nearest_arrest) AS min_mins
  FROM `{{PROJECT}}.{{DATASET}}.cv_for_afib`
  GROUP BY stay_id
);
