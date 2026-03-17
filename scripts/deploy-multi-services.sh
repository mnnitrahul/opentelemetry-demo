#!/usr/bin/env bash
# Builds and deploys the simple multi-platform services (ECS, Lambda, EC2).
# Run AFTER deploy-multi-platform.sh has created the shared stack and EKS cluster.
# Usage: ./scripts/deploy-multi-services.sh [--region us-east-1]

set -euo pipefail

REGION="${1:---region}"
if [[ "${REGION}" == "--region" ]]; then
  REGION="${2:-us-east-1}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"
CFN_DIR="${SCRIPT_DIR}/cfn"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "============================================"
echo " Multi-Platform Services Deploy"
echo " Region: ${REGION}"
echo " Account: ${ACCOUNT_ID}"
echo "============================================"

# Login to ECR
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_REGISTRY}" 2>/dev/null

# ---------------------------------------------------------------------------
# Step 1: Build and push ECS order-processor image
# ---------------------------------------------------------------------------
echo ""
echo "[1/5] Building ECS order-processor..."
ECS_REPO="otel-demo-multi/order-processor"
ECS_IMAGE="${ECR_REGISTRY}/${ECS_REPO}:latest"

if ! aws ecr describe-repositories --repository-names "${ECS_REPO}" --region "${REGION}" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "${ECS_REPO}" --region "${REGION}" --no-cli-pager > /dev/null
fi

docker build -t "${ECS_IMAGE}" "${REPO_ROOT}/src/multi-platform/ecs/" 2>&1
docker push "${ECS_IMAGE}" 2>&1
echo "  Pushed: ${ECS_IMAGE}"

# ---------------------------------------------------------------------------
# Step 2: Build and push EC2 inventory-service image
# ---------------------------------------------------------------------------
echo ""
echo "[2/5] Building EC2 inventory-service..."
EC2_REPO="otel-demo-multi/inventory-service"
EC2_IMAGE="${ECR_REGISTRY}/${EC2_REPO}:latest"

if ! aws ecr describe-repositories --repository-names "${EC2_REPO}" --region "${REGION}" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "${EC2_REPO}" --region "${REGION}" --no-cli-pager > /dev/null
fi

docker build -t "${EC2_IMAGE}" "${REPO_ROOT}/src/multi-platform/ec2/" 2>&1
docker push "${EC2_IMAGE}" 2>&1
echo "  Pushed: ${EC2_IMAGE}"

# ---------------------------------------------------------------------------
# Step 2b: Build and push Java order-processor image
# ---------------------------------------------------------------------------
echo ""
echo "[2b/6] Building Java order-processor..."
JAVA_REPO="otel-demo-multi/order-processor-java"
JAVA_IMAGE="${ECR_REGISTRY}/${JAVA_REPO}:latest"

if ! aws ecr describe-repositories --repository-names "${JAVA_REPO}" --region "${REGION}" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "${JAVA_REPO}" --region "${REGION}" --no-cli-pager > /dev/null
fi

docker build -t "${JAVA_IMAGE}" "${REPO_ROOT}/src/multi-platform/ecs-java/" 2>&1
docker push "${JAVA_IMAGE}" 2>&1
echo "  Pushed: ${JAVA_IMAGE}"

# ---------------------------------------------------------------------------
# Step 2c: Build and push Vert.x order-processor image
# ---------------------------------------------------------------------------
echo ""
echo "[2c/6] Building Vert.x order-processor..."
VERTX_REPO="otel-demo-multi/order-processor-vertx"
VERTX_IMAGE="${ECR_REGISTRY}/${VERTX_REPO}:latest"

if ! aws ecr describe-repositories --repository-names "${VERTX_REPO}" --region "${REGION}" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "${VERTX_REPO}" --region "${REGION}" --no-cli-pager > /dev/null
fi

docker build -t "${VERTX_IMAGE}" "${REPO_ROOT}/src/multi-platform/ecs-vertx/" 2>&1
docker push "${VERTX_IMAGE}" 2>&1
echo "  Pushed: ${VERTX_IMAGE}"

# ---------------------------------------------------------------------------
# Step 2d: Build and push caller image
# ---------------------------------------------------------------------------
echo ""
echo "  Building caller service..."
CALLER_REPO="otel-demo-multi/caller"
CALLER_IMAGE="${ECR_REGISTRY}/${CALLER_REPO}:latest"

if ! aws ecr describe-repositories --repository-names "${CALLER_REPO}" --region "${REGION}" > /dev/null 2>&1; then
  aws ecr create-repository --repository-name "${CALLER_REPO}" --region "${REGION}" --no-cli-pager > /dev/null
fi

docker build -t "${CALLER_IMAGE}" "${REPO_ROOT}/src/multi-platform/caller/" 2>&1
docker push "${CALLER_IMAGE}" 2>&1
echo "  Pushed: ${CALLER_IMAGE}"

# ---------------------------------------------------------------------------
# Step 3: Package and upload Lambda function
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Packaging Lambda function..."
LAMBDA_DIR="${REPO_ROOT}/src/multi-platform/lambda"
LAMBDA_ZIP="/tmp/payment_processor.zip"
LAMBDA_BUCKET=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text)

# Install deps and zip — include ALL Lambda functions
LAMBDA_BUILD="/tmp/lambda-build"
rm -rf "${LAMBDA_BUILD}" "${LAMBDA_ZIP}"
mkdir -p "${LAMBDA_BUILD}"
pip install -r "${LAMBDA_DIR}/requirements.txt" -t "${LAMBDA_BUILD}" --quiet 2>/dev/null
cp "${LAMBDA_DIR}/payment_processor.py" "${LAMBDA_BUILD}/"
cp "${LAMBDA_DIR}/sqs_consumer.py" "${LAMBDA_BUILD}/"
cp "${LAMBDA_DIR}/sns_consumer.py" "${LAMBDA_BUILD}/"
cp "${LAMBDA_DIR}/kinesis_consumer.py" "${LAMBDA_BUILD}/"
cp "${LAMBDA_DIR}/msk_consumer.py" "${LAMBDA_BUILD}/"
(cd "${LAMBDA_BUILD}" && zip -r "${LAMBDA_ZIP}" . -q)

aws s3 cp "${LAMBDA_ZIP}" "s3://${LAMBDA_BUCKET}/lambda/payment_processor.zip" --region "${REGION}"
echo "  Uploaded to s3://${LAMBDA_BUCKET}/lambda/payment_processor.zip"

# ---------------------------------------------------------------------------
# Step 4: Deploy CFN stacks
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Deploying CFN stacks..."

# Helper: wait for stack if it's being deleted
wait_for_stack_delete() {
  local stack_name="$1"
  local status
  status=$(aws cloudformation describe-stacks --stack-name "${stack_name}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
  if [[ "${status}" == "DELETE_IN_PROGRESS" ]]; then
    echo "  Waiting for ${stack_name} deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name "${stack_name}" --region "${REGION}" 2>/dev/null || true
  elif [[ "${status}" == "ROLLBACK_COMPLETE" || "${status}" == "ROLLBACK_FAILED" ]]; then
    echo "  Deleting ${stack_name} (${status})..."
    aws cloudformation delete-stack --stack-name "${stack_name}" --region "${REGION}"
    aws cloudformation wait stack-delete-complete --stack-name "${stack_name}" --region "${REGION}" 2>/dev/null || true
  fi
}

# No NLB needed — each ECS task has its own collector sidecar
VALKEY_ENDPOINT=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ValkeyEndpoint'].OutputValue" --output text 2>/dev/null || echo "")
S3_BUCKET=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text 2>/dev/null || echo "")

# Deploy Lambda stack
echo "  Deploying Lambda stack..."
wait_for_stack_delete "otel-demo-lambda"
aws cloudformation deploy --region "${REGION}" --stack-name otel-demo-lambda \
  --template-file "${CFN_DIR}/lambda.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "LambdaCodeBucket=${LAMBDA_BUCKET}" \
    "LambdaCodeKey=lambda/payment_processor.zip"

PAYMENT_ENDPOINT=$(aws cloudformation describe-stacks --stack-name otel-demo-lambda --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='PaymentEndpoint'].OutputValue" --output text)
echo "  Payment endpoint: ${PAYMENT_ENDPOINT}"

# Deploy ECS stack (both order-processor and inventory-service)
echo "  Deploying ECS stack..."
wait_for_stack_delete "otel-demo-ecs"

# Resolve MSK bootstrap brokers
MSK_CLUSTER_ARN=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='MskClusterArn'].OutputValue" --output text 2>/dev/null || echo "")
MSK_BOOTSTRAP=""
if [[ -n "${MSK_CLUSTER_ARN}" && "${MSK_CLUSTER_ARN}" != "None" ]]; then
  MSK_BOOTSTRAP=$(aws kafka get-bootstrap-brokers --region "${REGION}" --cluster-arn "${MSK_CLUSTER_ARN}" \
    --query 'BootstrapBrokerStringSaslIam' --output text 2>/dev/null || echo "")
  echo "  MSK Bootstrap: ${MSK_BOOTSTRAP}"
fi

aws cloudformation deploy --region "${REGION}" --stack-name otel-demo-ecs \
  --template-file "${CFN_DIR}/ecs.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "OrderProcessorImage=${ECS_IMAGE}" \
    "InventoryImage=${EC2_IMAGE}" \
    "OrderProcessorJavaImage=${JAVA_IMAGE}" \
    "OrderProcessorVertxImage=${VERTX_IMAGE}" \
    "PaymentEndpoint=${PAYMENT_ENDPOINT}" \
    "MskBootstrap=${MSK_BOOTSTRAP}"

ECS_ALB=$(aws cloudformation describe-stacks --stack-name otel-demo-ecs --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
echo "  Order processor: http://${ECS_ALB}/order"
echo "  Inventory: http://${ECS_ALB}/inventory"

# ---------------------------------------------------------------------------
# Step 5: Upload sample catalog to S3
# ---------------------------------------------------------------------------
echo ""
echo "[5/6] Uploading sample data..."
echo '{"products":[{"id":"OLJCESPC7Z","name":"Telescope","price":99.99}]}' | \
  aws s3 cp - "s3://${S3_BUCKET}/catalog.json" --region "${REGION}"

# ---------------------------------------------------------------------------
# Step 6: Deploy caller pod on EKS to generate cross-platform traffic
# ---------------------------------------------------------------------------
echo ""
echo "[6/6] Deploying cross-platform caller pod..."

cat > /tmp/caller.yaml << CALLEREOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi-platform-caller
  namespace: otel-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: multi-platform-caller
  template:
    metadata:
      labels:
        app: multi-platform-caller
    spec:
      containers:
      - name: caller
        image: ${CALLER_IMAGE}
        env:
        - name: OTEL_SERVICE_NAME
          value: multi-platform-caller
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: http://otel-collector:4317
        - name: OTEL_PROPAGATORS
          value: xray,tracecontext,baggage
        - name: ECS_ORDER_URL
          value: http://${ECS_ALB}/order
        - name: ECS_ORDER_JAVA_URL
          value: http://${ECS_ALB}/order-java
        - name: ECS_ORDER_VERTX_URL
          value: http://${ECS_ALB}/order-vertx
        - name: LAMBDA_PAYMENT_URL
          value: ${PAYMENT_ENDPOINT}
        - name: EC2_INVENTORY_URL
          value: http://${ECS_ALB}/inventory
CALLEREOF

kubectl apply -f /tmp/caller.yaml 2>/dev/null || echo "  Warning: could not deploy caller pod"

echo ""
echo "============================================"
echo " Multi-Platform Services Deployed!"
echo "============================================"
echo ""
echo "  ECS Order Processor: http://${ECS_ALB}/order"
echo "  ECS Inventory:       http://${ECS_ALB}/inventory"
echo "  Lambda Payment:      ${PAYMENT_ENDPOINT}"
echo ""
echo "  Test: curl http://${ECS_ALB}/order"
echo "============================================"
