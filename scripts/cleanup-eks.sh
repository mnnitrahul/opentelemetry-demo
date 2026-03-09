#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Tears down the EKS cluster and all associated AWS resources
# created by setup-eks.sh.
#
# Usage: ./scripts/cleanup-eks.sh

set -euo pipefail

CLUSTER_NAME="otel-demo"
REGION="us-east-1"
NAMESPACE="otel-demo"
XRAY_POLICY_NAME="otel-collector-xray-policy"
XRAY_ROLE_NAME="otel-collector-xray-role"
COLLECTOR_SA_NAME="otel-collector"

echo "============================================"
echo " OpenTelemetry Demo - EKS Cleanup"
echo " Region: ${REGION}"
echo " Cluster: ${CLUSTER_NAME}"
echo "============================================"
echo ""
read -p "This will DELETE the EKS cluster and all resources. Continue? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --------------------------------------------------
# 1. Uninstall Helm release
# --------------------------------------------------
echo ""
echo "[1/4] Uninstalling Helm release..."
helm uninstall otel-demo --namespace "${NAMESPACE}" 2>/dev/null || echo "Helm release not found, skipping."

# Wait for resources to terminate
echo "Waiting for pods to terminate..."
kubectl delete namespace "${NAMESPACE}" --wait=true 2>/dev/null || echo "Namespace already removed."

# --------------------------------------------------
# 2. Delete IRSA
# --------------------------------------------------
echo ""
echo "[2/4] Removing IAM service account..."
eksctl delete iamserviceaccount \
  --name "${COLLECTOR_SA_NAME}" \
  --namespace "${NAMESPACE}" \
  --cluster "${CLUSTER_NAME}" \
  --region "${REGION}" 2>/dev/null || echo "IRSA not found, skipping."

# --------------------------------------------------
# 3. Delete IAM policy
# --------------------------------------------------
echo ""
echo "[3/4] Removing IAM policy..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${XRAY_POLICY_NAME}"

aws iam delete-policy --policy-arn "${POLICY_ARN}" 2>/dev/null || echo "IAM policy not found, skipping."

# --------------------------------------------------
# 4. Delete EKS cluster
# --------------------------------------------------
echo ""
echo "[4/4] Deleting EKS cluster '${CLUSTER_NAME}'..."
echo "       This takes ~10-15 minutes."
eksctl delete cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --wait

echo ""
echo "============================================"
echo " Cleanup complete!"
echo "============================================"
