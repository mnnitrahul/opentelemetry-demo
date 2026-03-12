# Multi-Platform OpenTelemetry Demo

Extends the [OpenTelemetry Astronomy Shop](https://opentelemetry.io/docs/demo/) demo
to run across multiple AWS compute platforms — EKS, ECS Fargate, and Lambda — with
unified cross-platform tracing via AWS X-Ray.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Service Inventory](#service-inventory)
- [AWS Resource Inventory](#aws-resource-inventory)
- [Trace Flow and Dependencies](#trace-flow-and-dependencies)
- [Prerequisites](#prerequisites)
- [Deployment Steps](#deployment-steps)
- [Accessing the UIs](#accessing-the-uis)
- [Configuration Changes and Rationale](#configuration-changes-and-rationale)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

Two separate EKS clusters run side by side:
- `otel-demo` — the original Astronomy Shop (unchanged)
- `otel-demo-multi` — the multi-platform version with `multi-` prefixed service names

```
EKS Cluster: otel-demo-multi
  multi-load-generator -> multi-frontend -> All OTel Demo Services
  multi-platform-caller (calls ECS + Lambda every 30s)
  OTel Collector -> Jaeger + Prometheus + X-Ray (sigv4auth)

ECS Fargate (behind ALB)
  multi-order-processor  + collector sidecar -> X-Ray
  multi-inventory-service + collector sidecar -> X-Ray

Lambda (behind REST API Gateway)
  multi-payment-processor  (API GW POST /payment)
  multi-sqs-consumer       (SQS trigger)
  multi-sns-consumer       (SNS trigger)
  multi-kinesis-consumer   (Kinesis trigger)
  All use ADOT Python layer for Application Signals

AWS Managed Services
  DynamoDB | S3 | SNS | SQS | Kinesis | ElastiCache | Aurora | MSK
```

## Service Inventory

### EKS Services (cluster: otel-demo-multi)

All standard OTel Demo services run on EKS with `multi-` prefixed names.
They use the in-cluster OTel Collector which exports to Jaeger, Prometheus, and X-Ray.

| Service | Language | OTEL_SERVICE_NAME | Port |
|---------|----------|-------------------|------|
| Frontend | Next.js | multi-frontend | 8080 |
| Frontend Proxy | Envoy | multi-frontend-proxy | 8080 |
| Load Generator | Python/Locust | multi-load-generator | 8089 |
| Cart | .NET | multi-cart | 8080 |
| Checkout | Go | multi-checkout | 8080 |
| Currency | C++ | multi-currency | 8080 |
| Email | Ruby | multi-email | 8080 |
| Payment | Node.js | multi-payment | 8080 |
| Product Catalog | Go | multi-product-catalog | 8080 |
| Product Reviews | Python | multi-product-reviews | 3551 |
| Recommendation | Python | multi-recommendation | 8080 |
| Shipping | Rust | multi-shipping | 8080 |
| Ad | Java | multi-ad | 8080 |
| Quote | PHP | multi-quote | 8080 |
| Accounting | .NET | multi-accounting | — |
| Fraud Detection | Kotlin | multi-fraud-detection | — |
| Flagd | Go | multi-flagd | 8013 |
| Image Provider | Go | multi-image-provider | 8081 |
| Platform Caller | Python | multi-platform-caller | — |

### ECS Fargate Services

Each ECS task runs the app container + an OTel Collector Contrib sidecar.
The sidecar uses `sigv4auth` to export traces to X-Ray's OTLP endpoint.

| Service | OTEL_SERVICE_NAME | Image Source | Port |
|---------|-------------------|-------------|------|
| Order Processor | multi-order-processor | `src/multi-platform/ecs/` | 8080 |
| Inventory Service | multi-inventory-service | `src/multi-platform/ec2/` | 8080 |

Both behind a single ALB: `/order*` -> order-processor, `/inventory*` -> inventory-service.

### Lambda Functions

All use ADOT Python layer for Application Signals and X-Ray active tracing.

| Function | OTEL_SERVICE_NAME | Trigger | Handler |
|----------|-------------------|---------|---------|
| Payment Processor | multi-payment-processor | REST API Gateway POST /payment | payment_processor.handler |
| SQS Consumer | multi-sqs-consumer | SQS queue (otel-demo-order-queue) | sqs_consumer.handler |
| SNS Consumer | multi-sns-consumer | SNS topic (otel-demo-order-topic) | sns_consumer.handler |
| Kinesis Consumer | multi-kinesis-consumer | Kinesis stream (otel-demo-order-stream) | kinesis_consumer.handler |

## AWS Resource Inventory

### CloudFormation Stacks

| Stack | Template | Resources |
|-------|----------|-----------|
| otel-demo-shared | `cfn/shared.yaml` | Security groups, IAM roles, DynamoDB, S3, SQS, SNS, Kinesis, ElastiCache, Aurora, MSK |
| otel-demo-ecs | `cfn/ecs.yaml` | ECS Fargate cluster, ALB, 2 task definitions with collector sidecars |
| otel-demo-lambda | `cfn/lambda.yaml` | 4 Lambda functions, REST API Gateway, event source mappings |

### AWS Managed Services

| Service | Resource Name | Used By | Purpose |
|---------|--------------|---------|---------|
| DynamoDB | otel-demo-orders | ECS order-processor, all Lambda functions | Order and payment records |
| S3 | otel-demo-assets-{account} | ECS order-processor, ECS inventory-service | Product catalog JSON |
| SNS | otel-demo-order-topic | ECS order-processor -> Lambda sns-consumer | Order event fan-out |
| SQS | otel-demo-order-queue | ECS order-processor -> Lambda sqs-consumer | Order event queue |
| Kinesis | otel-demo-order-stream | ECS order-processor -> Lambda kinesis-consumer | Order event stream |
| ElastiCache | otel-demo-valkey | ECS inventory-service | Inventory cache (Valkey, TLS required) |
| Aurora | otel-demo-postgres | EKS product-catalog, product-reviews | Product database (in-cluster pg used instead) |
| MSK | otel-demo-kafka | ECS order-processor (if MSK_BOOTSTRAP set) | Kafka messaging |

### IAM Roles

| Role | Used By | Key Permissions |
|------|---------|----------------|
| github-actions-otel-demo | GitHub Actions OIDC | Full demo deployment (EKS, ECS, Lambda, CFN, ECR, S3, SNS, SQS, Kinesis, DynamoDB, etc.) |
| otel-demo-ecs-task-role | ECS task containers | DynamoDB write, S3 read, X-Ray, SNS publish, SQS send, Kinesis put, MSK |
| otel-demo-ecs-execution-role | ECS Fargate agent | ECR pull, CloudWatch Logs |
| otel-demo-lambda-role | All Lambda functions | DynamoDB read/write, SQS consume, Kinesis read, X-Ray, CloudWatch Logs |
| otel-collector-xray-policy | EKS collector SA (IRSA) | X-Ray PutTraceSegments, GetSamplingRules |

## Trace Flow and Dependencies

```
multi-load-generator -> multi-frontend-proxy -> multi-frontend
  -> multi-checkout -> multi-cart, multi-currency, multi-payment,
                       multi-shipping, multi-product-catalog, multi-email

multi-platform-caller (EKS pod, every 30s)
  |-> ECS ALB /order -> multi-order-processor
  |     |-> DynamoDB (put order)
  |     |-> S3 (read catalog)
  |     |-> API Gateway /payment -> multi-payment-processor (Lambda) -> DynamoDB
  |     |-> ECS ALB /inventory -> multi-inventory-service -> ElastiCache, S3
  |     |-> SNS (publish) -> multi-sns-consumer (Lambda) -> DynamoDB
  |     |-> SQS (send) -> multi-sqs-consumer (Lambda) -> DynamoDB
  |     |-> Kinesis (put) -> multi-kinesis-consumer (Lambda) -> DynamoDB
  |-> API Gateway /payment -> multi-payment-processor (Lambda)
  |-> ECS ALB /inventory -> multi-inventory-service
```

### Telemetry Export Paths

| Platform | SDK | Destination |
|----------|-----|-------------|
| EKS services | Vanilla OTel SDK (per language) | In-cluster collector -> Jaeger + Prometheus + X-Ray |
| ECS services | Vanilla OTel Python SDK | Localhost sidecar collector -> X-Ray (sigv4auth) |
| Lambda functions | ADOT Python layer | X-Ray (native Lambda integration) |
| EKS caller | Vanilla OTel Python SDK | In-cluster collector -> Jaeger + Prometheus + X-Ray |

## Prerequisites

- AWS CLI v2 configured with credentials that can create IAM roles
- [eksctl](https://eksctl.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) v3
- Docker (for building ECS/caller images)
- Python 3.12+ with pip (for Lambda packaging)
- A GitHub repository (for CI/CD)

## Deployment Steps

### Step 1: Set Up GitHub Actions IAM (one-time per account)

Creates an OIDC identity provider and IAM role for GitHub Actions.

```bash
./scripts/setup-iam-oidc.sh <github-org/repo>
# Example: ./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo
```

Add the output role ARN as a GitHub Actions secret:
1. Go to `https://github.com/<org>/<repo>/settings/secrets/actions/new`
2. Name: `AWS_ROLE_ARN`
3. Value: the ARN (e.g., `arn:aws:iam::123456789012:role/github-actions-otel-demo`)

### Step 2: Deploy via GitHub Actions (recommended)

Push to `main` — auto-deploys everything:
```bash
git push origin main
```
Or: Actions -> "Multi-Platform Deploy" -> Run workflow -> `deploy`

### Step 3: Manual Deployment (alternative)

```bash
./scripts/setup-eks.sh                                          # Original EKS app
./scripts/deploy-multi-platform.sh --region us-east-1 --cluster otel-demo  # Multi EKS + shared CFN
./scripts/deploy-multi-services.sh --region us-east-1           # ECS + Lambda + caller
```

| Script | Creates |
|--------|---------|
| `setup-iam-oidc.sh` | OIDC provider, IAM policy, IAM role for GitHub Actions |
| `deploy-multi-platform.sh` | EKS cluster `otel-demo-multi`, shared CFN stack, IRSA, Helm release |
| `deploy-multi-services.sh` | ECR repos, Docker images, Lambda zip, ECS/Lambda CFN stacks, caller pod |

## Accessing the UIs

```bash
# Original app
aws eks update-kubeconfig --name otel-demo --region us-east-1
kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080

# Multi-platform app
aws eks update-kubeconfig --name otel-demo-multi --region us-east-1
kubectl port-forward -n otel-demo svc/frontend-proxy 8081:8080
```

| UI | Original (8080) | Multi (8081) |
|----|-----------------|--------------|
| Astronomy Shop | http://localhost:8080 | http://localhost:8081 |
| Grafana | http://localhost:8080/grafana | http://localhost:8081/grafana |
| Jaeger | http://localhost:8080/jaeger/ui | http://localhost:8081/jaeger/ui |
| X-Ray | [Console](https://us-east-1.console.aws.amazon.com/xray/home#/service-map) | Same |

## Configuration Changes and Rationale

### 1. Separate EKS Cluster (otel-demo-multi)
- **Change:** Multi-platform services run on a second EKS cluster instead of the original.
- **Reason:** Avoids Helm release conflicts. The original `otel-demo` release uses default service names; the multi-platform release needs `multi-` prefixed names which requires `useDefault.env: false` on every service.
- **Impact:** Two clusters run simultaneously. Both export to the same X-Ray account, so all services appear in one service map.

### 2. useDefault.env: false on All Helm Components
- **Change:** Every service in `helm-values-multi.yaml` sets `useDefault.env: false` and provides a complete env block.
- **Reason:** The OTel Demo Helm chart sets `OTEL_SERVICE_NAME` via Kubernetes `fieldRef` (pod label). This cannot be overridden with `envOverrides` because Kubernetes rejects duplicate env keys.
- **Impact:** Verbose Helm values file (~500 lines). Any new env var added upstream must be manually added here.

### 3. ECS Collector Sidecars (not shared NLB)
- **Change:** Each ECS task definition includes an `otel/opentelemetry-collector-contrib` sidecar container. No shared NLB.
- **Reason:** Sidecars are simpler and more reliable than routing OTLP traffic through an NLB to the EKS cluster. Each sidecar has its own `sigv4auth` config and uses the ECS task role for AWS credentials.
- **Impact:** Slightly higher ECS resource usage. ECS traces go directly to X-Ray, not through Jaeger/Prometheus.

### 4. Vanilla OTel SDK on ECS (not X-Ray SDK)
- **Change:** ECS services use `opentelemetry-sdk`, `opentelemetry-instrumentation-*` packages with OTLP exporter.
- **Reason:** User requirement to use vanilla OTel SDK everywhere except Lambda. The collector sidecar handles X-Ray export via `sigv4auth`.
- **Impact:** Auto-instrumentation covers Flask, requests, botocore, redis.

### 5. Lambda Uses ADOT Python Layer (Application Signals)
- **Change:** Lambda functions use the ADOT Python layer with `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument`.
- **Reason:** Lambda cannot reach an external OTel Collector. The ADOT layer auto-instruments and exports via X-Ray.
- **Impact:** Lambda functions also use `aws-xray-sdk` for `patch_all()` to trace boto3 calls.

### 6. REST API Gateway (v1) Instead of HTTP API (v2)
- **Change:** Payment processor Lambda is behind a REST API Gateway with `TracingEnabled: true`.
- **Reason:** REST API Gateway (v1) supports X-Ray tracing natively. HTTP API (v2) does not.
- **Impact:** API Gateway node appears in X-Ray traces between caller/ECS and Lambda.

### 7. OTEL_PROPAGATORS=xray,tracecontext,baggage on ECS and Caller
- **Change:** ECS order-processor and EKS caller set `OTEL_PROPAGATORS=xray,tracecontext,baggage`.
- **Reason:** API Gateway uses X-Ray trace header format. The `xray` propagator (from `opentelemetry-propagator-aws-xray`, open-source OTel Contrib) ensures trace context propagates through API Gateway.
- **Impact:** Requires `opentelemetry-propagator-aws-xray` pip package.

### 8. EKS Access Entry for GitHub Actions Role
- **Change:** Deploy scripts automatically create an EKS access entry for the deploying IAM role.
- **Reason:** Without an access entry, `kubectl` commands fail with 403 even with `eks:*` IAM permissions.
- **Impact:** Automated in scripts — no manual step needed in a new account.

### 9. All Lambda Functions in Single Zip
- **Change:** All 4 Lambda handlers packaged into one zip uploaded to S3.
- **Reason:** Simplifies deployment. Each Lambda references a different handler in the same zip.

### 10. ECS Jaeger/Prometheus Limitation
- **Change:** ECS services do NOT send traces to Jaeger or Prometheus (only X-Ray).
- **Reason:** ECS collector sidecars export directly to X-Ray. Connecting to EKS Jaeger would require an NLB.
- **Impact:** ECS traces visible only in X-Ray. EKS traces appear in both Jaeger and X-Ray.

### 11. MSK Serverless Not Used by EKS Services
- **Change:** EKS services use in-cluster Kafka pod. MSK available for ECS if `MSK_BOOTSTRAP` is set.
- **Reason:** MSK Serverless requires IAM auth + TLS which EKS Kafka clients don't support without code changes.

### 12. ElastiCache Serverless Requires TLS
- **Change:** ECS inventory-service connects to ElastiCache with `ssl=True`. EKS cart uses in-cluster valkey-cart.
- **Reason:** ElastiCache Serverless mandates TLS connections.

## Cleanup

**Destroy multi-platform only:**
```bash
./scripts/cleanup-multi-platform.sh --region us-east-1 --keep-eks
```

**Destroy everything:**
```bash
./scripts/cleanup-multi-platform.sh --region us-east-1
./scripts/cleanup-eks.sh
```

**Via GitHub Actions:** Actions -> "Multi-Platform Deploy" -> Run workflow -> `destroy`

**Manual (if scripts fail):** Delete in order: otel-demo-lambda -> otel-demo-ecs -> empty S3 -> otel-demo-shared -> eksctl delete cluster.

## Troubleshooting

**ECS tasks not starting:** Check CloudWatch Logs `/ecs/otel-demo-multi/*`. Verify ECR images and security groups.

**Traces not in X-Ray:** EKS: verify IRSA on `otel-collector` SA. ECS: check collector sidecar logs. Lambda: verify `TracingConfig.Mode: Active` and ADOT layer.

**API Gateway not in X-Ray:** Must be REST API Gateway (v1) with `TracingEnabled: true`. Caller/ECS must use `OTEL_PROPAGATORS=xray,tracecontext,baggage`.

**CloudFormation ROLLBACK_COMPLETE:** Deploy scripts handle this automatically.

**EKS access denied (403):** Scripts auto-create access entries. Manual: `aws eks create-access-entry` + `aws eks associate-access-policy`.

## File Structure

```
scripts/
  setup-iam-oidc.sh          # One-time: GitHub OIDC + IAM role
  deploy-multi-platform.sh    # EKS cluster + shared CFN + Helm
  deploy-multi-services.sh    # Docker build + ECS/Lambda CFN + caller pod
  cleanup-multi-platform.sh   # Tear down everything
  helm-values-multi.yaml      # Helm values with multi- prefixed services
  cfn/
    shared.yaml               # SGs, IAM, DynamoDB, S3, SQS, SNS, Kinesis, ElastiCache, Aurora, MSK
    ecs.yaml                  # ECS Fargate + ALB + collector sidecars
    lambda.yaml               # Lambda functions + REST API Gateway
src/multi-platform/
  ecs/app.py                  # Order processor (Flask + OTel SDK)
  ec2/app.py                  # Inventory service (Flask + OTel SDK)
  caller/app.py               # Platform caller (OTel SDK, calls ECS+Lambda)
  lambda/                     # Lambda handlers (X-Ray SDK)
.github/workflows/
  multi-platform-deploy.yml   # CI/CD: deploy on push to main
```
