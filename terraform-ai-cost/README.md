# AI Cost Visibility (Terraform)

Makes AI spend across the whole AWS organization **attributable** and adds a
**runaway-spend guardrail**. Companion to the AWS Config tagging module in the
security account — this is the *finance/reporting* half.

## Where this deploys

**Management (payer) account `660571558619` (dyn media) only.** Cost allocation
tag activation, Cost Categories, and Budgets are payer-level billing features:
they can only be created in the management account, and they apply org-wide via
consolidated billing. The provider has `allowed_account_ids` set as a guard so
`apply` fails if pointed anywhere else.

This is deliberately separate from the Config module in security account
`754348400096`:

| Concern | Account | Module |
|---|---|---|
| Enforce tags EXIST on resources (detective) | 754348400096 | `security-account/modules/aws-config` |
| Make tags VISIBLE in Cost Explorer + budget on AI | 660571558619 | this module |

They connect only through the shared tag **key strings**.

## What it creates

1. **Cost allocation tag activation** for the keys your Config policy enforces
   (`Owner`, `Environment`, `Project`, `CostCenter`, `Stage`, `Team`) plus `AI`.
2. **An "AI" Cost Category** = resources tagged `AI=true` **OR** known AI
   services. The service rules catch usage-based AI cost that has no taggable
   resource (on-demand Bedrock model invocations, Kiro, etc.):
   - exact: Kiro, Amazon SageMaker, Amazon Lex, Amazon Polly, AWSDevOpsAgent, Q in Connect
   - contains `Bedrock`: `Amazon Bedrock`, `Amazon Bedrock AgentCore`, and every
     `... (Amazon Bedrock Edition)` model — stable as AWS adds new models.
3. **A monthly budget** on the AI Cost Category with email alerts at 80% / 100%
   actual and 100% forecasted.

## Why a Cost Category and not just a tag

The `AI=true` tag alone undercounts, because a large share of AI spend is
consumption with no resource to tag. The Cost Category unions the tag with the
AI **services**, giving one honest "total AI cost" dimension. Tagging still adds
value for the taggable cases (an EC2 box running a model that FinOps wouldn't
otherwise recognize as AI) — the two are complementary.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars   # set notify_emails, budget ceiling
terraform init
terraform plan      # review — confirm account id in the plan is 660571558619
terraform apply
```

## Verify

- `terraform output activated_cost_allocation_tags` lists the activated keys.
- Cost Explorer → group by **Cost Category: AI** → shows AI vs Non-AI spend
  (allow up to ~24h for a newly activated tag/category to populate).
- Billing → Budgets shows `ai-spend-monthly-budget`; confirm the email
  subscription when prompted.

## Governing the `AI` tag org-wide (policy side)

Activation here makes the tag *countable*; it does not make teams *apply* it.
To govern it, add an **Organizations Tag Policy** (not a required Config tag —
classification tags should be optional, applied only where relevant):

- `ai-tag-policy.json` in this folder defines the `AI` key with allowed values
  `true` / `false` (enforces consistent casing so Cost Explorer doesn't split
  `true`/`True`/`yes` into separate values).
- Attach it to the target OU(s). Recommended to manage this from the same place
  as your other Organizations policies.

## Note on the Config module's required tags

The Config README lists the enforced set as 4 (`Owner`, `Environment`,
`Project`, `CostCenter`) in one place and 6 (adding `Stage`, `Team`) in the
tfvars example, with a "must be exactly N" constraint. Reconcile that before
relying on `Stage`/`Team` for cost reporting — activate here only the keys that
are actually enforced.
