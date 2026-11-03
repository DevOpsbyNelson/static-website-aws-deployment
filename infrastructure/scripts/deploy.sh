#!/bin/bash
# Non-interactive deploy entry point (used by CI): plan, apply or destroy one environment.
# Usage: ENVIRONMENT=staging ACTION=apply ./scripts/deploy.sh
#
#   ENVIRONMENT  development | staging | production (required)
#   ACTION       plan (default) | apply | destroy
#   ENV_FILE     KEY=value file with the *_REMOTE_STORAGE_* settings (default: infrastructure/.env)
#   TFVARS_FILE  optional .tfvars or .tfvars.json file with Terraform variable overrides

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

ACTION="${ACTION:-plan}"
case "$ACTION" in
  plan) TF_ARGS=(plan -input=false) ;;
  apply | destroy) TF_ARGS=("$ACTION" -input=false -auto-approve) ;;
  *)
    echo "ERROR: unsupported ACTION '$ACTION' (expected plan | apply | destroy)" >&2
    exit 1
    ;;
esac

if [ -n "${TFVARS_FILE:-}" ]; then
  if [ ! -f "$TFVARS_FILE" ]; then
    echo "ERROR: TFVARS_FILE '$TFVARS_FILE' does not exist" >&2
    exit 1
  fi
  TF_ARGS+=("-var-file=$TFVARS_FILE")
fi

# CI deploys to real AWS only; an emulator endpoint here means a misconfigured secret.
if [ "${CI:-}" = "true" ] && [ -n "${AWS_ENDPOINT_URL:-}${REMOTE_STORAGE_AWS_S3_ENDPOINT:-}" ]; then
  echo "ERROR: AWS_ENDPOINT_URL / REMOTE_STORAGE_AWS_S3_ENDPOINT must not be set in CI" >&2
  exit 1
fi

exec "$SCRIPT_DIR/terraform-run.sh" "${TF_ARGS[@]}"
