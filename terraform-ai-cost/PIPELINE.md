# CI/CD Pipeline — AI Cost Module

GitHub Actions + OIDC pipeline that deploys the AI cost module to the
**management account `660571558619`**. No long-lived AWS keys are stored in
GitHub — the workflow assumes a scoped IAM role via OpenID Connect.

```
Pull request  ─▶ plan  (fmt · init · validate · plan · comment on PR)
Merge to main ─▶ plan ─▶ apply   (gated by the `production` environment)
```

## One-time setup

Do these in order. Steps 1–2 run locally with the `mgt` profile; the rest are
GitHub settings.

### 1. Apply the bootstrap (creates state bucket + pipeline IAM role)

```bash
cd terraform-ai-cost/bootstrap
terraform init
terraform plan     # confirm account = 660571558619
terraform apply
terraform output   # note state_bucket and pipeline_role_arn
```

This creates:
- **S3 state bucket** `dyn-tfstate-ai-cost-660571558619` (versioned, KMS-encrypted, public access blocked, `prevent_destroy`)
- Reuses the **existing GitHub OIDC provider** in the account
- IAM role **`gha-ai-cost-deployer`** — trusted only by
  `repo:Dynmedia/cost-allocation-tag` on `main` and pull requests, permissioned
  only for Cost Explorer allocation tags + Cost Categories, Budgets, and R/W to
  the state bucket.

> Bootstrap intentionally uses **local state**. Commit its `terraform.tfstate`
> to the repo, or just re-run `apply` (it is idempotent) if you need to change it.

### 2. Migrate the module's state to S3

The bucket now exists, so point the module at the remote backend:

```bash
cd terraform-ai-cost
terraform init -migrate-state -backend-config="profile=mgt"
# answer "yes" to copy the existing local state into S3
```

### 3. Set the GitHub repository variable

Repo → **Settings → Secrets and variables → Actions → Variables → New variable**:

| Name | Value |
|------|-------|
| `AWS_ROLE_ARN` | the `pipeline_role_arn` output from step 1 (e.g. `arn:aws:iam::660571558619:role/gha-ai-cost-deployer`) |
| `AI_NOTIFY_EMAILS` | budget alert recipients in HCL list form, e.g. `["ahmed.sajib@dynmedia.com"]` |
| `AI_BUDGET_LIMIT` | monthly budget ceiling in USD, e.g. `3000` |

These are **variables**, not secrets — a role ARN, an internal email, and a
budget number are not sensitive. `AI_NOTIFY_EMAILS` / `AI_BUDGET_LIMIT` replace
the gitignored `terraform.tfvars` for CI runs.

### 4. Create the `production` environment (the apply gate)

Repo → **Settings → Environments → New environment → `production`**:
- Enable **Required reviewers** and add whoever approves cost changes.
- Optionally restrict deployment branches to `main`.

The `apply` job declares `environment: production`, so merges to `main` will run
`plan`, then **pause for approval** before `apply`.

### 5. Protect `main` (recommended)

Repo → **Settings → Branches → Add rule** for `main`:
- Require a pull request before merging.
- Require the **Plan** status check to pass.

## Day-to-day flow

1. Open a PR that changes anything under `terraform-ai-cost/`.
2. The **Plan** job runs and posts the `terraform plan` output as a PR comment.
3. Review the plan, get approval, merge to `main`.
4. The **Apply** job runs `plan`, then waits for a `production` reviewer to
   approve, then applies the saved plan.

## What the workflow does (`.github/workflows/terraform-ai-cost.yml`)

- Triggers only on changes under `terraform-ai-cost/**` (and the workflow file).
- `permissions: id-token: write` — required for OIDC.
- `TF_VAR_aws_profile=""` in CI, so the provider uses OIDC env credentials
  instead of a local profile.
- `concurrency` prevents two applies racing on the same state.
- Apply consumes the exact `tfplan` artifact produced by the plan job, so what
  gets applied is what was reviewed.

## Gotchas

- **`terraform fmt -check` is a hard gate.** Run `terraform fmt -recursive`
  before pushing or the Plan job fails.
- **`.terraform.lock.hcl` is committed on purpose** so CI resolves the same
  provider versions. Don't gitignore it.
- **`terraform.tfvars` is gitignored.** It may hold an email/account values, so
  CI does not read it. The pipeline supplies `notify_emails` and
  `budget_limit_amount` via `TF_VAR_*` from GitHub repo variables (see step 3).
  Locally, keep your own `terraform.tfvars` (copy from `terraform.tfvars.example`).
- **Repo name must match.** The IAM trust policy is scoped to
  `Dynmedia/cost-allocation-tag`. If the repo is named differently, update
  `github_repo` in `bootstrap/terraform.tfvars` and re-apply the bootstrap.
- **First plan on a PR from a fork** won't have OIDC access by design (forks
  can't assume the role). Run the pipeline from branches in the same repo.

## Teardown

```bash
# Module resources (tags/category/budget):
cd terraform-ai-cost && terraform destroy

# Then the bootstrap. The state bucket has prevent_destroy — remove that
# lifecycle rule (or empty + delete the bucket manually) before destroying.
cd bootstrap && terraform destroy
```
