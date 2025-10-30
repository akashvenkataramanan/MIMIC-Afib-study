"""
Comprehensive Cardiac Rhythm Classification Module

This module provides Python functions to classify cardiac rhythms from MIMIC-IV
bedside telemetry data, with emphasis on proarrhythmic events from antiarrhythmic drugs.

Usage:
    from rhythm_classifier import classify_rhythm, classify_rhythm_df

    # Single rhythm
    result = classify_rhythm("ventricular tachycardia")

    # DataFrame with multiple rhythms
    import pandas as pd
    df['rhythm_category'] = df['rhythm_value'].apply(
        lambda x: classify_rhythm(x)['rhythm_category']
    )
"""

import re
from typing import Dict, Optional
import pandas as pd


def classify_rhythm(rhythm_value: str) -> Dict[str, any]:
    """
    Classify a single rhythm observation into clinical categories.

    Parameters
    ----------
    rhythm_value : str
        The raw rhythm text from bedside charting (e.g., "atrial fibrillation")

    Returns
    -------
    dict
        Dictionary containing:
        - rhythm_category: Primary rhythm classification
        - severity_level: Clinical severity (LIFE_THREATENING to NORMAL)
        - is_proarrhythmic_event: Boolean flag for antiarrhythmic drug toxicity
        - rhythm_origin: Anatomical origin (ATRIAL, JUNCTIONAL, VENTRICULAR, etc.)

    Examples
    --------
    >>> classify_rhythm("atrial fibrillation")
    {'rhythm_category': 'ATRIAL_FIBRILLATION', 'severity_level': 'MONITORED',
     'is_proarrhythmic_event': False, 'rhythm_origin': 'ATRIAL'}

    >>> classify_rhythm("torsades de pointes")
    {'rhythm_category': 'TORSADES_DE_POINTES', 'severity_level': 'LIFE_THREATENING',
     'is_proarrhythmic_event': True, 'rhythm_origin': 'VENTRICULAR'}
    """
    if not rhythm_value or not isinstance(rhythm_value, str):
        return {
            'rhythm_category': 'OTHER_UNCLASSIFIED',
            'severity_level': 'OTHER',
            'is_proarrhythmic_event': False,
            'rhythm_origin': 'UNKNOWN'
        }

    # Normalize: lowercase and strip whitespace
    rv = rhythm_value.lower().strip()

    # ==================================================================
    # PRIORITY 1: LIFE-THREATENING VENTRICULAR ARRHYTHMIAS
    # ==================================================================

    if re.search(r'(torsade|torsades)', rv, re.IGNORECASE):
        rhythm_category = 'TORSADES_DE_POINTES'
        severity_level = 'LIFE_THREATENING'
        is_proarrhythmic = True
        rhythm_origin = 'VENTRICULAR'

    elif re.search(r'(v[- ]?fib|ventricular.?fib(rillation)?|vf\b)', rv, re.IGNORECASE):
        rhythm_category = 'VENTRICULAR_FIBRILLATION'
        severity_level = 'LIFE_THREATENING'
        is_proarrhythmic = True
        rhythm_origin = 'VENTRICULAR'

    elif re.search(r'(v[- ]?tach|ventricular.?tach(ycardia)?|vt\b|polymorphic|monomorphic)', rv, re.IGNORECASE):
        rhythm_category = 'VENTRICULAR_TACHYCARDIA'
        severity_level = 'CRITICAL'
        is_proarrhythmic = True
        rhythm_origin = 'VENTRICULAR'

    elif re.search(r'idioventricular', rv, re.IGNORECASE):
        rhythm_category = 'IDIOVENTRICULAR'
        severity_level = 'CRITICAL'
        is_proarrhythmic = True
        rhythm_origin = 'VENTRICULAR'

    # ==================================================================
    # PRIORITY 2: HEART BLOCKS
    # ==================================================================

    elif re.search(r'(3rd.?degree|third.?degree|complete.?(heart.?)?block|chb)', rv, re.IGNORECASE):
        rhythm_category = '3RD_DEGREE_BLOCK'
        severity_level = 'CRITICAL'
        is_proarrhythmic = True
        rhythm_origin = 'AV_NODE'

    elif re.search(r'(2nd.?degree|second.?degree|mobitz|wenckebach)', rv, re.IGNORECASE):
        rhythm_category = '2ND_DEGREE_BLOCK'
        severity_level = 'WARNING'
        is_proarrhythmic = True
        rhythm_origin = 'AV_NODE'

    elif re.search(r'(av.?block|a-v.?block|heart.?block)', rv, re.IGNORECASE):
        rhythm_category = 'AV_BLOCK_UNSPECIFIED'
        severity_level = 'WARNING'
        is_proarrhythmic = True
        rhythm_origin = 'AV_NODE'

    elif re.search(r'(1st.?degree|first.?degree)', rv, re.IGNORECASE):
        rhythm_category = '1ST_DEGREE_BLOCK'
        severity_level = 'WARNING'
        is_proarrhythmic = False
        rhythm_origin = 'AV_NODE'

    # ==================================================================
    # PRIORITY 3: SEVERE BRADYCARDIA
    # ==================================================================

    elif re.search(r'sinus.?brad', rv, re.IGNORECASE):
        rhythm_category = 'SINUS_BRADYCARDIA'
        severity_level = 'WARNING'
        is_proarrhythmic = True
        rhythm_origin = 'ATRIAL'

    elif re.search(r'brad', rv, re.IGNORECASE):
        rhythm_category = 'BRADYCARDIA'
        severity_level = 'WARNING'
        is_proarrhythmic = True
        rhythm_origin = 'UNKNOWN'

    # ==================================================================
    # PRIORITY 4: ATRIAL FIBRILLATION & FLUTTER
    # ==================================================================

    elif re.search(r'(atrial.?fibrillation|a[- ]?fib\b|afib|af\b)', rv, re.IGNORECASE):
        rhythm_category = 'ATRIAL_FIBRILLATION'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    elif re.search(r'(atrial.?flutter|a[- ]?flutter\b|aflutter)', rv, re.IGNORECASE):
        rhythm_category = 'ATRIAL_FLUTTER'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    elif re.search(r'(rvr|rapid.?ventricular)', rv, re.IGNORECASE):
        rhythm_category = 'RAPID_VENTRICULAR_RESPONSE'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    # ==================================================================
    # PRIORITY 5: OTHER SUPRAVENTRICULAR ARRHYTHMIAS
    # ==================================================================

    elif re.search(r'(svt|supraventricular.?tach)', rv, re.IGNORECASE):
        rhythm_category = 'SVT'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    elif re.search(r'atrial.?tach', rv, re.IGNORECASE):
        rhythm_category = 'ATRIAL_TACHYCARDIA'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    # ==================================================================
    # PRIORITY 6: JUNCTIONAL RHYTHMS
    # ==================================================================

    elif re.search(r'junctional.?tach', rv, re.IGNORECASE):
        rhythm_category = 'JUNCTIONAL_TACHYCARDIA'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'JUNCTIONAL'

    elif re.search(r'junctional', rv, re.IGNORECASE):
        rhythm_category = 'JUNCTIONAL'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'JUNCTIONAL'

    # ==================================================================
    # PRIORITY 7: NORMAL SINUS RHYTHMS
    # ==================================================================

    elif re.search(r'sinus.?tach', rv, re.IGNORECASE):
        rhythm_category = 'SINUS_TACHYCARDIA'
        severity_level = 'MONITORED'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    elif re.search(r'(normal.?sinus|sinus.?rhythm|nsr)', rv, re.IGNORECASE):
        rhythm_category = 'SINUS_RHYTHM'
        severity_level = 'NORMAL'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    # ==================================================================
    # PRIORITY 8: PACED RHYTHMS
    # ==================================================================

    elif re.search(r'(av.?paced|a-v.?paced|dual.?chamber.?pac)', rv, re.IGNORECASE):
        rhythm_category = 'AV_PACED'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'PACED'

    elif re.search(r'(v.?paced|ventricular.?pac)', rv, re.IGNORECASE):
        rhythm_category = 'V_PACED'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'PACED'

    elif re.search(r'(a.?paced|atrial.?pac)', rv, re.IGNORECASE):
        rhythm_category = 'A_PACED'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'PACED'

    elif re.search(r'(paced|pacing|pacer)', rv, re.IGNORECASE):
        rhythm_category = 'PACED'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'PACED'

    # ==================================================================
    # PRIORITY 9: OTHER CLINICAL EVENTS
    # ==================================================================

    elif re.search(r'asystole', rv, re.IGNORECASE):
        rhythm_category = 'ASYSTOLE'
        severity_level = 'LIFE_THREATENING'
        is_proarrhythmic = False
        rhythm_origin = 'UNKNOWN'

    elif re.search(r'(pvc|premature.?ventricular)', rv, re.IGNORECASE):
        rhythm_category = 'PVC'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'VENTRICULAR'

    elif re.search(r'(pac|premature.?atrial)', rv, re.IGNORECASE):
        rhythm_category = 'PAC'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'ATRIAL'

    # ==================================================================
    # DEFAULT: UNCLASSIFIED
    # ==================================================================

    else:
        rhythm_category = 'OTHER_UNCLASSIFIED'
        severity_level = 'OTHER'
        is_proarrhythmic = False
        rhythm_origin = 'UNKNOWN'

    return {
        'rhythm_category': rhythm_category,
        'severity_level': severity_level,
        'is_proarrhythmic_event': is_proarrhythmic,
        'rhythm_origin': rhythm_origin
    }


def classify_rhythm_df(df: pd.DataFrame, rhythm_col: str = 'rhythm_value') -> pd.DataFrame:
    """
    Apply rhythm classification to a pandas DataFrame.

    Parameters
    ----------
    df : pd.DataFrame
        DataFrame containing rhythm observations
    rhythm_col : str, default 'rhythm_value'
        Name of the column containing rhythm text values

    Returns
    -------
    pd.DataFrame
        Original DataFrame with added columns:
        - rhythm_category
        - severity_level
        - is_proarrhythmic_event
        - rhythm_origin

    Examples
    --------
    >>> import pandas as pd
    >>> df = pd.DataFrame({'rhythm_value': ['afib', 'sinus rhythm', 'v tach']})
    >>> df_classified = classify_rhythm_df(df)
    >>> print(df_classified[['rhythm_value', 'rhythm_category']])
    """
    if rhythm_col not in df.columns:
        raise ValueError(f"Column '{rhythm_col}' not found in DataFrame")

    # Apply classification
    classification_results = df[rhythm_col].apply(classify_rhythm)

    # Extract components into separate columns
    df['rhythm_category'] = classification_results.apply(lambda x: x['rhythm_category'])
    df['severity_level'] = classification_results.apply(lambda x: x['severity_level'])
    df['is_proarrhythmic_event'] = classification_results.apply(lambda x: x['is_proarrhythmic_event'])
    df['rhythm_origin'] = classification_results.apply(lambda x: x['rhythm_origin'])

    return df


def get_proarrhythmic_events(df: pd.DataFrame) -> pd.DataFrame:
    """
    Filter DataFrame to only proarrhythmic events.

    Parameters
    ----------
    df : pd.DataFrame
        DataFrame with rhythm classifications (from classify_rhythm_df)

    Returns
    -------
    pd.DataFrame
        Filtered DataFrame with only proarrhythmic events
    """
    if 'is_proarrhythmic_event' not in df.columns:
        raise ValueError("DataFrame must have 'is_proarrhythmic_event' column. Run classify_rhythm_df first.")

    return df[df['is_proarrhythmic_event'] == True].copy()


def rhythm_summary(df: pd.DataFrame) -> pd.DataFrame:
    """
    Generate summary statistics of rhythm classifications.

    Parameters
    ----------
    df : pd.DataFrame
        DataFrame with rhythm classifications

    Returns
    -------
    pd.DataFrame
        Summary table with counts and percentages by rhythm category
    """
    if 'rhythm_category' not in df.columns:
        raise ValueError("DataFrame must have 'rhythm_category' column. Run classify_rhythm_df first.")

    summary = df.groupby('rhythm_category').agg(
        count=('rhythm_category', 'size'),
        num_patients=('stay_id', 'nunique') if 'stay_id' in df.columns else ('rhythm_category', 'size')
    ).reset_index()

    summary['percentage'] = (summary['count'] / summary['count'].sum() * 100).round(1)
    summary = summary.sort_values('count', ascending=False)

    return summary


# Example usage and testing
if __name__ == "__main__":
    # Test cases
    test_rhythms = [
        "atrial fibrillation",
        "sinus rhythm",
        "v tach",
        "torsades de pointes",
        "3rd degree heart block",
        "sinus bradycardia",
        "normal sinus rhythm",
        "ventricular fibrillation",
        "atrial flutter",
        "paced",
    ]

    print("Rhythm Classification Test\n" + "="*70)
    for rhythm in test_rhythms:
        result = classify_rhythm(rhythm)
        print(f"\nRhythm: {rhythm}")
        print(f"  Category: {result['rhythm_category']}")
        print(f"  Severity: {result['severity_level']}")
        print(f"  Proarrhythmic: {result['is_proarrhythmic_event']}")
        print(f"  Origin: {result['rhythm_origin']}")

    print("\n" + "="*70)
    print("DataFrame Example\n")

    # Example DataFrame
    df = pd.DataFrame({
        'stay_id': [1, 1, 2, 2, 3],
        'rhythm_value': ['sinus rhythm', 'atrial fibrillation', 'v tach', 'sinus rhythm', 'torsades']
    })

    df_classified = classify_rhythm_df(df)
    print(df_classified[['stay_id', 'rhythm_value', 'rhythm_category', 'is_proarrhythmic_event']])

    print("\n" + "="*70)
    print("Proarrhythmic Events Only\n")
    proarrhythmic = get_proarrhythmic_events(df_classified)
    print(proarrhythmic[['stay_id', 'rhythm_value', 'rhythm_category']])
