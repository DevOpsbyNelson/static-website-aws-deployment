# GitHub Actions deploy role (OIDC)

This Terraform creates the IAM role that `.github/workflows/deploy.yml` assumes through GitHub OIDC. The role gets short-lived credentials, and no AWS keys are stored anywhere.

- **Trust:** only this repository's jobs that run in the listed GitHub environments (`repo:<owner>/<repo>:environment:<name>`) can assume it.
- **Permissions:** least privilege for `infrastructure/`:
  - Its Terraform state keys only. Other keys in the state bucket, including this folder's own state, stay out of reach.
  - `s3:*` on the per-stage website buckets (`<project>-<stage>-<account>`) only.
  - The CloudFront actions the stack uses.
  - No IAM permissions.
- **OIDC provider:** set `create_oidc_provider = true` to create it, or `false` to reuse the account's existing one. AWS allows only one per account.

Nothing in this folder is specific to one AWS account: the account comes from the credentials it runs with.

## How it is run: `.github/workflows/create_role.yml`

The workflow is manual: **Actions → Create Deploy Role → Run workflow**.

```
aws-bootstrap environment (AWS_BOOTSTRAP_ROLE_ARN)
   │  OIDC
   ▼
create_role.yml ──▶ creates the state bucket if missing ──▶ terraform apply (this folder)
   │
   ▼
Job summary: AWS_DEPLOY_ROLE_ARN + REMOTE_STATE_ENV values to paste into each environment
```

| Input | Default | Meaning |
|---|---|---|
| `action` | `plan` | `plan`, `apply` or `destroy` |
| `github_repository` | this repo | Repository allowed to deploy (`owner/repo`) |
| `github_environments` | `development,staging,production` | Environments allowed to assume the role |
| `role_name` | `github-actions-static-website-deploy` | Name of the role |
| `project_name` | `static-website` | Must match `infrastructure/`'s `project_name` |
| `state_bucket` | `<project_name>-tfstate-<account id>` | Bucket for Terraform state, shared by this folder and `infrastructure/` |
| `immutable_subject` | `true` | Use GitHub's immutable subject (`owner@id/repo@id`); the IDs are read from GitHub at run time |
| `create_oidc_provider` | `false` | Create the GitHub OIDC provider (only if the account has none) |
| `aws_region` | `us-east-1` | Region of the state bucket |

State keys inside the bucket:
- `aws-role/terraform.tfstate` for this folder.
- `env:/<stage>/static-website/terraform.tfstate` for `infrastructure/`, one per workspace.

## One-time setup in a new AWS account

1. **AWS console:** if the account has no GitHub provider yet, add it under **IAM → Identity providers → Add provider**:
   - Type: **OpenID Connect**
   - URL: `https://token.actions.githubusercontent.com`
   - Audience: `sts.amazonaws.com`
2. **AWS console:** create the role **`github-actions-bootstrap`** under **IAM → Roles → Create role → Web identity**:
   - Provider: that one.
   - Audience: `sts.amazonaws.com`.
   - Leave the branch empty.
   - Permissions: `IAMFullAccess` and `AmazonS3FullAccess`.
   - Then edit its trust policy so `token.actions.githubusercontent.com:sub` is `repo:<owner>/<repo>:environment:aws-bootstrap`.
   - If the repository uses GitHub's **immutable subject**, the subject also contains the numeric IDs: `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:aws-bootstrap`. Check with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub`; its `sub_claim_prefix` is the exact `repo:...` part. `create_role.yml` handles this for the deploy role through its `immutable_subject` input, which is on by default.
3. **GitHub:** create the environment **`aws-bootstrap`**:
   - Required reviewers.
   - Deployment branches: `main`.
   - Secret `AWS_BOOTSTRAP_ROLE_ARN` = ARN of the role from step 2.
4. **GitHub:** run **Create Deploy Role** with `action = plan`, check the plan, then run it again with `action = apply`.
5. **GitHub:** copy the values from the job summary into each environment (`development`, `staging`, `production`):
   - `AWS_DEPLOY_ROLE_ARN`
   - `REMOTE_STATE_ENV`

To move to another AWS account, repeat these steps there: only the secrets change, not the code.

## Tests

```bash
terraform init -backend=false
terraform test   # mocked AWS provider: no credentials needed, nothing is created
```
