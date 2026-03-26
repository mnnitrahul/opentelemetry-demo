#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Creates an EKS cluster and deploys the OpenTelemetry Demo with X-Ray integration.
# Prerequisites: aws cli, eksctl, kubectl, helm
#
# Usage: ./scripts/setup-eks.sh

set -euo pipefail

CLUSTER_NAME="otel-demo"
REGION="us-east-1"
NODE_TYPE="m5.xlarge"
NODE_COUNT=3
NAMESPACE="otel-demo"
XRAY_POLICY_NAME="otel-collector-xray-policy"
XRAY_ROLE_NAME="otel-collector-xray-role"
COLLECTOR_SA_NAME="otel-collector"

echo "============================================"
echo " OpenTelemetry Demo - EKS Setup"
echo " Region: ${REGION}"
echo " Cluster: ${CLUSTER_NAME}"
echo "============================================"

# --------------------------------------------------
# 1. Verify prerequisites
# --------------------------------------------------
echo ""
echo "[1/7] Checking prerequisites..."
for cmd in aws eksctl kubectl helm; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: '$cmd' is not installed. Please install it first."
    exit 1
  fi
done
echo "All prerequisites found."

# --------------------------------------------------
# 2. Create EKS cluster
# --------------------------------------------------
echo ""
echo "[2/7] Creating EKS cluster '${CLUSTER_NAME}' in ${REGION}..."
echo "       This takes ~15-20 minutes."

eksctl create cluster \
  --name "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --nodes "${NODE_COUNT}" \
  --node-type "${NODE_TYPE}" \
  --with-oidc \
  --managed

echo "EKS cluster created."

# --------------------------------------------------
# 3. Create IAM policy for X-Ray
# --------------------------------------------------
echo ""
echo "[3/7] Creating IAM policy for X-Ray access..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${XRAY_POLICY_NAME}"

# Create policy only if it doesn't already exist
if ! aws iam get-policy --policy-arn "${POLICY_ARN}" &> /dev/null; then
  POLICY_ARN=$(aws iam create-policy \
    --policy-name "${XRAY_POLICY_NAME}" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "xray:PutTraceSegments",
            "xray:PutTelemetryRecords",
            "xray:GetSamplingRules",
            "xray:GetSamplingTargets"
          ],
          "Resource": "*"
        }
      ]
    }' \
    --query 'Policy.Arn' --output text)
  echo "IAM policy created: ${POLICY_ARN}"
else
  echo "IAM policy already exists: ${POLICY_ARN}"
fi

# --------------------------------------------------
# 4. Create IRSA for the OTel Collector service account
# --------------------------------------------------
echo ""
echo "[4/7] Creating IAM role for service account (IRSA)..."

eksctl create iamserviceaccount \
  --name "${COLLECTOR_SA_NAME}" \
  --namespace "${NAMESPACE}" \
  --cluster "${CLUSTER_NAME}" \
  --region "${REGION}" \
  --attach-policy-arn "${POLICY_ARN}" \
  --role-name "${XRAY_ROLE_NAME}" \
  --approve \
  --override-existing-serviceaccounts

echo "IRSA configured for ${COLLECTOR_SA_NAME} in ${NAMESPACE}."

# --------------------------------------------------
# 5. Add Helm repo
# --------------------------------------------------
echo ""
echo "[5/7] Adding OpenTelemetry Helm repo..."

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

# --------------------------------------------------
# 6. Deploy the demo via Helm
# --------------------------------------------------
echo ""
echo "[6/7] Deploying OpenTelemetry Demo..."

helm install otel-demo open-telemetry/opentelemetry-demo \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set opentelemetry-collector.serviceAccount.create=false \
  --set opentelemetry-collector.serviceAccount.name="${COLLECTOR_SA_NAME}" \
  --set opentelemetry-collector.config.extensions.sigv4auth.region="us-east-1" \
  --set opentelemetry-collector.config.extensions.sigv4auth.service=xray \
  --set 'opentelemetry-collector.config.exporters.otlphttp/xray.endpoint=https://xray.us-east-1.amazonaws.com' \
  --set 'opentelemetry-collector.config.exporters.otlphttp/xray.auth.authenticator=sigv4auth' \
  --set 'opentelemetry-collector.config.service.extensions[0]=health_check' \
  --set 'opentelemetry-collector.config.service.extensions[1]=sigv4auth' \
  --wait \
  --timeout 10m

# --------------------------------------------------
# 7. Verify deployment
# --------------------------------------------------
echo ""
echo "[7/7] Verifying deployment..."

kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/part-of=opentelemetry-demo \
  -n "${NAMESPACE}" \
  --timeout=300s 2>/dev/null || true

echo ""
echo "============================================"
echo " Deployment complete!"
echo "============================================"
echo ""
echo "Access the demo frontend:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/otel-demo-frontend-proxy 8080:8080"
echo "  Then open http://localhost:8080"
echo ""
echo "Access Grafana:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/otel-demo-grafana 3000:80"
echo "  Then open http://localhost:3000"
echo ""
echo "View X-Ray traces:"
echo "  https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/traces"
echo ""
echo "To clean up, run: ./scripts/cleanup-eks.sh"
