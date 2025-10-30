#!/usr/bin/env python3
"""
Setup Verification Script for MIMIC-IV AF Study
Run this script to verify your environment is correctly configured.
"""

import sys
import subprocess

def check_requirement(name, check_func, fix_hint=""):
    """Check a requirement and report status"""
    print(f"\n{'='*60}")
    print(f"Checking: {name}")
    print(f"{'='*60}")
    try:
        result = check_func()
        if result:
            print(f"✅ PASS: {name}")
            return True
        else:
            print(f"❌ FAIL: {name}")
            if fix_hint:
                print(f"   Fix: {fix_hint}")
            return False
    except Exception as e:
        print(f"❌ ERROR: {name}")
        print(f"   Error: {str(e)}")
        if fix_hint:
            print(f"   Fix: {fix_hint}")
        return False

def check_python_version():
    """Check Python version >= 3.8"""
    version = sys.version_info
    print(f"Python version: {version.major}.{version.minor}.{version.micro}")
    return version.major == 3 and version.minor >= 8

def check_packages():
    """Check required Python packages"""
    required_packages = [
        'pandas', 'numpy', 'matplotlib', 'seaborn', 'plotly',
        'google.cloud.bigquery', 'scipy', 'jupyter'
    ]

    missing = []
    for package in required_packages:
        package_name = package.split('.')[0]  # Handle google.cloud.bigquery
        try:
            __import__(package_name)
            print(f"  ✓ {package_name}")
        except ImportError:
            print(f"  ✗ {package_name} (missing)")
            missing.append(package_name)

    if missing:
        print(f"\nMissing packages: {', '.join(missing)}")
        print("Install with: pip install -r requirements.txt")
        return False
    return True

def check_gcloud():
    """Check if gcloud is installed and authenticated"""
    try:
        # Check gcloud version
        result = subprocess.run(['gcloud', 'version'],
                              capture_output=True, text=True, timeout=5)
        if result.returncode == 0:
            print("gcloud CLI installed")

            # Check authentication
            result = subprocess.run(['gcloud', 'auth', 'list'],
                                  capture_output=True, text=True, timeout=5)
            if 'ACTIVE' in result.stdout:
                print("✓ Authenticated account found")
                return True
            else:
                print("✗ No active authentication")
                return False
        return False
    except FileNotFoundError:
        print("gcloud CLI not found")
        return False
    except Exception as e:
        print(f"Error checking gcloud: {e}")
        return False

def check_bigquery_access():
    """Check BigQuery access to MIMIC-IV"""
    try:
        from google.cloud import bigquery

        client = bigquery.Client(project='tactical-grid-454202-h6')

        # Try to list datasets in physionet-data
        query = """
        SELECT table_catalog, table_schema
        FROM `physionet-data.mimiciv_3_1_icu.INFORMATION_SCHEMA.TABLES`
        LIMIT 1
        """

        result = client.query(query).result()
        print("✓ Successfully queried MIMIC-IV on BigQuery")
        return True

    except Exception as e:
        print(f"✗ BigQuery access error: {str(e)[:100]}")
        return False

def check_directory_structure():
    """Check if project directories exist"""
    import os

    required_dirs = ['notebooks', 'sql_queries', 'outputs', 'data']

    all_exist = True
    for dir_name in required_dirs:
        if os.path.exists(dir_name):
            print(f"  ✓ {dir_name}/")
        else:
            print(f"  ✗ {dir_name}/ (missing)")
            all_exist = False

    return all_exist

def check_required_files():
    """Check if required files exist"""
    import os

    required_files = [
        'config.py',
        'requirements.txt',
        'README.md',
        'QUICKSTART.md',
        'notebooks/01_rhythm_itemid_discovery.ipynb',
        'notebooks/02_af_cohort_construction.ipynb',
        'sql_queries/01_discover_rhythm_itemids.sql'
    ]

    all_exist = True
    for file_path in required_files:
        if os.path.exists(file_path):
            print(f"  ✓ {file_path}")
        else:
            print(f"  ✗ {file_path} (missing)")
            all_exist = False

    return all_exist

def main():
    """Run all checks"""
    print("\n" + "="*60)
    print("MIMIC-IV AF STUDY - ENVIRONMENT VERIFICATION")
    print("="*60)

    checks = [
        ("Python Version (>= 3.8)", check_python_version,
         "Install Python 3.8 or higher"),

        ("Required Python Packages", check_packages,
         "Run: pip install -r requirements.txt"),

        ("Google Cloud SDK", check_gcloud,
         "Run: gcloud auth login"),

        ("BigQuery Access to MIMIC-IV", check_bigquery_access,
         "Ensure you have access to physionet-data project"),

        ("Project Directory Structure", check_directory_structure,
         "Run setup from project root directory"),

        ("Required Files", check_required_files,
         "Re-run project setup")
    ]

    results = []
    for name, check_func, fix_hint in checks:
        passed = check_requirement(name, check_func, fix_hint)
        results.append((name, passed))

    # Summary
    print("\n" + "="*60)
    print("VERIFICATION SUMMARY")
    print("="*60)

    passed_count = sum(1 for _, passed in results if passed)
    total_count = len(results)

    for name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status}: {name}")

    print("\n" + "="*60)
    print(f"Results: {passed_count}/{total_count} checks passed")
    print("="*60)

    if passed_count == total_count:
        print("\n🎉 SUCCESS! Your environment is ready for analysis.")
        print("\nNext step: Run the Jupyter notebooks in order:")
        print("  1. notebooks/01_rhythm_itemid_discovery.ipynb")
        print("  2. notebooks/02_af_cohort_construction.ipynb")
        print("  3. notebooks/03_statistical_analysis.ipynb")
        print("  4. notebooks/04_visualization_dashboard.ipynb")
    else:
        print("\n⚠️  ATTENTION: Some checks failed. Please fix the issues above.")
        print("\nFor help, see:")
        print("  - README.md for comprehensive documentation")
        print("  - QUICKSTART.md for troubleshooting tips")

    return passed_count == total_count

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
