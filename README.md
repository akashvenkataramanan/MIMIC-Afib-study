MIMIC AFib Cardioversion Study — Reusable SQL Scripts

Overview
- This repo organizes the ad‑hoc notes in `prior_AF_CV_SCRIPT.md` into reusable, commented BigQuery SQL scripts for the AFib cardioversion analysis on MIMIC-IV.
- Scripts are parameterized via simple placeholders to avoid hard‑coding your project/dataset names.

What’s Included
- `sql/10_deduplicate_cv_for_afib.sql`: Removes duplicate rows in the cardioversion cohort table.
- `sql/20_labs_within_24h.sql`: Adds most-recent potassium and magnesium within 24 hours before cardioversion.
- `sql/30_rhythm_10_14h.sql`: Classifies rhythm between 10–14 hours post-cardioversion with naive and censored windows.
- `scripts/render_sql.py`: Tiny renderer to substitute placeholders like `{{PROJECT}}` and `{{DATASET}}`.

Full, defaulted (no placeholders) versions live in `sql_full/`:
- `01_admitted_with_af_or_aflutter.sql`: ICU stays admitted with AF or AFlutter using first rhythm within 2h of ICU intime.
- `05_build_af_episodes.sql`: AF-only episode segmentation (kept for reference; optional).
- `06_build_af_or_aflutter_episodes.sql`: Combined AF/AFlutter episodes (preferred for downstream consistency).
- `10_deduplicate_cv_for_afib.sql`, `20_labs_within_24h.sql`, `30_rhythm_10_14h.sql`, `35_rhythm_10_14h_summary.sql`, `40_join_labs_rhythm.sql`, `60_k_mg_vs_rhythm_10_14h.sql`.
- `00_run_all.sql`: Runs all `sql_full` steps in order.

Assumptions
- You have an existing cardioversion cohort table at `{{PROJECT}}.{{DATASET}}.cv_for_afib` with at least: `subject_id, hadm_id, stay_id, cv_time, cv_endtime, location, locationcategory, ordercategoryname, ordercategorydescription, statusdescription, cv_inside_af_episode, has_nearby_arrest, mins_to_nearest_arrest, shock_type_label`.
- Source MIMIC-IV tables are read from `physionet-data` (public), with versions `mimiciv_3_1_hosp`, `mimiciv_3_1_icu`.

Placeholders
- `{{PROJECT}}`: Your GCP project (e.g., `tactical-grid-454202-h6`).
- `{{DATASET}}`: Your dataset (e.g., `mimic_af_electrolytes`).

How To Use
1) Render a script by replacing placeholders, then run with `bq` or the BigQuery UI.
   - Option A: Quick manual replace
     - Open the SQL file, replace `{{PROJECT}}` and `{{DATASET}}` with your values, paste into BigQuery Console.
   - Option B: Use the renderer
     - `python3 scripts/render_sql.py sql/20_labs_within_24h.sql --project YOUR_PROJECT --dataset YOUR_DATASET > /tmp/20_labs.sql`
     - `bq query --use_legacy_sql=false < /tmp/20_labs.sql`

Suggested Order
- (Optional) Build episodes: prefer `06_build_af_or_aflutter_episodes.sql`; `05_build_af_episodes.sql` is AF-only reference.
- Identify admissions with AF/AFlutter: `01_admitted_with_af_or_aflutter.sql`.
- Cardioversion flow: `10_deduplicate_cv_for_afib.sql` → `20_labs_within_24h.sql` → `30_rhythm_10_14h.sql` → `40_join_labs_rhythm.sql` → `60_k_mg_vs_rhythm_10_14h.sql`.

ItemIDs Reference (from notes)
- Rhythm (CHARTEVENTS) `itemid = 220048`
- Cardioversion (PROCEDUREEVENTS) `itemid = 225464`
- Cardiac arrest (PROCEDUREEVENTS) `itemid = 225466`
- Potassium (LABEVENTS): `itemid IN (50971, 52610)`; `valueuom = 'mEq/L'`
- Magnesium (LABEVENTS): `itemid = 50960`; `valueuom = 'mg/dL'`

Notes
- The earlier COALESCE-based segmentation that mis-labeled AF segments is not included here. Keep using the fixed segmentation that uses explicit segment end (`seg.segment_end`) where applicable.
- The 10–14h rhythm window has both naive and censored interpretations to mitigate bias from ICU discharge or subsequent cardioversion.
- Downstream analyses group AF and Atrial Flutter together. Where possible, use the combined tables (`af_or_aflutter_episodes`, `admitted_with_af_or_aflutter`). When you provide the exact distinct charted rhythm strings for itemid 220048, we can replace regex with exact‑match label lists.
