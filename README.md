# Amazon Q Agent — Cost Visibility Toolkit

Make Amazon Q Agent spend **attributable** to an owner/workload and guard against
runaway cost. This is the first concrete AI-cost visibility case.

It delivers the three acceptance criteria:

| # | Acceptance criterion | How this repo satisfies it |
|---|----------------------|----------------------------|
| 1 | Amazon Q Agent cost broken down and understood | `analyze_costs.py` (Cost Explorer) |
| 2 | Cost allocation tags applied and visible in Cost Explorer | `apply_tags.py` or `terraform/` |
| 3 | Billing alert(s) configured for budget overruns | `create_budget_alerts.py` or `terraform/` |

---

## Important: this needs YOUR AWS account

Every step here reads or writes real billing data, so it must run with
credentials for the AWS account that owns the Amazon Q Agent. Nothing in this
repo can query your account without that access. The scripts were authored and
their pure logic validated locally, but they have **not** been run against a live
account from here — run them yourself (or in CI) with valid credentials.

### Prerequisites

- **AWS credentials** with the permissions listed per step below. Cost Explorer,
  cost allocation tags, and Budgets are **global** services reached through
  `us-east-1`; the config defaults to that region.
- **Cost Explorer must be enabled** in the account (Billing console → Cost
  Explorer → Enable). First-time enablement can take up to 24h to populate.
- Python 3.9+ and `pip install -r requirements.txt` for the Python path, **or**
  Terraform ≥ 1.5 for the IaC path.

### Setup

```bash
python3 -m pip install -r requirements.txt
cp config.example.json config.json
# edit config.json: set budget.notify_emails to a REAL address, adjust limits/tags
export AWS_PROFILE=your-profile   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
```

---

## Step 1 — Analyze Amazon Q Agent costs

```bash
python3 analyze_costs.py            # human-readable report
python3 analyze_costs.py --json     # machine-readable
```

Breaks spend down by month, by service, and by usage type over the lookback
window (default 6 months), filtered to the Amazon Q / Bedrock services listed in
`config.json` → `q_agent.service_names`.

- IAM permission: `ce:GetCostAndUsage`
- **Verify (criterion #1):** the report prints a monthly trend, a per-service
  breakdown, top usage types, and a grand total. Cross-check the same numbers in
  the Cost Explorer console (filter Service = Amazon Q / Amazon Bedrock).

> Tune `q_agent.service_names` to match how Q shows up on your bill. Depending on
> account/region, Amazon Q appears as "Amazon Q", and agent model usage often
> appears under "Amazon Bedrock". Run `analyze_costs.py --json` and inspect
> `by_service` to confirm the exact service strings, then refine the filter.

## Step 2 — Apply cost allocation tags

A tag becomes a *cost allocation* tag only after **both**: (a) the resources are
tagged, and (b) the tag key is **activated** in Billing.

```bash
# Preview everything first
python3 apply_tags.py --discover --dry-run

# Activate the tag keys only (safe, no resource changes)
python3 apply_tags.py --activate-only

# Tag specific resources (recommended: pass the Q app / Bedrock agent ARNs)
python3 apply_tags.py --arns \
  arn:aws:qbusiness:us-east-1:<acct>:application/<app-id> \
  arn:aws:bedrock:us-east-1:<acct>:agent/<agent-id>

# Or discover taggable resources by type
python3 apply_tags.py --discover qbusiness bedrock
```

- IAM permissions: `ce:UpdateCostAllocationTagsStatus`, `ce:ListCostAllocationTags`,
  `tag:TagResources`, `tag:GetResources`
- **Verify (criterion #2):** in Billing console → Cost allocation tags, the keys
  (`Owner`, `Workload`, `CostCenter`, `Environment`) show **Active**. Then in Cost
  Explorer, group by Tag → `Workload` and confirm `amazon-q-agent` appears.

> Two timing caveats set by AWS, not this tool: a newly activated cost allocation
> tag can take up to ~24h to appear in Cost Explorer, and only usage recorded
> **after** a resource is tagged is attributed to that value.

## Step 3 — Create billing alerts on overruns

```bash
python3 create_budget_alerts.py --dry-run   # preview
python3 create_budget_alerts.py             # create/update the budget
```

Creates a monthly COST budget scoped to `Workload=amazon-q-agent`, with email
alerts at **80% actual**, **100% actual**, and **100% forecasted** (all
configurable in `config.json` → `budget`).

- IAM permissions: `budgets:CreateBudget`, `budgets:ModifyBudget`,
  `budgets:DescribeBudget`, `budgets:CreateNotification`, `budgets:CreateSubscriber`
- Guard: the script refuses to run while `notify_emails` is the placeholder
  `you@example.com`.
- **Verify (criterion #3):** Billing console → Budgets shows
  `amazon-q-agent-monthly-budget` with the three alert thresholds. Subscribed
  emails receive an SNS/email confirmation.

---

## Alternative: Terraform (IaC)

Steps 2 and 3 as reviewable, repeatable infrastructure code.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # set notify_emails etc.
terraform init
terraform plan
terraform apply
```

Creates `aws_ce_cost_allocation_tag` (Active) for each key and an
`aws_budgets_budget` filtered to the workload tag with actual + forecasted
notifications. Provider is pinned to `us-east-1` because these are global
services.

---

## Layout

```
config.example.json        # copy to config.json and edit
requirements.txt           # boto3
analyze_costs.py           # criterion #1 — Cost Explorer breakdown
apply_tags.py              # criterion #2 — activate + apply cost allocation tags
create_budget_alerts.py    # criterion #3 — AWS Budgets overrun alerts
qcost/common.py            # shared config/date/formatting helpers
terraform/                 # IaC alternative for criteria #2 and #3
```

## Recommended order of operations

1. Run **Step 2** (tag + activate) first so spend starts accruing under the tag.
2. Run **Step 3** to put the guardrail in place.
3. Run **Step 1** regularly (or on a schedule) to review the breakdown. Note that
   tag-based attribution in Cost Explorer becomes meaningful only after tagging
   plus AWS's backfill delay.
