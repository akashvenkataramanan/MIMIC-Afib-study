-- Query 7: Comprehensive Rhythm Classification Schema
-- This defines the complete classification system for all cardiac rhythms
-- Priority: Proarrhythmic events from antiarrhythmic drugs (VT, VF, blocks, bradycardia)
--
-- Based on:
-- - AHA/ACC/HRS 2017 Guidelines for Ventricular Arrhythmias
-- - Antiarrhythmic drug proarrhythmic effects (StatPearls, AHA 2024)
-- - ICU telemetry rhythm documentation standards

-- This is a reference query showing the classification logic
-- Use this CASE statement in your rhythm analysis queries

WITH example_rhythms AS (
  -- This CTE would contain your actual rhythm observations
  SELECT
    'atrial fibrillation' AS rhythm_value,
    1 AS example_id
  UNION ALL SELECT 'sinus rhythm', 2
  UNION ALL SELECT 'v tach', 3
)

SELECT
  rhythm_value,

  -- PRIMARY CLASSIFICATION (hierarchical - order matters!)
  CASE
    -- ==================================================================
    -- PRIORITY 1: LIFE-THREATENING VENTRICULAR ARRHYTHMIAS
    -- (Proarrhythmic effects of Class Ia, Ic, III antiarrhythmics)
    -- ==================================================================

    -- Torsades de Pointes (polymorphic VT with QT prolongation)
    -- Risk: Class Ia (quinidine, procainamide), Class III (sotalol, dofetilide, ibutilide)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|torsades)')
      THEN 'TORSADES_DE_POINTES'

    -- Ventricular Fibrillation
    -- Risk: All antiarrhythmics in proarrhythmic setting
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?fib|ventricular.?fib(rillation)?|vf\b)')
      THEN 'VENTRICULAR_FIBRILLATION'

    -- Ventricular Tachycardia (monomorphic or unspecified)
    -- Risk: Class Ic (flecainide, propafenone) especially with structural heart disease
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?tach|ventricular.?tach(ycardia)?|vt\b|polymorphic|monomorphic)')
      THEN 'VENTRICULAR_TACHYCARDIA'

    -- Idioventricular Rhythm (wide complex escape rhythm)
    -- Can indicate severe conduction disease or antiarrhythmic toxicity
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)idioventricular')
      THEN 'IDIOVENTRICULAR'

    -- ==================================================================
    -- PRIORITY 2: HEART BLOCKS (Conduction System Toxicity)
    -- (Proarrhythmic effects of Class Ia, Ic, IV drugs)
    -- ==================================================================

    -- Third Degree / Complete Heart Block
    -- Risk: Class Ia, Ic, IV (verapamil, diltiazem), beta-blockers
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(3rd.?degree|third.?degree|complete.?(heart.?)?block|chb)')
      THEN '3RD_DEGREE_BLOCK'

    -- Second Degree Heart Block (Mobitz I or II, or unspecified)
    -- Risk: Class Ia, Ic, IV, beta-blockers, digoxin
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(2nd.?degree|second.?degree|mobitz|wenckebach)')
      THEN '2ND_DEGREE_BLOCK'

    -- General AV Block (when degree not specified)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(av.?block|a-v.?block|heart.?block)')
      THEN 'AV_BLOCK_UNSPECIFIED'

    -- First Degree Heart Block (prolonged PR, usually benign)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(1st.?degree|first.?degree)')
      THEN '1ST_DEGREE_BLOCK'

    -- ==================================================================
    -- PRIORITY 3: SEVERE BRADYCARDIA
    -- (Side effect of beta-blockers, CCBs, digoxin, amiodarone)
    -- ==================================================================

    -- Sinus Bradycardia
    -- Risk: Beta-blockers (metoprolol, esmolol), CCBs, digoxin, amiodarone
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)sinus.?brad')
      THEN 'SINUS_BRADYCARDIA'

    -- General Bradycardia (when mechanism not specified)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)brad')
      THEN 'BRADYCARDIA'

    -- ==================================================================
    -- PRIORITY 4: ATRIAL FIBRILLATION & FLUTTER (Target Arrhythmias)
    -- ==================================================================

    -- Atrial Fibrillation (primary arrhythmia being treated)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?fibrillation|a[- ]?fib\b|afib|af\b)')
      THEN 'ATRIAL_FIBRILLATION'

    -- Atrial Flutter (can occur paradoxically with Class Ic drugs)
    -- "Pseudo-atrial flutter" / organized atrial activity with 1:1 conduction
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?flutter|a[- ]?flutter\b|aflutter)')
      THEN 'ATRIAL_FLUTTER'

    -- Rapid Ventricular Response (AFib/Flutter with RVR)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(rvr|rapid.?ventricular)')
      THEN 'RAPID_VENTRICULAR_RESPONSE'

    -- ==================================================================
    -- PRIORITY 5: OTHER SUPRAVENTRICULAR ARRHYTHMIAS
    -- ==================================================================

    -- Supraventricular Tachycardia (narrow complex tachycardia)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(svt|supraventricular.?tach)')
      THEN 'SVT'

    -- Atrial Tachycardia (organized atrial rhythm >100 bpm)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)atrial.?tach')
      THEN 'ATRIAL_TACHYCARDIA'

    -- ==================================================================
    -- PRIORITY 6: JUNCTIONAL RHYTHMS
    -- (Can indicate AV node dysfunction from drugs)
    -- ==================================================================

    -- Junctional Tachycardia
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)junctional.?tach')
      THEN 'JUNCTIONAL_TACHYCARDIA'

    -- Junctional Rhythm / Escape Rhythm
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)junctional')
      THEN 'JUNCTIONAL'

    -- ==================================================================
    -- PRIORITY 7: NORMAL SINUS RHYTHMS
    -- ==================================================================

    -- Sinus Tachycardia (physiologic or inappropriate)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)sinus.?tach')
      THEN 'SINUS_TACHYCARDIA'

    -- Normal Sinus Rhythm (goal rhythm for AF treatment)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(normal.?sinus|sinus.?rhythm|nsr)')
      THEN 'SINUS_RHYTHM'

    -- ==================================================================
    -- PRIORITY 8: PACED RHYTHMS
    -- ==================================================================

    -- AV Sequential Pacing (dual chamber)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(av.?paced|a-v.?paced|dual.?chamber.?pac)')
      THEN 'AV_PACED'

    -- Ventricular Paced
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v.?paced|ventricular.?pac)')
      THEN 'V_PACED'

    -- Atrial Paced
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(a.?paced|atrial.?pac)')
      THEN 'A_PACED'

    -- General Paced Rhythm
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(paced|pacing|pacer)')
      THEN 'PACED'

    -- ==================================================================
    -- PRIORITY 9: OTHER CLINICAL EVENTS
    -- ==================================================================

    -- Asystole (cardiac arrest)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)asystole')
      THEN 'ASYSTOLE'

    -- Premature Ventricular Contractions (ectopy)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(pvc|premature.?ventricular)')
      THEN 'PVC'

    -- Premature Atrial Contractions (ectopy)
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(pac|premature.?atrial)')
      THEN 'PAC'

    -- ==================================================================
    -- DEFAULT: UNCLASSIFIED
    -- ==================================================================
    ELSE 'OTHER_UNCLASSIFIED'
  END AS rhythm_category,

  -- CLINICAL SEVERITY CLASSIFICATION
  CASE
    -- Life-threatening: Requires immediate intervention
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|v[- ]?fib|ventricular.?fib|asystole)')
      THEN 'LIFE_THREATENING'

    -- Critical: Serious arrhythmia requiring urgent treatment
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(v[- ]?tach|ventricular.?tach|3rd.?degree|third.?degree|complete.?block)')
      THEN 'CRITICAL'

    -- Warning: Concerning rhythm suggesting drug toxicity
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(2nd.?degree|mobitz|av.?block|idioventricular|sinus.?brad)')
      THEN 'WARNING'

    -- Monitored: Arrhythmia being treated (AF) or physiologic response
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial.?fib|atrial.?flutter|sinus.?tach)')
      THEN 'MONITORED'

    -- Normal: Desired rhythm
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(normal.?sinus|sinus.?rhythm|nsr)')
      THEN 'NORMAL'

    -- Other
    ELSE 'OTHER'
  END AS severity_level,

  -- PROARRHYTHMIC FLAG (specific to antiarrhythmic side effects)
  CASE
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(torsade|v[- ]?fib|v[- ]?tach|ventricular|3rd.?degree|2nd.?degree|complete.?block|av.?block|idioventricular)')
      THEN TRUE
    ELSE FALSE
  END AS is_proarrhythmic_event,

  -- RHYTHM ORIGIN (anatomical classification)
  CASE
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(atrial|sinus)') THEN 'ATRIAL'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)junctional') THEN 'JUNCTIONAL'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(ventricular|idioventricular)') THEN 'VENTRICULAR'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)(av.?block|heart.?block)') THEN 'AV_NODE'
    WHEN REGEXP_CONTAINS(rhythm_value, r'(?i)pac') THEN 'PACED'
    ELSE 'UNKNOWN'
  END AS rhythm_origin

FROM example_rhythms;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- 1. COPY the rhythm_category CASE statement into your analysis queries
--
-- 2. PRIORITY ORDER MATTERS: More specific patterns must come first
--    (e.g., "sinus bradycardia" before "bradycardia")
--
-- 3. REGEX PATTERNS use (?i) for case-insensitive matching
--
-- 4. CLINICAL INTERPRETATION:
--    - LIFE_THREATENING: VF, Torsades, Asystole → Immediate code/ACLS
--    - CRITICAL: VT, 3rd degree block → Urgent intervention
--    - WARNING: 2nd degree block, severe bradycardia → Drug toxicity
--    - MONITORED: AF, AFl → Target arrhythmias being treated
--    - NORMAL: Sinus rhythm → Successful treatment
--
-- 5. ANTIARRHYTHMIC DRUG ASSOCIATIONS:
--    - Torsades: Class Ia (quinidine, procainamide), Class III (sotalol, dofetilide)
--    - VT: Class Ic (flecainide, propafenone) in structural heart disease
--    - Heart blocks: Class Ia, Ic, IV (CCBs), beta-blockers
--    - Bradycardia: Beta-blockers, CCBs, digoxin, amiodarone
--
-- ============================================================================
