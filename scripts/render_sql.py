#!/usr/bin/env python3
"""
Simple placeholder renderer for SQL templates.

Replaces {{PROJECT}} and {{DATASET}} in input SQL and writes to stdout.

Usage:
  python3 scripts/render_sql.py path/to/file.sql \
    --project YOUR_PROJECT --dataset YOUR_DATASET > /tmp/rendered.sql
"""

import argparse
import re
import sys


def render(text: str, project: str, dataset: str) -> str:
    text = re.sub(r"\{\{\s*PROJECT\s*\}\}", project, text)
    text = re.sub(r"\{\{\s*DATASET\s*\}\}", dataset, text)
    return text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("template", help="Path to SQL template with placeholders")
    ap.add_argument("--project", required=True, help="GCP project ID to fill in")
    ap.add_argument("--dataset", required=True, help="BigQuery dataset to fill in")
    args = ap.parse_args()

    with open(args.template, "r", encoding="utf-8") as f:
        txt = f.read()

    sys.stdout.write(render(txt, args.project, args.dataset))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

