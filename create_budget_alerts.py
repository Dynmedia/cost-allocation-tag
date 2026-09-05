#!/usr/bin/env python3
"""Create AWS Budgets billing alerts for Amazon Q Agent spend.

Acceptance criterion #3: "Billing alert(s) configured for budget overruns."

Creates (or updates) a monthly cost budget scoped to the Amazon Q Agent workload
via a cost allocation tag filter (default: Workload=amazon-q-agent), with email
notifications that fire when:
  * ACTUAL spend crosses configured % thresholds (e.g. 80%, 100%)
  * FORECASTED spend is expected to cross a threshold (e.g. 100%)

Budgets is a global service accessed through us-east-1. The budget filter uses
the SAME cost allocation tag the tagging step activates, so alerts track exactly
the tagged workload.

Requires IAM permissions: budgets:CreateBudget, budgets:ModifyBudget,
budgets:DescribeBudget, budgets:CreateNotification, budgets:CreateSubscriber.
"""
from __future__ import annotations

import argparse
import sys

from qcost.common import load_config, require_boto3


def _account_id(boto3) -> str:
    return boto3.client("sts").get_caller_identity()["Account"]


def _build_notifications(budget_cfg: dict) -> list[dict]:
    emails = budget_cfg["notify_emails"]
    subscribers = [
        {"SubscriptionType": "EMAIL", "Address": addr} for addr in emails
    ]
    notifications = []
    for pct in budget_cfg.get("actual_thresholds_percent", []):
        notifications.append(
            {
                "Notification": {
                    "NotificationType": "ACTUAL",
                    "ComparisonOperator": "GREATER_THAN",
                    "Threshold": float(pct),
                    "ThresholdType": "PERCENTAGE",
                },
                "Subscribers": subscribers,
            }
        )
    for pct in budget_cfg.get("forecasted_thresholds_percent", []):
        notifications.append(
            {
                "Notification": {
                    "NotificationType": "FORECASTED",
                    "ComparisonOperator": "GREATER_THAN",
                    "Threshold": float(pct),
                    "ThresholdType": "PERCENTAGE",
                },
                "Subscribers": subscribers,
            }
        )
    return notifications


def _build_budget(budget_cfg: dict) -> dict:
    budget = {
        "BudgetName": budget_cfg["name"],
        "BudgetLimit": {
            "Amount": str(budget_cfg["limit_amount"]),
            "Unit": budget_cfg.get("limit_unit", "USD"),
        },
        "TimeUnit": budget_cfg.get("time_unit", "MONTHLY"),
        "BudgetType": "COST",
    }
    tag_key = budget_cfg.get("cost_filter_tag_key")
    tag_val = budget_cfg.get("cost_filter_tag_value")
    if tag_key and tag_val:
        # CostFilters expects keys like "TagKeyValue" -> ["user:Key$Value"].
        budget["CostFilters"] = {
            "TagKeyValue": [f"user:{tag_key}${tag_val}"]
        }
    return budget


def create_or_update(config: dict, dry_run: bool) -> int:
    boto3 = require_boto3()
    region = config.get("cost_explorer_region", "us-east-1")
    budgets = boto3.client("budgets", region_name=region)
    budget_cfg = config["budget"]

    account_id = _account_id(boto3)
    budget = _build_budget(budget_cfg)
    notifications = _build_notifications(budget_cfg)

    print(f"[budget] account={account_id} name={budget['BudgetName']}")
    print(f"  limit={budget['BudgetLimit']['Amount']} {budget['BudgetLimit']['Unit']}"
          f" / {budget['TimeUnit']}")
    print(f"  filter={budget.get('CostFilters', 'none (whole-account)')}")
    print(f"  notifications={len(notifications)}")

    if dry_run:
        print("  [dry-run] no API calls made.")
        return 0

    # Does it already exist?
    exists = False
    try:
        budgets.describe_budget(AccountId=account_id, BudgetName=budget["BudgetName"])
        exists = True
    except budgets.exceptions.NotFoundException:
        exists = False

    if exists:
        budgets.update_budget(AccountId=account_id, NewBudget=budget)
        print("  updated existing budget.")
        # Reconcile notifications: simplest robust approach is create-if-missing.
        _ensure_notifications(budgets, account_id, budget["BudgetName"], notifications)
    else:
        budgets.create_budget(
            AccountId=account_id,
            Budget=budget,
            NotificationsWithSubscribers=notifications,
        )
        print("  created budget with notifications.")
    return 0


def _ensure_notifications(budgets, account_id, name, notifications):
    """Create any notifications that don't already exist on the budget."""
    existing = []
    try:
        paginator = budgets.get_paginator("describe_notifications_for_budget")
        for page in paginator.paginate(AccountId=account_id, BudgetName=name):
            existing.extend(page.get("Notifications", []))
    except Exception:  # noqa: BLE001
        existing = []

    def key(n):
        return (n["NotificationType"], n["ComparisonOperator"], float(n["Threshold"]))

    existing_keys = {key(n) for n in existing}
    for item in notifications:
        n = item["Notification"]
        if key(n) in existing_keys:
            continue
        budgets.create_notification(
            AccountId=account_id,
            BudgetName=name,
            Notification=n,
            Subscribers=item["Subscribers"],
        )
        print(f"    added notification {key(n)}")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    budget_cfg = config.get("budget", {})
    if not budget_cfg.get("notify_emails") or budget_cfg["notify_emails"] == [
        "you@example.com"
    ]:
        sys.stderr.write(
            "[error] Set a real address in budget.notify_emails before creating "
            "alerts (currently the placeholder you@example.com).\n"
        )
        return 2

    try:
        return create_or_update(config, args.dry_run)
    except Exception as exc:  # noqa: BLE001
        sys.stderr.write(f"[error] budget creation failed: {exc}\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
