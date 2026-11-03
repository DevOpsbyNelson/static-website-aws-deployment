#!/bin/bash
# GitHub Actions helper: turns the environment's secrets into the files the other scripts read.
#   REMOTE_STORAGE_AWS_S3_BUCKET / _REGION / _S3_KEY -> <PREFIX>_REMOTE_STORAGE_* in ENV_FILE
#   TFVARS_JSON (optional)                           -> TFVARS_FILE
# Files go to RUNNER_TEMP (outside the checkout); their paths are exported through GITHUB_ENV.
# Usage (in a workflow step): ENVIRONMENT=production bash infrastructure/scripts/ci-write-env.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

: "${ENVIRONMENT:?ERROR: ENVIRONMENT is required (production | development | staging)}"
: "${RUNNER_TEMP:?ERROR: RUNNER_TEMP is not set (run this in GitHub Actions)}"
: "${GITHUB_ENV:?ERROR: GITHUB_ENV is not set (run this in GitHub Actions)}"

MISSING=""
for NAME in REMOTE_STORAGE_AWS_S3_BUCKET REMOTE_STORAGE_AWS_REGION REMOTE_STORAGE_AWS_S3_KEY; do
  [ -n "${!NAME:-}" ] || MISSING="$MISSING $NAME"
done
if [ -n "$MISSING" ]; then
  echo "::error::Set these secrets in the '$ENVIRONMENT' environment:$MISSING"
  exit 1
fi

PREFIX="$(resolve_environment_prefix "$ENVIRONMENT")" || {
  echo "::error::Unsupported environment '$ENVIRONMENT'"
  exit 1
}

umask 077
ENV_FILE="$RUNNER_TEMP/remote-state.$ENVIRONMENT.env"
{
  echo "${PREFIX}_REMOTE_STORAGE_AWS_S3_BUCKET=$REMOTE_STORAGE_AWS_S3_BUCKET"
  echo "${PREFIX}_REMOTE_STORAGE_AWS_REGION=$REMOTE_STORAGE_AWS_REGION"
  echo "${PREFIX}_REMOTE_STORAGE_AWS_S3_KEY=$REMOTE_STORAGE_AWS_S3_KEY"
} > "$ENV_FILE"
echo "ENV_FILE=$ENV_FILE" >> "$GITHUB_ENV"

if [ -n "${TFVARS_JSON:-}" ]; then
  TFVARS_FILE="$RUNNER_TEMP/$ENVIRONMENT.tfvars.json"
  printf '%s' "$TFVARS_JSON" | jq -e . > "$TFVARS_FILE"
  echo "TFVARS_FILE=$TFVARS_FILE" >> "$GITHUB_ENV"
fi
