"""Shared helpers for the Amazon Q Agent cost toolkit."""
from __future__ import annotations

import json
import os
import sys
from datetime import date

try:
    import boto3  # noqa: F401
except ImportError:  # pragma: no cover
    boto3 = None


DEFAULT_CONFIG_PATH = os.environ.get("QCOST_CONFIG", "config.json")


def load_config(path: str | None = None) -> dict:
    """Load JSON config; fall back to config.example.json if config.json is absent."""
    path = path or DEFAULT_CONFIG_PATH
    if not os.path.exists(path) and os.path.exists("config.example.json"):
        sys.stderr.write(
            f"[warn] {path} not found, using config.example.json. "
            "Copy it to config.json and edit before running against real accounts.\n"
        )
        path = "config.example.json"
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def require_boto3():
    if boto3 is None:
        sys.exit(
            "boto3 is not installed. Run: python3 -m pip install -r requirements.txt"
        )
    return boto3


def _add_months(d: date, months: int) -> date:
    """Add (or subtract) whole months to a date, clamped to the 1st of the month."""
    month_index = (d.year * 12 + (d.month - 1)) + months
    year, month0 = divmod(month_index, 12)
    return date(year, month0 + 1, 1)


def month_range(lookback_months: int) -> tuple[str, str]:
    """Return (start, end) as YYYY-MM-DD covering the last N whole+current months.

    Cost Explorer 'end' is exclusive, so we go to the first of next month.
    """
    first_of_this_month = date.today().replace(day=1)
    end = _add_months(first_of_this_month, 1).isoformat()
    start = _add_months(first_of_this_month, -(lookback_months - 1)).isoformat()
    return start, end


def money(value: str | float) -> str:
    return f"${float(value):,.2f}"
