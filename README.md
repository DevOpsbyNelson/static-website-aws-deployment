# static-website-aws-deployment

A React + Vite website deployed to AWS with Terraform and GitHub Actions. Production, staging and development each get their own S3 bucket and CloudFront distribution. Deploys authenticate to AWS through **GitHub OIDC**, so no AWS keys are stored anywhere.

```
Browser ──HTTPS──▶ CloudFront ──(Origin Access Control)──▶ private S3 bucket
```

## Repository layout

| Path | What it is | Docs |
|---|---|---|
| `website/` | React 19 + TypeScript + Vite site (pnpm) | [website/README.md](website/README.md) |
| `infrastructure/` | Terraform for the site: S3, CloudFront, file upload; one workspace per stage, S3 remote state | [infrastructure/README.md](infrastructure/README.md) |
| `aws_role/` | Terraform for the IAM role GitHub Actions assumes through OIDC | [aws_role/README.md](aws_role/README.md) |
| `.github/workflows/` | CI/CD pipelines (see below) | |

## Branches and stages

Each branch deploys its own stage:

| Branch | Stage (GitHub environment) |
|---|---|
| `main` | `production` |
| `staging` | `staging` |
| `dev` | `development` |

A push that changes `website/`, `infrastructure/` or the workflows runs the tests and then deploys that branch's stage. Pushes to any other branch run the tests only.

## Pipelines

| Workflow | Trigger | What it does |
|---|---|---|
| **Terraform Tests** (`tests.yml`) | every push and pull request; also called by Deploy | `terraform fmt`/`validate`, ShellCheck, Checkov (report-only) and `terraform test` (mocked AWS, no credentials) |
| **Deploy** (`deploy.yml`) | push to `main`/`staging`/`dev`, or manual (`plan`/`apply`, optional rollback `commit_sha`) | Builds the site (Node 26, pnpm), assumes the deploy role through OIDC, and runs Terraform for the branch's stage |
| **Destroy** (`destroy.yml`) | manual only | Deletes one stage's website infrastructure (S3 bucket with all file versions, CloudFront, OAC). You must type the stage name again to confirm. |
| **Create Deploy Role** (`create_role.yml`) | manual only | Creates, updates or destroys the deploy role (`plan`/`apply`/`destroy`) with the bootstrap role |

How the pieces fit together:

```
 Create Deploy Role (once per AWS account)
   aws-bootstrap environment ──OIDC──▶ bootstrap role ──▶ creates the deploy role + state bucket
        │
        ▼
 Deploy (every push to main / staging / dev)
   <stage> environment ──OIDC──▶ deploy role ──▶ terraform apply ──▶ S3 + CloudFront
```

- **`plan`** only shows what would change; nothing is created in AWS.
- **`apply`** makes the changes.
- **`destroy`** deletes what that Terraform created, without a preview.

### Rolling back the website

To redeploy an earlier version of the site:
1. Open **Actions → Deploy → Run workflow**.
2. Pick the branch of the stage, e.g. `main` for production.
3. Enter a **`commit_sha`** from that branch's history, short or full.

Only `website/` goes back to that commit. Terraform and the scripts stay at the branch's latest version, so a rollback never re-applies old infrastructure code. To undo an infrastructure change, use `git revert` and push.

Commits that aren't in the branch's history are rejected, so an unreviewed commit can't reach production. The job summary shows which commit was deployed.

The next normal push to that branch deploys its latest code again.

### Tearing everything down

Everything Terraform created goes away in this order:

1. **Actions → Destroy:** pick the stage and type its name again in `confirm`. Repeat for each stage that was deployed. This needs the deploy role, so it must come first.
2. **Actions → Create Deploy Role** with `action = destroy`: deletes the deploy role.

Terraform didn't create these, so they stay until you remove them by hand:
- the state bucket (`<project>-tfstate-<account_id>`);
- the `github-actions-bootstrap` role;
- the GitHub OIDC provider.

## Getting started (developers)

Prerequisites:
- Node 26 and pnpm 11
- Terraform >= 1.10 (CI uses 1.15)
- AWS CLI v2, only to run Terraform locally
- Docker, optional: an AWS emulator on `localhost:4566` for local runs

**Work on the website:**

```bash
cd website
pnpm install
pnpm dev          # local dev server
pnpm build        # production build in website/dist
pnpm lint
```

**Run the Terraform tests:** no AWS account needed.

```bash
cd infrastructure/modules/static-website && terraform init && terraform test
cd ../.. && terraform init -backend=false && terraform test
cd ../aws_role && terraform init -backend=false && terraform test
```

**Deploy:** merge or push to `dev`, `staging` or `main`. Pull requests run the tests only. To test the infrastructure locally against an AWS emulator, see [infrastructure/README.md → Local development](infrastructure/README.md#local-development-with-localstack-or-another-aws-emulator).

## First-time setup (maintainers, once per AWS account)

Nothing in the code is tied to a specific AWS account. The account comes from the role ARNs stored in GitHub secrets, so moving to another account means repeating these steps there.

1. **AWS console:** if the account has no GitHub OIDC provider yet, create one: **IAM → Identity providers → OpenID Connect**, URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
2. **AWS console:** create the role **`github-actions-bootstrap`**:
   - Type: Web identity.
   - Permissions: `IAMFullAccess` and `AmazonS3FullAccess`.
   - Trust policy `sub`: `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:aws-bootstrap`.

   This repository uses GitHub's **immutable OIDC subject**. Get the exact prefix with:
   ```bash
   gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
   ```
3. **GitHub → Settings → Environments:** create `aws-bootstrap`:
   - Required reviewers.
   - Deployment branch: `main`.
   - Secret `AWS_BOOTSTRAP_ROLE_ARN` = ARN of the role from step 2.
4. **GitHub → Actions → Create Deploy Role:**
   - Run it with `action = plan` and check the plan, then run it again with `apply`.
   - Leave `create_oidc_provider` off if step 1 was already done, and leave `immutable_subject` on.
5. **GitHub → Settings → Secrets and variables → Actions:** add the **repository** secret `AWS_DEPLOY_ROLE_ARN` = ARN of the deploy role, from the Create Deploy Role job summary. It lives outside the environments because one role serves all three stages.

   **GitHub → Settings → Environments:** create `production`, `staging` and `development`, and add these secrets to each:

   | Environment secret | Value (the same in all three environments) |
   |---|---|
   | `REMOTE_STORAGE_AWS_S3_BUCKET` | Terraform state bucket, e.g. `static-website-tfstate-<account_id>` |
   | `REMOTE_STORAGE_AWS_REGION` | Region of that bucket, e.g. `us-east-1` |
   | `REMOTE_STORAGE_AWS_S3_KEY` | `static-website/terraform.tfstate` |

   The secrets have no stage prefix: the environment they live in already decides the stage.

   Also set each environment's **deployment branch**: `production` → `main`, `staging` → `staging`, `development` → `dev`. Add **required reviewers** to `production`.
6. **Create the `staging` and `dev` branches** from `main`. Pushing to them deploys their stage.

Optional repository variable: `AWS_REGION` (default `us-east-1`).

## Troubleshooting

| Error in the "Configure AWS credentials" step | Cause |
|---|---|
| `Could not load credentials from any providers` | The role ARN secret is missing in that GitHub environment |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The role's trust policy `sub` doesn't match the token. Check the immutable subject prefix, the environment name, and the deployment branch rules |

More troubleshooting is in [infrastructure/README.md](infrastructure/README.md#troubleshooting).

## Learn more

- GitHub: *About security hardening with OpenID Connect* and *Configuring OpenID Connect in Amazon Web Services*
- AWS: *Create a role for OpenID Connect federation* and *IAM OIDC identity providers*
