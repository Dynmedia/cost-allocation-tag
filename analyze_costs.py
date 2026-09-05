#!/usr/bin/env python3
"""Analyze Amazon Q Agent costs via AWS Cost Explorer.

Acceptance criterion #1: "Amazon Q Agent cost broken down and understood."

This script pulls unblended cost for the Amazon Q / Bedrock family of services
and breaks it down by:
  * month (trend over the lookback window)
  * service
  * usage type (to separate agent invocations, tokens, indexing, etc.)

It prints a human-readable report and, with --json, emits machine-readable output.

Requires: Cost Explorer enabled + IAM permission `ce:GetCostAndUsage`.
Cost Explorer is a global service; boto3 client region should be us-east-1.
"""
from __future__ import annotations

import argparse
import json
import sys

from qcost.common import load_config, require_boto3, month_range, money


def _ce_client(boto3, region: str):
    return boto3.client("ce", region_name=region)


def _group_query(ce, start, end, granularity, service_names, group_key):
    """Run GetCostAndUsage filtered to the Q/Bedrock services, grouped by group_key."""
    cost_filter = {
        "Dimensions": {
            "Key": "SERVICE",
            "Values": service_names,
        }
    }
    results = []
    next_token = None
    while True:
        kwargs = dict(
            TimePeriod={"Start": start, "End": end},
            Granularity=granularity,
            Metrics=["UnblendedCost"],
            Filter=cost_filter,
            GroupBy=[{"Type": "DIMENSION", "Key": group_key}],
        )
        if next_token:
            kwargs["NextPageToken"] = next_token
        resp = ce.get_cost_and_usage(**kwargs)
        results.extend(resp.get("ResultsByTime", []))
        next_token = resp.get("NextPageToken")
        if not next_token:
            break
    return results


def _sum_by_group(results_by_time) -> dict[str, float]:
    totals: dict[str, float] = {}
    for period in results_by_time:
        for grp in period.get("Groups", []):
            key = grp["Keys"][0]
            amt = float(grp["Metrics"]["UnblendedCost"]["Amount"])
            totals[key] = totals.get(key, 0.0) + amt
    return totals


def _monthly_totals(results_by_time) -> list[tuple[str, float]]:
    out = []
    for period in results_by_time:
        start = period["TimePeriod"]["Start"]
        total = 0.0
        for grp in period.get("Groups", []):
            total += float(grp["Metrics"]["UnblendedCost"]["Amount"])
        out.append((start, total))
    return out


def analyze(config: dict) -> dict:
    boto3 = require_boto3()
    ce_region = config.get("cost_explorer_region", "us-east-1")
    ce = _ce_client(boto3, ce_region)

    start, end = month_range(int(config.get("lookback_months", 6)))
    granularity = config.get("granularity", "MONTHLY")
    service_names = config["q_agent"]["service_names"]

    by_service_time = _group_query(ce, start, end, granularity, service_names, "SERVICE")
    by_usage_time = _group_query(ce, start, end, granularity, service_names, "USAGE_TYPE")

    report = {
        "time_period": {"start": start, "end": end},
        "granularity": granularity,
        "services_filter": service_names,
        "monthly_totals": _monthly_totals(by_service_time),
        "by_service": dict(
            sorted(_sum_by_group(by_service_time).items(), key=lambda kv: -kv[1])
        ),
        "by_usage_type": dict(
            sorted(_sum_by_group(by_usage_time).items(), key=lambda kv: -kv[1])
        ),
    }
    report["grand_total"] = round(sum(report["by_service"].values()), 2)
    return report


def print_report(report: dict) -> None:
    tp = report["time_period"]
    print("=" * 62)
    print("  Amazon Q Agent Cost Analysis")
    print(f"  Window: {tp['start']} -> {tp['end']} (end exclusive)")
    print("=" * 62)

    print("\nMonthly trend:")
    for month, total in report["monthly_totals"]:
        bar = "#" * min(50, int(total / 10)) if total else ""
        print(f"  {month}   {money(total):>12}  {bar}")

    print("\nBy service:")
    for svc, amt in report["by_service"].items():
        print(f"  {money(amt):>12}   {svc}")

    print("\nTop usage types:")
    for ut, amt in list(report["by_usage_type"].items())[:15]:
        if amt <= 0:
            continue
        print(f"  {money(amt):>12}   {ut}")

    print("\n" + "-" * 62)
    print(f"  GRAND TOTAL: {money(report['grand_total'])}")
    print("-" * 62)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=None, help="Path to config JSON")
    parser.add_argument("--json", action="store_true", help="Emit JSON only")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    try:
        report = analyze(config)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[error] cost analysis failed: {exc}\n")
        sys.stderr.write(
            "Check that Cost Explorer is enabled and the caller has ce:GetCostAndUsage.\n"
        )
        return 1

    if args.json:
        print(json.dumps(report, indent=2, default=str))
    else:
        print_report(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
