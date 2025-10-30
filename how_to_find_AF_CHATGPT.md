Awesome project. Here’s a clean, BigQuery-first recipe you can drop into your workflow to (1) find ICU atrial fibrillation (AF) episodes from bedside charting, (2) time-align antiarrhythmic (and—optionally—rate-control) administrations, and (3) compute AF duration and outcomes (mortality, LOS), all in MIMIC-IV on BigQuery.

---

# 0) Where to query (datasets)

If you were granted BigQuery access via PhysioNet, you’ll see the hosted datasets under the `physionet-data` project (e.g., `mimiciv_v3_1_*` or the rolling `mimiciv_*`). The ICU tables live in `…mimiciv_*_icu`, hospital-wide tables in `…mimiciv_*_hosp`, and the handy derived tables in `…mimiciv_derived` (e.g., SOFA). MIT-LCP maintains these and documents current versions and schemas. ([PhysioNet][1])

Practical note on medication timestamps: barcode-based eMAR (the most precise admin times) is comprehensively available from 2016 onward—useful when you need exact timing around AF episodes. ([Nature][2])

Mortality fields: in-hospital death is indicated in `mimiciv_hosp.admissions.hospital_expire_flag` and date of death (for post-discharge windows) is in `mimiciv_hosp.patients.dod`. ([PhysioNet][3])

---

# 1) High-level design

**AF identification**

* Use ICU `chartevents` (bedside nurse charting). Rhythm is charted as free text values (e.g., “Atrial Fibrillation”, “AFib”). This signal is surprisingly reliable vs ECG review for onset/offset timing at the hour-scale you need. ([PhysioNet][4])

**Antiarrhythmic exposure**

* Pull precise administrations from `hosp.emar_detail` (barcode scans), and continuous infusions from `icu.inputevents` (e.g., amiodarone drips), matching by generic names.

**Duration & outcomes**

* Build rhythm segments (AF vs non-AF) per `stay_id`, compress into episodes, compute duration in hours.
* Outcomes: ICU/hospital mortality, ICU/hospital LOS; optional 30-day mortality via `patients.dod`.

**Confounding**

* Add severity (first-24h SOFA from `mimiciv_derived.sofa`), ventilation/vasopressor exposure, sepsis flags, etc. The `mimiciv_derived` dataset is referenced throughout the official MIT-LCP concepts. ([GitHub][5])

---

# 2) BigQuery: starter SQL blocks

> Replace dataset prefixes below with the ones you see (e.g., `physionet-data.mimiciv_icu` / `physionet-data.mimiciv_hosp` / `physionet-data.mimiciv_derived`). All queries use Standard SQL.

## 2.1 Discover rhythm itemids and AF value strings

This lets you *learn* which `chartevents.itemid` fields carry a rhythm and how AF is spelled locally.

```sql
-- Find likely rhythm itemids and how AF is charted
WITH rhythm_candidates AS (
  SELECT
    ce.itemid,
    di.label AS item_label,
    di.category AS item_category,
    COUNTIF(REGEXP_CONTAINS(LOWER(ce.value), r'(atrial.?fibrillation|a[- ]?fib|afib|a[- ]?flutter|atrial.?flutter)')) AS af_hits,
    COUNT(*) AS n
  FROM `physionet-data.mimiciv_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_icu.d_items` di USING (itemid)
  WHERE ce.value IS NOT NULL
  GROUP BY ce.itemid, item_label, item_category
)
SELECT *
FROM rhythm_candidates
WHERE af_hits > 100  -- tune threshold after first pass
ORDER BY af_hits DESC;
```

## 2.2 Build AF vs non-AF timeline per ICU stay

Use only the itemids you validate from the step above (put them into the `IN (…)` list). This compresses all rhythm charting into contiguous segments and measures AF duration.

```sql
-- PARAMETERS (fill these after 2.1)
DECLARE RHYTHM_ITEMIDS ARRAY<INT64> DEFAULT [/* e.g. 220045, 223257, … */];

WITH rhythm_obs AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    LOWER(ce.value) AS value_lc
  FROM `physionet-data.mimiciv_icu.chartevents` ce
  WHERE ce.itemid IN UNNEST(RHYTHM_ITEMIDS)
    AND ce.charttime IS NOT NULL
),
labeled AS (
  SELECT
    stay_id,
    charttime,
    -- Define AF; include “flutter” if you want to treat AFlutter as AF-equivalent
    REGEXP_CONTAINS(value_lc, r'(atrial.?fibrillation|a[- ]?fib|afib)') AS is_af
  FROM rhythm_obs
),
-- Keep only the first record at each time to avoid duplicate entries
dedup AS (
  SELECT AS VALUE x
  FROM (
    SELECT ARRAY_AGG(l ORDER BY l.charttime LIMIT 1)[OFFSET(0)] AS x
    FROM labeled l
    GROUP BY l.stay_id, l.charttime
  )
),
segmented AS (
  SELECT
    stay_id,
    charttime,
    is_af,
    -- new segment whenever the label switches
    SUM(CASE WHEN is_af != LAG(is_af) OVER w OR LAG(is_af) OVER w IS NULL THEN 1 ELSE 0 END)
      OVER (PARTITION BY stay_id ORDER BY charttime) AS seg_id
  FROM dedup
  WINDOW w AS (PARTITION BY stay_id ORDER BY charttime)
),
segments AS (
  SELECT
    stay_id,
    seg_id,
    ANY_VALUE(is_af) AS is_af,
    MIN(charttime) AS seg_start,
    -- segment ends when the next segment starts
    LEAD(MIN(charttime)) OVER (PARTITION BY stay_id ORDER BY MIN(charttime)) AS seg_end
  FROM segmented
  GROUP BY stay_id, seg_id
),
af_episodes AS (
  -- keep AF-only segments, impute seg_end with ICU outtime
  SELECT
    s.stay_id,
    s.seg_start AS af_start,
    COALESCE(s.seg_end, i.outtime) AS af_end,
    TIMESTAMP_DIFF(COALESCE(s.seg_end, i.outtime), s.seg_start, MINUTE)/60.0 AS af_hours
  FROM segments s
  JOIN `physionet-data.mimiciv_icu.icustays` i USING (stay_id)
  WHERE s.is_af = TRUE
)
SELECT * FROM af_episodes
WHERE af_hours > 0.0
ORDER BY stay_id, af_start;
```

> Tip: If charting is sparse you can merge AF segments separated by short gaps (e.g., <2 h) by adding a gap-bridging step, but start simple.

## 2.3 Capture antiarrhythmic (and optional rate-control) administrations

Barcode-scanned **eMAR** gives exact admin times; ICU **inputevents** give drip windows. We’ll match on generic strings; tweak the lists to your taste.

```sql
-- Concept lists (edit as needed)
DECLARE AA_RX ARRAY<STRING> DEFAULT [
  'amiodarone','ibutilide','procainamide','dofetilide','sotalol','flecainide','propafenone'
];
DECLARE RATE_RX ARRAY<STRING> DEFAULT [
  'metoprolol','esmolol','diltiazem','verapamil','digoxin'
];

-- eMAR (precise doses)
WITH emar AS (
  SELECT
    e.subject_id, e.hadm_id, e.charttime AS admin_time,
    LOWER(ed.medication) AS med_string
  FROM `physionet-data.mimiciv_hosp.emar` e
  JOIN `physionet-data.mimiciv_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
  WHERE e.charttime IS NOT NULL
),
emar_aa AS (
  SELECT subject_id, hadm_id, admin_time, med_string, 'AA' AS drug_class
  FROM emar
  WHERE EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE med_string LIKE CONCAT('%', g, '%'))
),
emar_rate AS (
  SELECT subject_id, hadm_id, admin_time, med_string, 'RATE' AS drug_class
  FROM emar
  WHERE EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE med_string LIKE CONCAT('%', g, '%'))
),

-- ICU drips (e.g., amiodarone infusions)
icu_drips AS (
  SELECT
    ie.subject_id, i.hadm_id, ie.stay_id,
    ie.starttime, ie.endtime,
    LOWER(di.label) AS item_label
  FROM `physionet-data.mimiciv_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_icu.icustays` i USING (stay_id)
  JOIN `physionet-data.mimiciv_icu.d_items` di ON ie.itemid = di.itemid
  WHERE (EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE di.label LIKE CONCAT('%', g, '%'))
         OR EXISTS (SELECT 1 FROM UNNEST(RATE_RX) g WHERE di.label LIKE CONCAT('%', g, '%')))
),

meds_union AS (
  -- Normalize into point-in-time events; for drips we’ll overlap by window
  SELECT subject_id, hadm_id, NULL AS stay_id, admin_time AS t_start, admin_time AS t_end,
         med_string AS med_name, drug_class
  FROM emar_aa
  UNION ALL
  SELECT subject_id, hadm_id, NULL, admin_time, admin_time, med_string, drug_class
  FROM emar_rate

  UNION ALL
  SELECT subject_id, hadm_id, stay_id, starttime, endtime,
         item_label AS med_name,
         CASE
           WHEN EXISTS (SELECT 1 FROM UNNEST(AA_RX) g WHERE item_label LIKE CONCAT('%', g, '%')) THEN 'AA'
           ELSE 'RATE'
         END AS drug_class
  FROM icu_drips
)
SELECT * FROM meds_union;
```

## 2.4 Join meds to AF episodes (overlap logic) and add outcomes

This returns AF episode–level rows with the drugs given during the episode and basic outcomes.

```sql
WITH af AS ( /* 2.2 query */ ),
meds AS ( /* 2.3 query */ ),

af_meds AS (
  SELECT
    i.subject_id, i.hadm_id, a.stay_id,
    a.af_start, a.af_end, a.af_hours,
    m.med_name, m.drug_class,
    -- first dose time within this episode (NULL for drips if no overlap)
    MIN(CASE WHEN m.t_start BETWEEN a.af_start AND a.af_end THEN m.t_start END) AS first_admin_time,
    -- any drip overlapping the episode
    COUNTIF( (m.t_start <= a.af_end) AND (COALESCE(m.t_end, m.t_start) >= a.af_start) AND m.stay_id = a.stay_id ) > 0 AS any_drip_overlap
  FROM af a
  JOIN `physionet-data.mimiciv_icu.icustays` i USING (stay_id)
  LEFT JOIN meds m
    ON m.subject_id = i.subject_id AND m.hadm_id = i.hadm_id
       AND (m.t_start <= a.af_end) AND (COALESCE(m.t_end, m.t_start) >= a.af_start)
  GROUP BY i.subject_id, i.hadm_id, a.stay_id, a.af_start, a.af_end, a.af_hours, m.med_name, m.drug_class
),

outcomes AS (
  SELECT
    ad.subject_id, ad.hadm_id,
    ad.hospital_expire_flag,
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR)/24.0 AS hosp_los_days
  FROM `physionet-data.mimiciv_hosp.admissions` ad
),

severity AS (
  -- first-24h SOFA (if available in derived)
  SELECT stay_id, MAX(sofa) AS sofa_24h
  FROM `physionet-data.mimiciv_derived.sofa`
  GROUP BY stay_id
)

SELECT
  am.*,
  o.hospital_expire_flag,
  o.hosp_los_days,
  sv.sofa_24h
FROM af_meds am
LEFT JOIN outcomes o USING (subject_id, hadm_id)
LEFT JOIN severity sv USING (stay_id)
ORDER BY stay_id, af_start, med_name;
```

**Add a “conversion” endpoint (optional):** define *conversion to sinus* = first non-AF segment start time after `af_start`. You can compute a boolean “converted within 24 h” by comparing that timestamp to `af_start`. (Reuse the `segments` CTE and `LEAD()` logic above.)

---

# 3) Analysis sketch

* **Primary exposure:** any *antiarrhythmic* given during AF (or within X minutes of AF start). Optionally build mutually exclusive groups: *AA only*, *rate-control only*, *both*, *neither*.
* **Primary outcomes:** in-hospital mortality, ICU/hospital LOS, conversion within 24 h, AF total duration.
* **Adjustment variables:** age, sex, admission type, first-24h SOFA, ventilation, vasopressors, sepsis; anchor to first AF episode per stay to avoid clustering, or use GEE/mixed models downstream.
* **Stats:** export the AF-episode table to your notebook, or use BigQuery ML for quick logistic models on mortality.

---

# 4) Validation & pitfalls (worth planning up front)

* **AF labeling quality:** nurse-charted rhythm is a strong signal for AF onset/offset at ~hour resolution; still, audit a small random sample by reading notes/ECG reports to estimate PPV/NPV for your regex. ([biosignal.uconn.edu][6])
* **Medication timing coverage:** eMAR is richest from 2016+, so (a) restrict to hadm_id ≥2016 entries for exact timing analyses or (b) do sensitivity analyses (full cohort vs 2016+ subset). ([Nature][2])
* **New-onset vs pre-existing AF:** to approximate NOAF, exclude AF charted in the first 2 ICU hours **and** discharges carrying AF ICD codes from prior admissions; compare with published NOAF phenotypes on MIMIC-IV. ([PMC][7])
* **De-identification time shifting:** absolute dates are shifted, but within-stay ordering is intact—compute durations using timestamps, not calendar dates. (Standard MIMIC guidance.) ([Nature][2])

---

# 5) What others did (for ideas & references)

* **NOAF risk / timing models in ICU with MIMIC-IV**—good for phenotype/feature ideas and for how they handle confounding. ([PMC][7])
* **eMAR explanation & coverage**—why we prefer it for med timing. ([Nature][2])
* **Dataset/version pointers & derived tables**—where to find SOFA, etc., on BigQuery. ([PhysioNet][1])

---

# 6) Cost/speed hygiene on BigQuery

* Always `SELECT` only columns you need and **filter by ICU windows** (use `icustays.intime/outtime`) before joining large tables.
* Develop against the **MIMIC-IV demo** (100 patients) to check logic. ([PhysioNet][8])
* Materialize intermediate cohorts in your own project as clustered, partitioned tables on `stay_id`/`charttime` for iterative work.

---

If you want, I can adapt the SQL above to:

* your exact dataset names on BigQuery,
* a stricter AF regex built from what your local `d_items` reveals, and
* a mutually exclusive exposure framework (AA vs rate-control) with a ready-to-export analytic table.

[1]: https://physionet.org/news/post/mimic-iv-v3-1-on-bigquery?utm_source=chatgpt.com "MIMIC-IV v3.1 is now available on BigQuery"
[2]: https://www.nature.com/articles/s41597-022-01899-x?utm_source=chatgpt.com "MIMIC-IV, a freely accessible electronic health record dataset"
[3]: https://physionet.org/content/mimic-iv-demo/1.0/core/admissions.csv.gz?utm_source=chatgpt.com "admissions.csv.gz - MIMIC-IV Clinical Database Demo"
[4]: https://physionet.org/content/mimiciv/?utm_source=chatgpt.com "MIMIC-IV v3.1"
[5]: https://github.com/MIT-LCP/mimic-code/discussions/1845?utm_source=chatgpt.com "MIMIC-IV-3.1 don`t have the derived table? #1845"
[6]: https://biosignal.uconn.edu/wp-content/uploads/sites/2503/2019/08/05_Ding_2019_JIntCare.pdf?utm_source=chatgpt.com "Novel Method of Atrial Fibrillation Case Identification and ..."
[7]: https://pmc.ncbi.nlm.nih.gov/articles/PMC11523862/?utm_source=chatgpt.com "Interpretable machine learning model for new-onset atrial ..."
[8]: https://physionet.org/content/mimic-iv-demo/?utm_source=chatgpt.com "MIMIC-IV Clinical Database Demo v2.2"
