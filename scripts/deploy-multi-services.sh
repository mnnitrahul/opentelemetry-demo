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
# Step 3: Package and upload Lambda function
# ---------------------------------------------------------------------------
echo ""
echo "[3/5] Packaging Lambda function..."
LAMBDA_DIR="${REPO_ROOT}/src/multi-platform/lambda"
LAMBDA_ZIP="/tmp/payment_processor.zip"
LAMBDA_BUCKET=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text)

# Install deps and zip
LAMBDA_BUILD="/tmp/lambda-build"
rm -rf "${LAMBDA_BUILD}" "${LAMBDA_ZIP}"
mkdir -p "${LAMBDA_BUILD}"
pip install -r "${LAMBDA_DIR}/requirements.txt" -t "${LAMBDA_BUILD}" --quiet 2>/dev/null
cp "${LAMBDA_DIR}/payment_processor.py" "${LAMBDA_BUILD}/"
(cd "${LAMBDA_BUILD}" && zip -r "${LAMBDA_ZIP}" . -q)

aws s3 cp "${LAMBDA_ZIP}" "s3://${LAMBDA_BUCKET}/lambda/payment_processor.zip" --region "${REGION}"
echo "  Uploaded to s3://${LAMBDA_BUCKET}/lambda/payment_processor.zip"

# ---------------------------------------------------------------------------
# Step 4: Deploy CFN stacks
# ---------------------------------------------------------------------------
echo ""
echo "[4/5] Deploying CFN stacks..."

# Get OTel Collector endpoint (internal NLB or direct)
OTEL_ENDPOINT="https://xray.${REGION}.amazonaws.com"
VALKEY_ENDPOINT=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='ValkeyEndpoint'].OutputValue" --output text 2>/dev/null || echo "")
S3_BUCKET=$(aws cloudformation describe-stacks --stack-name otel-demo-shared --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AssetsBucketName'].OutputValue" --output text 2>/dev/null || echo "")

# Deploy Lambda stack
echo "  Deploying Lambda stack..."
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

# Deploy EC2 stack
echo "  Deploying EC2 stack..."
aws cloudformation deploy --region "${REGION}" --stack-name otel-demo-ec2 \
  --template-file "${CFN_DIR}/ec2-asg.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "InventoryImage=${EC2_IMAGE}" \
    "OtelCollectorEndpoint=${OTEL_ENDPOINT}" \
    "ValkeyAddr=${VALKEY_ENDPOINT}" \
    "S3BucketName=${S3_BUCKET}"

EC2_ALB=$(aws cloudformation describe-stacks --stack-name otel-demo-ec2 --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
INVENTORY_ENDPOINT="http://${EC2_ALB}"
echo "  Inventory endpoint: ${INVENTORY_ENDPOINT}"

# Deploy ECS stack
echo "  Deploying ECS stack..."
aws cloudformation deploy --region "${REGION}" --stack-name otel-demo-ecs \
  --template-file "${CFN_DIR}/ecs.yaml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "OrderProcessorImage=${ECS_IMAGE}" \
    "PaymentEndpoint=${PAYMENT_ENDPOINT}" \
    "InventoryEndpoint=${INVENTORY_ENDPOINT}" \
    "OtelCollectorEndpoint=${OTEL_ENDPOINT}"

ECS_ALB=$(aws cloudformation describe-stacks --stack-name otel-demo-ecs --region "${REGION}" \
  --query "Stacks[0].Outputs[?OutputKey=='AlbDnsName'].OutputValue" --output text)
echo "  Order processor: http://${ECS_ALB}/order"

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
        image: curlimages/curl:latest
        command: ["/bin/sh", "-c"]
        args:
        - |
          while true; do
            echo "--- Calling ECS order-processor ---"
            curl -s --max-time 15 http://${ECS_ALB}/order
            echo ""
            echo "--- Calling Lambda payment-processor ---"
            curl -s --max-time 10 -X POST ${PAYMENT_ENDPOINT} -H 'Content-Type: application/json' -d '{"order_id":"auto","amount":9.99}'
            echo ""
            echo "--- Calling EC2 inventory-service ---"
            curl -s --max-time 10 http://${EC2_ALB}/inventory
            echo ""
            sleep 30
          done
CALLEREOF

kubectl apply -f /tmp/caller.yaml 2>/dev/null || echo "  Warning: could not deploy caller pod (kubectl not configured for multi cluster)"

echo ""
echo "============================================"
echo " Multi-Platform Services Deployed!"
echo "============================================"
echo ""
echo "  ECS Order Processor: http://${ECS_ALB}/order"
echo "  Lambda Payment:      ${PAYMENT_ENDPOINT}"
echo "  EC2 Inventory:       ${INVENTORY_ENDPOINT}/inventory"
echo ""
echo "  Test: curl http://${ECS_ALB}/order"
echo "============================================"
