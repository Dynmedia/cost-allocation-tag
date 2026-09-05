#!/usr/bin/env python3
"""Apply cost allocation tags for Amazon Q Agent spend.

Acceptance criterion #2: "Cost allocation tags applied and visible in Cost Explorer."

Two distinct things are needed for a tag to become a *cost allocation* tag:

  1. TAG the resources        -> puts key/value pairs on the actual AWS resources
                                  (via the Resource Groups Tagging API).
  2. ACTIVATE the tag keys    -> tells AWS Billing to treat those keys as cost
                                  allocation tags so they appear in Cost Explorer
                                  and can be used as budget filters.
                                  (ce:UpdateCostAllocationTagsStatus)

NOTE: After activation, AWS takes up to ~24h to backfill and surface a new user-
defined cost allocation tag in Cost Explorer. Only usage recorded *after* a
resource is tagged is attributed to that tag value.

Requires IAM permissions:
  * tag:TagResources, tag:GetResources        (Resource Groups Tagging API)
  * ce:UpdateCostAllocationTagsStatus,
    ce:ListCostAllocationTags                  (Cost Explorer billing tags)
"""
from __future__ import annotations

import argparse
import sys

from qcost.common import load_config, require_boto3


def activate_cost_allocation_tags(boto3, region: str, keys: list[str], dry_run: bool):
    """Activate user-defined tag keys as cost allocation tags in Billing."""
    ce = boto3.client("ce", region_name=region)
    print(f"[tags] Activating cost allocation tag keys: {keys}")
    if dry_run:
        print("  [dry-run] would call ce:UpdateCostAllocationTagsStatus (Active)")
        return
    resp = ce.update_cost_allocation_tags_status(
        CostAllocationTagsStatus=[
            {"TagKey": key, "Status": "Active"} for key in keys
        ]
    )
    errors = resp.get("Errors", [])
    if errors:
        for err in errors:
            sys.stderr.write(
                f"  [warn] could not activate '{err.get('TagKey')}': "
                f"{err.get('Code')} {err.get('Message')}\n"
            )
    else:
        print("  activated (allow up to ~24h to appear in Cost Explorer).")


def find_resources(boto3, region: str, resource_type_filters: list[str] | None):
    """Discover taggable resources via the Resource Groups Tagging API."""
    tagging = boto3.client("resourcegroupstaggingapi", region_name=region)
    paginator = tagging.get_paginator("get_resources")
    kwargs = {}
    if resource_type_filters:
        kwargs["ResourceTypeFilters"] = resource_type_filters
    arns = []
    for page in paginator.paginate(**kwargs):
        for item in page.get("ResourceTagMappingList", []):
            arns.append(item["ResourceARN"])
    return arns


def tag_resources(boto3, region: str, arns: list[str], tags: dict, dry_run: bool):
    """Apply key/value tags to a batch of resource ARNs (max 20 per call)."""
    tagging = boto3.client("resourcegroupstaggingapi", region_name=region)
    if not arns:
        print("[tags] No resource ARNs supplied to tag.")
        return
    print(f"[tags] Tagging {len(arns)} resource(s) with {tags}")
    if dry_run:
        for arn in arns:
            print(f"  [dry-run] would tag {arn}")
        return
    failed = {}
    for i in range(0, len(arns), 20):
        batch = arns[i : i + 20]
        resp = tagging.tag_resources(ResourceARNList=batch, Tags=tags)
        failed.update(resp.get("FailedResourcesMap", {}))
    if failed:
        for arn, info in failed.items():
            sys.stderr.write(
                f"  [warn] failed to tag {arn}: {info.get('ErrorCode')} "
                f"{info.get('ErrorMessage')}\n"
            )
    else:
        print("  all resources tagged successfully.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default=None)
    parser.add_argument(
        "--arns",
        nargs="*",
        default=None,
        help="Explicit resource ARNs to tag (e.g. Q application / Bedrock agent ARNs).",
    )
    parser.add_argument(
        "--discover",
        nargs="*",
        metavar="RESOURCE_TYPE",
        help="Discover resources by type filter (e.g. 'qbusiness' 'bedrock'). "
        "Empty means all taggable resources in the region.",
    )
    parser.add_argument(
        "--activate-only",
        action="store_true",
        help="Only activate cost allocation tag keys; do not tag resources.",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    config = load_config(args.config)
    boto3 = require_boto3()
    region = config.get("region", "us-east-1")
    ce_region = config.get("cost_explorer_region", "us-east-1")
    cat = config["cost_allocation_tags"]

    # Step 1: activate the keys as billing cost allocation tags (global -> us-east-1).
    activate_cost_allocation_tags(boto3, ce_region, cat["activate_keys"], args.dry_run)

    if args.activate_only:
        return 0

    # Step 2: figure out which resources to tag.
    arns = list(args.arns or [])
    if args.discover is not None:
        discovered = find_resources(boto3, region, args.discover or None)
        print(f"[tags] Discovered {len(discovered)} resource(s) via tagging API.")
        arns.extend(discovered)

    if not arns:
        print(
            "[tags] No ARNs given. Pass --arns <arn...> or --discover to select "
            "resources. (Tag keys were still activated above.)"
        )
        return 0

    tag_resources(boto3, region, arns, cat["resource_tags"], args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
