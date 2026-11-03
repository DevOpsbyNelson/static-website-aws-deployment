# Static website infrastructure

Terraform code that hosts the Vite/React site in `../website` on AWS:

```
Browser ──HTTPS──▶ CloudFront ──(Origin Access Control)──▶ private S3 bucket
```

- **S3**: private bucket (public access blocked, encrypted, versioned). Old file versions expire after a per-stage number of days.
- **CloudFront**:
  - Redirects HTTP to HTTPS and serves `index.html` for unknown paths, so client-side routing works.
  - Adds AWS's security headers and uses its caching-optimized policy.
- **Upload**: Terraform uploads `../website/dist`:
  - Each file gets the correct `Content-Type`.
  - Files in `assets/` are cached forever. Vite puts a content hash in their names.
  - `index.html` and other files are always revalidated.
  - The CloudFront cache is invalidated when content changes.
- **Stages**: `development`, `staging` and `production`, one Terraform workspace each.
- **State**: kept in S3 (remote backend), one state file per workspace.

## Layout

```
infrastructure/
├── versions.tf               # Terraform/provider versions, S3 backend, default tags
├── variables.tf              # region, project name, site folder, per-stage settings
├── stage.tf                  # workspace → stage mapping and guard
├── main.tf                   # calls modules/static-website
├── outputs.tf                # website URL, bucket, distribution ID, ...
├── moved.tf                  # maps pre-module resource addresses into the module
├── tests/                    # root tests (stage wiring)
├── scripts/
│   ├── common.sh                  # shared helpers (+ loads .env)
│   ├── bootstrap-state-bucket.sh  # creates the S3 bucket for Terraform state
│   ├── terraform-init.sh          # terraform init with the S3 backend + selects workspace
│   ├── terraform-run.sh           # init, then any terraform command for ENVIRONMENT
│   └── deploy.sh                  # non-interactive plan/apply/destroy (used by CI)
└── modules/static-website/   # reusable module: S3 + CloudFront + upload
    └── tests/                # module unit tests + fixture site
```

## Prerequisites

- Terraform >= 1.10 (S3-native state locking). CI uses 1.15.6.
- AWS CLI v2. The scripts use it, and so does the cache invalidation after each upload.
- AWS credentials allowed to manage S3 and CloudFront in the target account.
- The built site: `cd ../website && pnpm install && pnpm build`.

## Configuration

All settings come from environment variables. For local use, copy the example file and edit it:

```bash
cp .env.example .env   # gitignored; variables already set in your shell take precedence
```

The scripts select variables with the `ENVIRONMENT` value:

| `ENVIRONMENT` | Variable prefix |
|---|---|
| `development` | `DEV_` |
| `staging` | `STAGING_` |
| `production` | `PROD_` |

| Variable | Required | Purpose |
|---|---|---|
| `<PREFIX>_REMOTE_STORAGE_AWS_S3_BUCKET` | yes | S3 bucket that stores Terraform state |
| `<PREFIX>_REMOTE_STORAGE_AWS_REGION` | yes | Region of that bucket |
| `<PREFIX>_REMOTE_STORAGE_AWS_S3_KEY` | yes | State object key, e.g. `static-website/terraform.tfstate` |
| `<PREFIX>_REMOTE_STORAGE_AWS_S3_ENDPOINT` or `REMOTE_STORAGE_AWS_S3_ENDPOINT` | no | Custom S3 endpoint (LocalStack, MinIO, ...) |
| `<PREFIX>_REMOTE_STORAGE_AWS_ACCESS_KEY_ID` or `REMOTE_STORAGE_AWS_ACCESS_KEY_ID` | no | Credentials for the state bucket only |
| `<PREFIX>_REMOTE_STORAGE_AWS_SECRET_ACCESS_KEY` or `REMOTE_STORAGE_AWS_SECRET_ACCESS_KEY` | no | Credentials for the state bucket only |
| `TF_INIT_RECONFIGURE` | no | `true` runs `terraform init -reconfigure` (needed when switching to another state bucket) |

The `REMOTE_STORAGE_*` credentials are used only for the **state** backend. The website resources are created with the normal AWS provider credentials: `AWS_PROFILE`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, SSO and so on. State and resources can therefore live in different accounts.

In the workspace, each stage's state is stored at `s3://<bucket>/env:/<ENVIRONMENT>/<key>`.

## First-time setup (once per state bucket)

```bash
ENVIRONMENT=development ./scripts/bootstrap-state-bucket.sh
```

This creates the state bucket with versioning, encryption and public access blocked. Re-running it is safe.

## Deploy

```bash
# 1. Build the site
cd ../website && pnpm build && cd ../infrastructure

# 2. Review and apply
ENVIRONMENT=development ./scripts/terraform-run.sh plan
ENVIRONMENT=development ./scripts/terraform-run.sh apply

# 3. Get the URL
ENVIRONMENT=development ./scripts/terraform-run.sh output website_url
```

What `terraform-run.sh` does:

1. Runs `terraform-init.sh`, which initializes the backend and selects (or creates) the `ENVIRONMENT` workspace.
2. Checks that the selected workspace matches `ENVIRONMENT`.
3. Runs the Terraform command.

Extra arguments are passed through to Terraform, for example `apply -auto-approve` in CI.

On the first deploy, CloudFront takes about 5–15 minutes to come online. To redeploy after code changes, run `pnpm build` and then `apply` again. Only the files that changed are uploaded, and the cache is cleared automatically.

**Switching environments:** if the stages use **different** state buckets, add `TF_INIT_RECONFIGURE=true` when you change `ENVIRONMENT`. The `.terraform/` folder only remembers one backend at a time:

```bash
TF_INIT_RECONFIGURE=true ENVIRONMENT=production ./scripts/terraform-run.sh plan
```

### Per-stage settings

Set in `var.stages` (`variables.tf`). Override them in a `terraform.tfvars` file if needed.

| | development | staging | production |
|---|---|---|---|
| CloudFront price class | `PriceClass_100` (NA/EU) | `PriceClass_100` | `PriceClass_All` |
| `terraform destroy` with files in the bucket | allowed | allowed | blocked |
| Old file versions kept | 7 days | 14 days | 90 days |

Resources are named `<project_name>-<stage>`. The bucket name also gets the AWS account ID, for example `static-website-production-123456789012`.

The `default` workspace isn't a stage. Plan and apply stop there with an error.

## Local development with LocalStack (or another AWS emulator)

Point both the state backend and the AWS provider at the emulator, e.g. in `.env`:

```bash
REMOTE_STORAGE_AWS_S3_ENDPOINT=http://localhost:4566
REMOTE_STORAGE_AWS_ACCESS_KEY_ID=test
REMOTE_STORAGE_AWS_SECRET_ACCESS_KEY=test

# Optional, local emulator only. Leave all of these unset to deploy to real AWS.
AWS_ENDPOINT_URL=http://localhost:4566
AWS_ACCESS_KEY_ID=test
AWS_SECRET_ACCESS_KEY=test
AWS_DEFAULT_REGION=us-east-1
```

When `AWS_ENDPOINT_URL` is set, the scripts turn on path-style S3 URLs (`TF_VAR_s3_use_path_style=true`) automatically.

Then use the same commands: `bootstrap-state-bucket.sh`, then `terraform-run.sh plan/apply`. `terraform-run.sh` prints the target before each command:

- `Target: AWS emulator at http://localhost:4566` for the emulator.
- `Target: real AWS account <id>` for real AWS.

In the plan, the bucket name should also end in the emulator's account ID (`000000000000`).

> ⚠️ If `AWS_ENDPOINT_URL` is missing, Terraform talks to **real AWS** with whatever credentials your shell has.

## Tests

The tests use `terraform test` with a **mocked AWS provider**. They need no credentials and create nothing.

```bash
# Module unit tests: bucket security, CloudFront settings, file types, cache headers, toggles
cd modules/static-website
terraform init
terraform test

# Root tests: stage wiring, per-stage settings, default-workspace guard
cd ../..
terraform init -backend=false
terraform test
```

`terraform test` always runs in the `default` workspace. The root tests pick a stage with `-var stage=<name>` instead. Leave `var.stage` unset for real deployments: it's only allowed to match the current workspace.

## Destroy

```bash
ENVIRONMENT=development ./scripts/terraform-run.sh destroy
```

Deleting a CloudFront distribution takes about 15 minutes, because AWS first disables it and waits for that change to finish rolling out.

`production` has `force_destroy = false`, so its bucket can't be destroyed while it still holds files. To destroy it on purpose, first set `force_destroy = true` for production in `var.stages` and apply that change.

## Reusing the module

`modules/static-website` has no stage logic and no provider block. It works in any configuration:

```hcl
module "docs_site" {
  source = "./modules/static-website"

  name        = "docs-production"
  bucket_name = "docs-production-123456789012"
  site_dir    = abspath("${path.root}/../docs/dist")

  # optional
  price_class             = "PriceClass_All"
  force_destroy           = false
  noncurrent_version_days = 30
  spa_fallback            = true      # serve index.html for unknown paths
  immutable_path_prefix   = "assets/" # files cached forever
  invalidate_on_change    = true      # needs the AWS CLI
}
```

Outputs: `website_url`, `bucket_name`, `bucket_arn`, `cloudfront_distribution_id`, `cloudfront_domain_name`, `uploaded_file_count`.

## CI/CD (GitHub Actions)

`.github/workflows/deploy.yml` (in the repo root) deploys to **real AWS**:

1. **`test` job**: reuses `.github/workflows/tests.yml`, which also runs on its own for every push and pull request. It runs:
   - `terraform fmt -check` and `terraform validate`
   - ShellCheck on the scripts
   - a Checkov security scan, report-only for now
   - both `terraform test` suites (mocked, so no credentials needed)
2. **`deploy` job**, for the stage that matches the branch:

   | Branch | Stage (GitHub environment) |
   |---|---|
   | `main` | `production` |
   | `staging` | `staging` |
   | `dev` | `development` |

   Other branches deploy nothing. The run:
   - uses the GitHub environment of the same name, so it gets that environment's secrets and protection rules;
   - builds the website with Node 26 and pnpm;
   - assumes the deploy IAM role through GitHub OIDC (short-lived credentials, no stored AWS keys);
   - runs `scripts/deploy.sh`.

   Each stage has its own concurrency group, so two runs never touch the same state at once.

**Triggers:**
- A push to `main`, `staging` or `dev` that changes `website/`, `infrastructure/` or the workflows runs `apply` for that branch's stage.
- A manual run (**Actions → Deploy → Run workflow**) lets you choose `apply` or `plan`. Pick the branch in that dialog: its stage is the one that runs.

### Setup

1. **Create the deploy role and the state bucket** with the manual **Create Deploy Role** workflow. See [`aws_role/README.md`](../aws_role/README.md). Its job summary prints the exact secret values for step 3.
2. **Create three GitHub environments**: `development`, `staging` and `production`. In each one, set **Deployment branches** to its branch only (`production` → `main`, `staging` → `staging`, `development` → `dev`). Add **required reviewers** to `production`; otherwise every push to `main` deploys production without approval.
3. **Add the secrets to each environment:**

| Secret | Required | Content |
|---|---|---|
| `REMOTE_STATE_ENV` | yes | `KEY=value` lines for the state backend (no quotes, no endpoint, no `test` keys). See the example below. |
| `AWS_DEPLOY_ROLE_ARN` | yes | ARN of the deploy role assumed through GitHub OIDC (created by `aws_role/`) |
| `TFVARS_JSON` | no | Terraform variable overrides, e.g. `{"project_name": "static-website"}` |

Example `REMOTE_STATE_ENV` for the `production` environment:

```
PROD_REMOTE_STORAGE_AWS_S3_BUCKET=static-website-tfstate-<account_id>
PROD_REMOTE_STORAGE_AWS_REGION=us-east-1
PROD_REMOTE_STORAGE_AWS_S3_KEY=static-website/terraform.tfstate
```

`<account_id>` is the bucket that **Create Deploy Role** creates by default (`<project_name>-tfstate-<account_id>`). All three stages can share it: each workspace's state goes to its own key (`env:/<stage>/...`). Use `DEV_` and `STAGING_` as the prefix in the other environments.

Optional repository **variable**: `AWS_REGION` (default `us-east-1`).

How the workflow handles the secrets:
- It writes them to the runner's temp folder, outside the checkout, and deletes them, together with `.terraform/`, at the end.
- `deploy.sh` refuses to run in CI if an emulator endpoint (`AWS_ENDPOINT_URL` / `REMOTE_STORAGE_AWS_S3_ENDPOINT`) is set.

### `scripts/deploy.sh`

The non-interactive entry point that the Deploy workflow calls. You can also run it locally:

```bash
ENVIRONMENT=staging ACTION=plan ./scripts/deploy.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `ENVIRONMENT` | (required) | `development`, `staging` or `production` |
| `ACTION` | `plan` | `plan`, `apply` or `destroy`. `apply` and `destroy` run with `-auto-approve`. |
| `ENV_FILE` | `infrastructure/.env` | `KEY=value` file with the `*_REMOTE_STORAGE_*` settings. CI writes `REMOTE_STATE_ENV` here. |
| `TFVARS_FILE` | none | `.tfvars` or `.tfvars.json` file with variable overrides. CI writes `TFVARS_JSON` here. |

### Deploy role permissions

The IAM role is created by [`aws_role/`](../aws_role/README.md), which documents its trust policy (including GitHub's immutable subject) and permissions. In short, it can:
- read and write only this stack's state keys;
- use `s3:*` only on the `<project>-<stage>-<account>` website buckets;
- use the CloudFront actions this stack needs;
- do nothing in IAM.

## Troubleshooting

- **`Workspace "default" is not a configured stage`**: run through `scripts/terraform-run.sh` with `ENVIRONMENT` set, or run `terraform workspace select <stage>`.
- **`Backend configuration changed`**: re-run with `TF_INIT_RECONFIGURE=true`.
- **`ERROR: DEV_REMOTE_STORAGE_AWS_S3_BUCKET is required`**: set the variable, or create `.env` from `.env.example`.
- **Site still shows old content**: the cache invalidation runs on apply when files change. To clear it by hand, run `aws cloudfront create-invalidation --distribution-id <id> --paths '/*'`.
- **Secrets on disk**: backend credentials passed by `terraform-init.sh` are saved in `.terraform/terraform.tfstate`. That folder is gitignored, so don't commit or share it. Where you can, prefer an AWS profile or role over static keys.
