#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Tears down the multi-platform OpenTelemetry Demo.
# Empties S3, deletes CloudFormation stacks in reverse dependency order,
# and optionally restores the EKS Helm release.
#
# Usage: ./scripts/cleanup-multi-platform.sh [--region us-east-1] [--keep-eks]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REGION="us-east-1"
KEEP_EKS=false
NAMESPACE="otel-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stack names — cleanup order (reverse of deploy): ec2 → lambda → ecs → shared
SHARED_STACK="otel-demo-shared"
ECS_STACK="otel-demo-ecs"
LAMBDA_STACK="otel-demo-lambda"
EC2_STACK="otel-demo-ec2"
EC2_PRICING_STACK="otel-demo-ec2-pricing"
CLEANUP_ORDER=("${EC2_PRICING_STACK}" "${EC2_STACK}" "${LAMBDA_STACK}" "${ECS_STACK}" "${SHARED_STACK}")

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --keep-eks)
      KEEP_EKS=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--region REGION] [--keep-eks]"
      exit 1
      ;;
  esac
done

echo "============================================"
echo " Multi-Platform Cleanup"
echo " Region:   ${REGION}"
echo " Keep EKS: ${KEEP_EKS}"
echo "============================================"
echo ""
echo "This will delete the following CloudFormation stacks:"
for stack in "${CLEANUP_ORDER[@]}"; do
  echo "  - ${stack}"
done
if [[ "${KEEP_EKS}" == "true" ]]; then
  echo ""
  echo "EKS Helm release will be restored to original values."
else
  echo ""
  echo "EKS Helm release will be uninstalled."
fi
echo ""
read -p "Are you sure you want to proceed? (y/N) " -r CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: check if a CloudFormation stack exists
# ---------------------------------------------------------------------------
stack_exists() {
  local stack_name="$1"
  local status
  status=$(aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${stack_name}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null) || return 1

  # A stack in DELETE_COMPLETE is effectively gone
  if [[ "${status}" == "DELETE_COMPLETE" ]]; then
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Helper: get a stack output value
# ---------------------------------------------------------------------------
get_stack_output() {
  local stack_name="$1"
  local output_key="$2"
  aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${stack_name}" \
    --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue" \
    --output text 2>/dev/null || echo ""
}

# ---------------------------------------------------------------------------
# Helper: delete a CloudFormation stack and wait for completion
# ---------------------------------------------------------------------------
delete_stack() {
  local stack_name="$1"

  if ! stack_exists "${stack_name}"; then
    echo "  Stack '${stack_name}' does not exist, skipping."
    return 0
  fi

  echo "  Deleting stack: ${stack_name}"
  aws cloudformation delete-stack \
    --region "${REGION}" \
    --stack-name "${stack_name}"

  echo "  Waiting for stack '${stack_name}' to be deleted..."
  if ! aws cloudformation wait stack-delete-complete \
    --region "${REGION}" \
    --stack-name "${stack_name}"; then
    echo ""
    echo "ERROR: Stack '${stack_name}' deletion failed or timed out."
    echo "Recent stack events:"
    aws cloudformation describe-stack-events \
      --region "${REGION}" \
      --stack-name "${stack_name}" \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
      --output table 2>/dev/null || true
    exit 1
  fi

  echo "  Stack '${stack_name}' deleted successfully."
}

# ---------------------------------------------------------------------------
# Step 1: Empty S3 bucket before deleting shared stack
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] Emptying S3 bucket..."

BUCKET_NAME=$(get_stack_output "${SHARED_STACK}" "AssetsBucketName")
if [[ -n "${BUCKET_NAME}" && "${BUCKET_NAME}" != "None" ]]; then
  echo "  Emptying bucket: ${BUCKET_NAME}"
  aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "${REGION}" 2>/dev/null || true
  echo "  Bucket emptied."
else
  echo "  No S3 bucket found (shared stack may not exist), skipping."
fi

# ---------------------------------------------------------------------------
# Step 2: Delete stacks in reverse dependency order
#         ec2 → lambda → ecs → shared
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] Deleting CloudFormation stacks in reverse dependency order..."

for stack in "${CLEANUP_ORDER[@]}"; do
  delete_stack "${stack}"
done

echo ""
echo "All CloudFormation stacks deleted."

# ---------------------------------------------------------------------------
# Step 3: Restore or uninstall EKS Helm release
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Handling EKS Helm release..."

if [[ "${KEEP_EKS}" == "true" ]]; then
  echo "  Restoring EKS Helm release to original values..."
  helm upgrade otel-demo open-telemetry/opentelemetry-demo \
    --namespace "${NAMESPACE}" \
    -f "${SCRIPT_DIR}/helm-values-xray.yaml" \
    --wait \
    --timeout 10m
  echo "  Helm release restored to helm-values-xray.yaml values."
else
  echo "  Uninstalling Helm release..."
  helm uninstall otel-demo --namespace "${NAMESPACE}" 2>/dev/null || true
  echo "  Helm release uninstalled."
fi

echo ""
echo "============================================"
echo " Multi-Platform Cleanup Complete!"
echo "============================================"
