#!/usr/bin/env bash
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0
#
# Deploys the multi-platform OpenTelemetry Demo across EKS, ECS, Lambda, and EC2.
# Creates CloudFormation stacks in dependency order and updates Helm values.
#
# Usage: ./scripts/deploy-multi-platform.sh [--region us-east-1] [--cluster otel-demo]

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REGION="us-east-1"
CLUSTER_NAME="otel-demo"
MULTI_CLUSTER="${CLUSTER_NAME}-multi"
NAMESPACE="otel-demo"
HELM_RELEASE="otel-demo-multi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFN_DIR="${SCRIPT_DIR}/cfn"

# Stack names — deploy order: shared → ecs → lambda → ec2
SHARED_STACK="otel-demo-shared"
ECS_STACK="otel-demo-ecs"
LAMBDA_STACK="otel-demo-lambda"
EC2_STACK="otel-demo-ec2"
DEPLOY_ORDER=("${SHARED_STACK}" "${ECS_STACK}" "${LAMBDA_STACK}" "${EC2_STACK}")

# CFN template paths (relative to CFN_DIR)
declare -A STACK_TEMPLATES=(
  ["${SHARED_STACK}"]="shared.yaml"
  ["${ECS_STACK}"]="ecs.yaml"
  ["${LAMBDA_STACK}"]="lambda.yaml"
  ["${EC2_STACK}"]="ec2-asg.yaml"
)

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      REGION="$2"
      shift 2
      ;;
    --cluster)
      CLUSTER_NAME="$2"
      MULTI_CLUSTER="${CLUSTER_NAME}-multi"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--region REGION] [--cluster CLUSTER_NAME]"
      exit 1
      ;;
  esac
done

echo "============================================"
echo " Multi-Platform Deploy"
echo " Region:       ${REGION}"
echo " EKS Cluster:  ${MULTI_CLUSTER}"
echo "============================================"

# ---------------------------------------------------------------------------
# Step 1: Validate prerequisites
# ---------------------------------------------------------------------------
echo ""
echo "[1/8] Checking prerequisites..."
for cmd in aws kubectl helm eksctl; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "ERROR: '${cmd}' is not installed. Please install it first."
    exit 1
  fi
done
echo "All prerequisites found."

# ---------------------------------------------------------------------------
# Step 2: Create separate EKS cluster for multi-platform app
# ---------------------------------------------------------------------------
echo ""
echo "[2/8] Creating EKS cluster '${MULTI_CLUSTER}' (skip if exists)..."

if aws eks describe-cluster --name "${MULTI_CLUSTER}" --region "${REGION}" &>/dev/null; then
  echo "  Cluster '${MULTI_CLUSTER}' already exists. Skipping creation."
else
  echo "  Creating cluster (this takes ~15 minutes)..."
  eksctl create cluster \
    --name "${MULTI_CLUSTER}" \
    --region "${REGION}" \
    --nodes 3 \
    --node-type m5.xlarge \
    --with-oidc \
    --managed
fi

aws eks update-kubeconfig --name "${MULTI_CLUSTER}" --region "${REGION}"

# ---------------------------------------------------------------------------
# Step 3: Discover EKS VPC networking
# ---------------------------------------------------------------------------
echo ""
echo "[3/8] Discovering EKS VPC networking..."

CLUSTER_INFO=$(aws eks describe-cluster \
  --name "${MULTI_CLUSTER}" \
  --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig' \
  --output json)

VPC_ID=$(echo "${CLUSTER_INFO}" | python3 -c "import sys,json; print(json.load(sys.stdin)['vpcId'])")
EKS_SG=$(echo "${CLUSTER_INFO}" | python3 -c "import sys,json; print(json.load(sys.stdin)['clusterSecurityGroupId'])")

echo "  VPC ID:     ${VPC_ID}"
echo "  Cluster SG: ${EKS_SG}"

# Discover subnets — partition into public and private
# Public subnets have a route to an internet gateway; private do not.
ALL_SUBNETS=$(aws ec2 describe-subnets \
  --region "${REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[*].SubnetId' \
  --output json)

PUBLIC_SUBNETS=()
PRIVATE_SUBNETS=()

for SUBNET_ID in $(echo "${ALL_SUBNETS}" | python3 -c "import sys,json; [print(s) for s in json.load(sys.stdin)]"); do
  # Check if the subnet's route table has a route to an internet gateway
  HAS_IGW=$(aws ec2 describe-route-tables \
    --region "${REGION}" \
    --filters "Name=association.subnet-id,Values=${SUBNET_ID}" \
    --query 'RouteTables[*].Routes[?GatewayId!=`null` && starts_with(GatewayId, `igw-`)].GatewayId' \
    --output text 2>/dev/null || true)

  # If no explicit association, check the main route table
  if [[ -z "${HAS_IGW}" ]]; then
    HAS_IGW=$(aws ec2 describe-route-tables \
      --region "${REGION}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=association.main,Values=true" \
      --query 'RouteTables[*].Routes[?GatewayId!=`null` && starts_with(GatewayId, `igw-`)].GatewayId' \
      --output text 2>/dev/null || true)
  fi

  if [[ -n "${HAS_IGW}" ]]; then
    PUBLIC_SUBNETS+=("${SUBNET_ID}")
  else
    PRIVATE_SUBNETS+=("${SUBNET_ID}")
  fi
done

if [[ ${#PRIVATE_SUBNETS[@]} -lt 2 ]]; then
  echo "ERROR: Need at least 2 private subnets, found ${#PRIVATE_SUBNETS[@]}"
  exit 1
fi
if [[ ${#PUBLIC_SUBNETS[@]} -lt 2 ]]; then
  echo "ERROR: Need at least 2 public subnets, found ${#PUBLIC_SUBNETS[@]}"
  exit 1
fi

PRIVATE_SUBNET_1="${PRIVATE_SUBNETS[0]}"
PRIVATE_SUBNET_2="${PRIVATE_SUBNETS[1]}"
PUBLIC_SUBNET_1="${PUBLIC_SUBNETS[0]}"
PUBLIC_SUBNET_2="${PUBLIC_SUBNETS[1]}"

echo "  Private subnets: ${PRIVATE_SUBNET_1}, ${PRIVATE_SUBNET_2}"
echo "  Public subnets:  ${PUBLIC_SUBNET_1}, ${PUBLIC_SUBNET_2}"

# ---------------------------------------------------------------------------
# Helper: deploy a CloudFormation stack and wait for completion
# ---------------------------------------------------------------------------
deploy_stack() {
  local stack_name="$1"
  local template_file="$2"
  shift 2
  local params=("$@")

  echo ""
  echo "  Deploying stack: ${stack_name}"
  echo "  Template:        ${template_file}"

  # If the stack is in ROLLBACK_COMPLETE, delete it first — it can't be updated.
  local current_status
  current_status=$(aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${stack_name}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "DOES_NOT_EXIST")

  if [[ "${current_status}" == "ROLLBACK_COMPLETE" || "${current_status}" == "ROLLBACK_FAILED" ]]; then
    echo "  Stack is in ${current_status} state. Deleting before re-create..."
    aws cloudformation delete-stack --region "${REGION}" --stack-name "${stack_name}"
    aws cloudformation wait stack-delete-complete --region "${REGION}" --stack-name "${stack_name}"
    echo "  Deleted."
  elif [[ "${current_status}" == "DELETE_IN_PROGRESS" ]]; then
    echo "  Stack is in DELETE_IN_PROGRESS. Waiting for deletion to complete..."
    aws cloudformation wait stack-delete-complete --region "${REGION}" --stack-name "${stack_name}"
    echo "  Deleted."
  fi

  echo ""
  echo "  Deploying stack: ${stack_name}"
  echo "  Template:        ${template_file}"

  local deploy_cmd=(
    aws cloudformation deploy
    --region "${REGION}"
    --stack-name "${stack_name}"
    --template-file "${template_file}"
    --capabilities CAPABILITY_NAMED_IAM
    --no-fail-on-empty-changeset
  )

  if [[ ${#params[@]} -gt 0 ]]; then
    deploy_cmd+=(--parameter-overrides "${params[@]}")
  fi

  if ! "${deploy_cmd[@]}"; then
    echo ""
    echo "ERROR: Stack '${stack_name}' deployment failed."
    echo "Recent stack events:"
    aws cloudformation describe-stack-events \
      --region "${REGION}" \
      --stack-name "${stack_name}" \
      --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
      --output table 2>/dev/null || true
    exit 1
  fi

  # Wait for stack to reach a stable state
  echo "  Waiting for stack '${stack_name}' to stabilize..."
  if ! aws cloudformation wait stack-create-complete \
    --region "${REGION}" \
    --stack-name "${stack_name}" 2>/dev/null; then
    # Might be an update, try update-complete waiter
    if ! aws cloudformation wait stack-update-complete \
      --region "${REGION}" \
      --stack-name "${stack_name}" 2>/dev/null; then
      # Check if the stack is actually in a good state already
      local stack_status
      stack_status=$(aws cloudformation describe-stacks \
        --region "${REGION}" \
        --stack-name "${stack_name}" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")

      case "${stack_status}" in
        CREATE_COMPLETE|UPDATE_COMPLETE)
          echo "  Stack '${stack_name}' is in ${stack_status} state."
          ;;
        *)
          echo ""
          echo "ERROR: Stack '${stack_name}' is in unexpected state: ${stack_status}"
          echo "Recent failure events:"
          aws cloudformation describe-stack-events \
            --region "${REGION}" \
            --stack-name "${stack_name}" \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED` || ResourceStatus==`UPDATE_FAILED` || ResourceStatus==`ROLLBACK_COMPLETE`].[LogicalResourceId,ResourceStatusReason]' \
            --output table 2>/dev/null || true
          exit 1
          ;;
      esac
    fi
  fi

  echo "  Stack '${stack_name}' deployed successfully."
}

# Helper: get a stack output value
get_stack_output() {
  local stack_name="$1"
  local output_key="$2"
  aws cloudformation describe-stacks \
    --region "${REGION}" \
    --stack-name "${stack_name}" \
    --query "Stacks[0].Outputs[?OutputKey=='${output_key}'].OutputValue" \
    --output text
}

# ---------------------------------------------------------------------------
# Step 3: Deploy CloudFormation stacks in dependency order
#         shared → ecs → lambda → ec2
# ---------------------------------------------------------------------------
echo ""
echo "[4/8] Deploying CloudFormation stacks..."

# --- Shared stack ---
deploy_stack "${SHARED_STACK}" "${CFN_DIR}/${STACK_TEMPLATES[${SHARED_STACK}]}" \
  "VpcId=${VPC_ID}" \
  "PrivateSubnet1=${PRIVATE_SUBNET_1}" \
  "PrivateSubnet2=${PRIVATE_SUBNET_2}" \
  "PublicSubnet1=${PUBLIC_SUBNET_1}" \
  "PublicSubnet2=${PUBLIC_SUBNET_2}" \
  "EksClusterSG=${EKS_SG}"

# --- ECS stack (depends on shared) ---
# Resolve MSK bootstrap brokers (not available as CFN attribute)
MSK_CLUSTER_ARN=$(get_stack_output "${SHARED_STACK}" "MskClusterArn")
MSK_BOOTSTRAP=""
if [[ -n "${MSK_CLUSTER_ARN}" && "${MSK_CLUSTER_ARN}" != "None" ]]; then
  echo "  Resolving MSK bootstrap brokers..."
  MSK_BOOTSTRAP=$(aws kafka get-bootstrap-brokers \
    --region "${REGION}" \
    --cluster-arn "${MSK_CLUSTER_ARN}" \
    --query 'BootstrapBrokerStringSaslIam' \
    --output text 2>/dev/null || echo "")
  echo "  MSK Bootstrap: ${MSK_BOOTSTRAP}"
fi

deploy_stack "${ECS_STACK}" "${CFN_DIR}/${STACK_TEMPLATES[${ECS_STACK}]}" \
  "MskBootstrapBrokers=${MSK_BOOTSTRAP}"

# --- Mirror Lambda images from ghcr.io to ECR (Lambda only supports ECR) ---
echo ""
echo "  Mirroring Lambda images to ECR..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Login to ECR
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}" 2>/dev/null

LAMBDA_SERVICES=("adservice" "recommendationservice" "currencyservice" "quoteservice" "emailservice")
declare -A ECR_IMAGES

for svc in "${LAMBDA_SERVICES[@]}"; do
  REPO_NAME="otel-demo/${svc}"
  GHCR_IMAGE="ghcr.io/open-telemetry/demo:latest-${svc}"
  ECR_IMAGE="${ECR_REGISTRY}/${REPO_NAME}:latest"

  # Create ECR repo if not exists
  if ! aws ecr describe-repositories --repository-names "${REPO_NAME}" --region "${REGION}" > /dev/null 2>&1; then
    echo "  Creating ECR repo: ${REPO_NAME}"
    aws ecr create-repository --repository-name "${REPO_NAME}" --region "${REGION}" --no-cli-pager > /dev/null
  fi

  # Set ECR repo policy to allow Lambda to pull
  aws ecr set-repository-policy \
    --repository-name "${REPO_NAME}" \
    --region "${REGION}" \
    --policy-text '{"Version":"2012-10-17","Statement":[{"Sid":"LambdaECRPull","Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]}]}' \
    > /dev/null 2>&1 || echo "  Warning: could not set repo policy on ${REPO_NAME}"

  # Check if image already exists in ECR — skip pull/push if so
  if aws ecr describe-images --repository-name "${REPO_NAME}" --region "${REGION}" \
    --image-ids imageTag=latest > /dev/null 2>&1; then
    echo "  ${REPO_NAME}:latest already in ECR, skipping."
    ECR_IMAGES["${svc}"]="${ECR_IMAGE}"
    continue
  fi

  echo "  Pulling ${GHCR_IMAGE}..."
  if ! docker pull "${GHCR_IMAGE}" 2>&1; then
    echo "  ERROR: Failed to pull ${GHCR_IMAGE}"
    exit 1
  fi
  docker tag "${GHCR_IMAGE}" "${ECR_IMAGE}"
  echo "  Pushing to ${ECR_IMAGE}..."
  if ! docker push "${ECR_IMAGE}" 2>&1; then
    echo "  ERROR: Failed to push ${ECR_IMAGE}"
    exit 1
  fi

  ECR_IMAGES["${svc}"]="${ECR_IMAGE}"
done

# --- Lambda stack (depends on shared) ---
deploy_stack "${LAMBDA_STACK}" "${CFN_DIR}/${STACK_TEMPLATES[${LAMBDA_STACK}]}" \
  "AdImage=${ECR_IMAGES[adservice]}" \
  "RecommendationImage=${ECR_IMAGES[recommendationservice]}" \
  "CurrencyImage=${ECR_IMAGES[currencyservice]}" \
  "QuoteImage=${ECR_IMAGES[quoteservice]}" \
  "EmailImage=${ECR_IMAGES[emailservice]}"

# --- EC2 stack (depends on shared) ---
deploy_stack "${EC2_STACK}" "${CFN_DIR}/${STACK_TEMPLATES[${EC2_STACK}]}"

echo ""
echo "All CloudFormation stacks deployed successfully."

# ---------------------------------------------------------------------------
# Step 4: Resolve endpoints from stack outputs
# ---------------------------------------------------------------------------
echo ""
echo "[5/8] Resolving endpoints from stack outputs..."

ECS_ALB_DNS=$(get_stack_output "${ECS_STACK}" "AlbDnsName")
APIGW_URL=$(get_stack_output "${LAMBDA_STACK}" "ApiGatewayUrl")
EC2_ALB_DNS=$(get_stack_output "${EC2_STACK}" "AlbDnsName")

# Strip trailing slash and protocol from API Gateway URL if present
APIGW_URL="${APIGW_URL%/}"
APIGW_URL="${APIGW_URL#https://}"
APIGW_URL="${APIGW_URL#http://}"

echo "  ECS ALB DNS:     ${ECS_ALB_DNS}"
echo "  API Gateway URL: ${APIGW_URL}"
echo "  EC2 ALB DNS:     ${EC2_ALB_DNS}"

# ---------------------------------------------------------------------------
# Step 5: Generate updated Helm values via envsubst
# ---------------------------------------------------------------------------
echo ""
echo "[5/8] Generating Helm values with resolved endpoints..."

export ECS_ALB_DNS
export APIGW_URL
export EC2_ALB_DNS
export AWS_REGION="${REGION}"

# Managed service endpoints from shared stack
export AURORA_CONN_STR=$(get_stack_output "${SHARED_STACK}" "AuroraConnectionString")
export VALKEY_ENDPOINT=$(get_stack_output "${SHARED_STACK}" "ValkeyEndpoint")

# MSK_BOOTSTRAP was already resolved via API in step 4
# (get_stack_output returns the ARN, not the brokers)
export MSK_BOOTSTRAP

echo "  Aurora:  ${AURORA_CONN_STR:0:40}..."
echo "  MSK:     ${MSK_BOOTSTRAP}"
echo "  Valkey:  ${VALKEY_ENDPOINT}"

HELM_VALUES_TEMPLATE="${SCRIPT_DIR}/helm-values-multi.yaml"
HELM_VALUES_RESOLVED="/tmp/helm-values-multi-resolved.yaml"

envsubst < "${HELM_VALUES_TEMPLATE}" > "${HELM_VALUES_RESOLVED}"

echo "  Resolved values written to ${HELM_VALUES_RESOLVED}"

# ---------------------------------------------------------------------------
# Step 6: Set up IRSA for otel-collector on the multi cluster
# ---------------------------------------------------------------------------
echo ""
echo "[6/8] Setting up IRSA for ${NAMESPACE} on ${MULTI_CLUSTER}..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
XRAY_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/otel-collector-xray-policy"

# Create X-Ray IAM policy if not exists
if ! aws iam get-policy --policy-arn "${XRAY_POLICY_ARN}" &>/dev/null; then
  XRAY_POLICY_ARN=$(aws iam create-policy --policy-name otel-collector-xray-policy \
    --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["xray:PutTraceSegments","xray:PutTelemetryRecords","xray:GetSamplingRules","xray:GetSamplingTargets"],"Resource":"*"}]}' \
    --query 'Policy.Arn' --output text)
fi

# Create IRSA — uses a different role name to avoid conflict with original cluster
MULTI_XRAY_ROLE="otel-collector-xray-role-multi"
eksctl create iamserviceaccount \
  --name otel-collector \
  --namespace "${NAMESPACE}" \
  --cluster "${MULTI_CLUSTER}" \
  --region "${REGION}" \
  --attach-policy-arn "${XRAY_POLICY_ARN}" \
  --role-name "${MULTI_XRAY_ROLE}" \
  --approve \
  --override-existing-serviceaccounts || true

# Adopt SA for Helm
kubectl annotate serviceaccount otel-collector \
  -n "${NAMESPACE}" \
  meta.helm.sh/release-name="${HELM_RELEASE}" \
  meta.helm.sh/release-namespace="${NAMESPACE}" \
  --overwrite 2>/dev/null || true
kubectl label serviceaccount otel-collector \
  -n "${NAMESPACE}" \
  app.kubernetes.io/managed-by=Helm \
  --overwrite 2>/dev/null || true

echo "  IRSA configured for otel-collector in ${NAMESPACE}"

# ---------------------------------------------------------------------------
# Step 7: Helm install multi-platform release
# ---------------------------------------------------------------------------
echo ""
echo "[7/8] Installing Helm release ${HELM_RELEASE} in ${NAMESPACE}..."

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
helm repo update

# Uninstall first to avoid duplicate env key conflicts on upgrade
helm uninstall "${HELM_RELEASE}" --namespace "${NAMESPACE}" 2>/dev/null || true
sleep 5

helm install "${HELM_RELEASE}" open-telemetry/opentelemetry-demo \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${HELM_VALUES_RESOLVED}" \
  --wait \
  --timeout 15m

# Re-apply IRSA annotation (Helm install recreates the SA without it)
echo "  Re-applying IRSA annotation after Helm install..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
kubectl annotate serviceaccount otel-collector -n "${NAMESPACE}" \
  eks.amazonaws.com/role-arn="arn:aws:iam::${ACCOUNT_ID}:role/${MULTI_XRAY_ROLE}" \
  --overwrite 2>/dev/null || true
kubectl rollout restart daemonset/otel-collector-agent -n "${NAMESPACE}" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Step 7: Scale up ECS services (were created with DesiredCount=0)
# ---------------------------------------------------------------------------
echo ""
echo "[7/7] Scaling up ECS services..."

ECS_CLUSTER_NAME="otel-demo-ecs"
for svc in otel-demo-checkout otel-demo-cart otel-demo-product-catalog otel-demo-product-reviews; do
  echo "  Scaling ${svc} to 2 tasks..."
  aws ecs update-service \
    --region "${REGION}" \
    --cluster "${ECS_CLUSTER_NAME}" \
    --service "${svc}" \
    --desired-count 2 \
    --no-cli-pager > /dev/null 2>&1 || echo "  Warning: could not scale ${svc}"
done

echo "  ECS services scaled up. Tasks will start shortly."

echo ""
echo "============================================"
echo " Multi-Platform Deployment Complete!"
echo "============================================"
echo ""
echo "Two apps running:"
echo ""
echo "  1. Original EKS App (namespace: otel-demo)"
echo "     kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080"
echo ""
echo "  2. Multi-Platform App (namespace: ${NAMESPACE})"
echo "     EKS services: kubectl port-forward -n ${NAMESPACE} svc/frontend-proxy 8081:8080"
echo "     ECS ALB: http://${ECS_ALB_DNS}"
echo "     API Gateway: https://${APIGW_URL}"
echo "     EC2 ALB: http://${EC2_ALB_DNS}"
echo ""
echo "  X-Ray Service Map:"
echo "    https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/service-map"
echo ""
echo "To tear down multi-platform only: ./scripts/cleanup-multi-platform.sh --region ${REGION}"
