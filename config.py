"""
Configuration file for MIMIC-IV Atrial Fibrillation Study
"""

# BigQuery Project and Dataset Configuration
PROJECT_ID = "physionet-data"
MIMIC_ICU_DATASET = "mimiciv_3_1_icu"
MIMIC_HOSP_DATASET = "mimiciv_3_1_hosp"
MIMIC_DERIVED_DATASET = "mimiciv_3_1_derived"

# Your project for storing results (update this with your project)
OUTPUT_PROJECT_ID = "tactical-grid-454202-h6"

# Table Names
CHARTEVENTS_TABLE = f"{PROJECT_ID}.{MIMIC_ICU_DATASET}.chartevents"
ICUSTAYS_TABLE = f"{PROJECT_ID}.{MIMIC_ICU_DATASET}.icustays"
D_ITEMS_TABLE = f"{PROJECT_ID}.{MIMIC_ICU_DATASET}.d_items"
INPUTEVENTS_TABLE = f"{PROJECT_ID}.{MIMIC_ICU_DATASET}.inputevents"

ADMISSIONS_TABLE = f"{PROJECT_ID}.{MIMIC_HOSP_DATASET}.admissions"
PATIENTS_TABLE = f"{PROJECT_ID}.{MIMIC_HOSP_DATASET}.patients"
EMAR_TABLE = f"{PROJECT_ID}.{MIMIC_HOSP_DATASET}.emar"
EMAR_DETAIL_TABLE = f"{PROJECT_ID}.{MIMIC_HOSP_DATASET}.emar_detail"

SOFA_TABLE = f"{PROJECT_ID}.{MIMIC_DERIVED_DATASET}.first_day_sofa"
AGE_TABLE = f"{PROJECT_ID}.{MIMIC_DERIVED_DATASET}.age"

# AF Identification Parameters
AF_REGEX = r'(atrial.?fibrillation|a[- ]?fib|afib)'
AFLUTTER_REGEX = r'(atrial.?flutter|a[- ]?flutter|aflutter)'

# Medication Lists
ANTIARRHYTHMIC_MEDS = [
    'amiodarone',
    'ibutilide',
    'procainamide',
    'dofetilide',
    'sotalol',
    'flecainide',
    'propafenone'
]

RATE_CONTROL_MEDS = [
    'metoprolol',
    'esmolol',
    'diltiazem',
    'verapamil',
    'digoxin'
]

# Output Paths
COHORT_OUTPUT_PATH = "outputs/cohorts"
FIGURES_OUTPUT_PATH = "outputs/figures"
DATA_OUTPUT_PATH = "data"

# Analysis Parameters
MIN_AF_DURATION_HOURS = 0.0  # Minimum AF duration to include
EMAR_RELIABLE_START_YEAR = 2016  # Year when eMAR becomes comprehensively available
