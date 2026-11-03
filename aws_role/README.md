# GitHub Actions deploy role (OIDC)

This Terraform creates the IAM role that `.github/workflows/deploy.yml` assumes through GitHub OIDC. The role gets short-lived credentials, and no AWS keys are stored anywhere.

- **Trust:** only this repository's jobs that run in the listed GitHub environments can assume it:
  - with GitHub's immutable subject: `repo:<owner>@<owner_id>/<repo>@<repo_id>:environment:<name>`;
  - otherwise: `repo:<owner>/<repo>:environment:<name>`.
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
Job summary: AWS_DEPLOY_ROLE_ARN (repository secret) + REMOTE_STORAGE_* values (environment secrets)
```

| Input | Default | Meaning |
|---|---|---|
| `action` | `plan` | `plan`, `apply` or `destroy` |
| `github_repository` | this repo | Repository allowed to deploy (`owner/repo`) |
| `role_name` | `github-actions-static-website-deploy` | Name of the role |
| `project_name` | `static-website` | Must match `infrastructure/`'s `project_name` |
| `state_bucket` | `<project_name>-tfstate-<account id>` | Bucket for Terraform state, shared by this folder and `infrastructure/` |
| `immutable_subject` | `true` | Use GitHub's immutable subject (`owner@id/repo@id`); the IDs are read from GitHub at run time |
| `create_oidc_provider` | `false` | Create the GitHub OIDC provider (only if the account has none) |
| `aws_region` | `us-east-1` | Region of the state bucket |

The workflow always creates **one role for all three stages**. Its trust policy accepts the `development`, `staging` and `production` environments, the stages that `deploy.yml` maps branches to. Store its ARN once, as the **repository** secret `AWS_DEPLOY_ROLE_ARN`.

State keys inside the bucket:
- `aws-role/terraform.tfstate` for this folder.
- `env:/<stage>/static-website/terraform.tfstate` for `infrastructure/`, one per workspace.

### What each action does

| Action | Effect in AWS |
|---|---|
| `plan` | Nothing is created. It only shows what `apply` would do. The state bucket is the exception: it is created if missing, because Terraform needs it to plan. |
| `apply` | Creates or updates the deploy role and its policy. |
| `destroy` | Deletes the deploy role and its policy, **without a preview**. |

`destroy` leaves these alone:
- the OIDC provider, when `create_oidc_provider = false`;
- the bootstrap role;
- the state bucket;
- the deployed website, which belongs to `infrastructure/`.

After a `destroy`, `deploy.yml` fails until the role is created again. Use the same inputs as the `apply`, especially `state_bucket`.

## Terraform variables

`create_role.yml` sets these from its inputs. To run the folder by hand, pass them with `-var` or a `.tfvars` file.

| Variable | Default | Meaning |
|---|---|---|
| `github_repository` | (required) | `owner/repo` allowed to assume the role |
| `github_repository_owner_id` / `github_repository_id` | `null` | Numeric IDs for GitHub's immutable subject. Set both or neither. |
| `github_environments` | `["development","staging","production"]` | Environments allowed to assume the role; also the stage names used for website bucket ARNs |
| `state_bucket_names` | (required) | State buckets the role may use |
| `deploy_state_key` | `static-website/terraform.tfstate` | `infrastructure/`'s state key; the role may only touch it and `env:/*` |
| `project_name` | `static-website` | Prefix of the website buckets (`<project_name>-<stage>-<account>`) |
| `role_name` | `github-actions-static-website-deploy` | Name of the role |
| `create_oidc_provider` | `true` | Create the GitHub OIDC provider, or reuse the existing one when `false` |
| `max_session_duration` | `3600` | Maximum session length in seconds (3600–43200) |
| `aws_region` | `us-east-1` | Provider region; IAM itself is global |

Outputs:
- `role_arn`: the value for the `AWS_DEPLOY_ROLE_ARN` secret.
- `role_name`
- `oidc_provider_arn`
- `allowed_subjects`

### Running it locally (optional)

This needs credentials for the target account that can manage IAM, e.g. an SSO profile:

```bash
export AWS_PROFILE=<profile>
terraform init \
  -backend-config="bucket=<state bucket>" \
  -backend-config="key=aws-role/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform plan \
  -var 'github_repository=<owner>/<repo>' \
  -var 'github_repository_owner_id=<owner_id>' -var 'github_repository_id=<repo_id>' \
  -var 'state_bucket_names=["<state bucket>"]' \
  -var 'create_oidc_provider=false'
```

Get the IDs with `gh api repos/<owner>/<repo> --jq '.owner.id, .id'`.

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
5. **GitHub:** copy the values from the job summary:
   - repository secret `AWS_DEPLOY_ROLE_ARN`;
   - in each environment (`development`, `staging`, `production`):
     - `REMOTE_STORAGE_AWS_S3_BUCKET`
     - `REMOTE_STORAGE_AWS_REGION`
     - `REMOTE_STORAGE_AWS_S3_KEY`

To move to another AWS account, repeat these steps there: only the secrets change, not the code.

## Tests

```bash
terraform init -backend=false
terraform test   # mocked AWS provider: no credentials needed, nothing is created
```

The tests cover:
- the trust policy: subjects, audience, immutable IDs, and reusing an existing provider;
- the permission scoping: state keys only, `s3:*` only on the website buckets, no IAM actions;
- input validation.
