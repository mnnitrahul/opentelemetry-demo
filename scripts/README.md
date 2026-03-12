# AWS Multi-Platform OpenTelemetry Demo

This is a fork of the [OpenTelemetry Astronomy Shop](https://opentelemetry.io/docs/demo/)
extended to run across AWS EKS, ECS Fargate, and Lambda with unified X-Ray tracing.

## Changes from Open-Source Version

### Infrastructure & CI/CD (new files)
- `scripts/setup-iam-oidc.sh` — GitHub OIDC provider + IAM role for CI/CD
- `scripts/setup-eks.sh` — EKS cluster creation + IRSA + Helm deploy
- `scripts/cleanup-eks.sh` — EKS teardown
- `scripts/deploy-multi-platform.sh` — Second EKS cluster + shared CloudFormation stack + Helm
- `scripts/deploy-multi-services.sh` — Docker build + ECS/Lambda CloudFormation stacks + caller pod
- `scripts/cleanup-multi-platform.sh` — Multi-platform teardown
- `scripts/cfn/shared.yaml` — Security groups, IAM roles, DynamoDB, S3, SQS, SNS, Kinesis, ElastiCache, Aurora, MSK
- `scripts/cfn/ecs.yaml` — ECS Fargate cluster, ALB, task definitions with OTel Collector sidecars
- `scripts/cfn/lambda.yaml` — 4 Lambda functions, REST API Gateway, event source mappings
- `scripts/cfn/ec2-asg.yaml` — (unused, kept for reference)
- `.github/workflows/eks-deploy.yml` — GitHub Actions: deploy/destroy original EKS app
- `.github/workflows/multi-platform-deploy.yml` — GitHub Actions: deploy/destroy both apps

### OTel Collector Configuration (new files)
- `scripts/helm-values-xray.yaml` — Helm overrides for original EKS app (sigv4auth, X-Ray exporter, resource detection, span metrics dimensions)
- `scripts/helm-values-multi.yaml` — Helm overrides for multi-platform app (all services with `multi-` prefixed names, `useDefault.env: false`)

### Application Code (new files)
- `src/multi-platform/ecs/app.py` — Order processor (Flask + vanilla OTel SDK)
- `src/multi-platform/ec2/app.py` — Inventory service (Flask + vanilla OTel SDK)
- `src/multi-platform/caller/app.py` — Cross-platform caller (OTel SDK, calls ECS + Lambda)
- `src/multi-platform/lambda/payment_processor.py` — Payment handler (X-Ray SDK)
- `src/multi-platform/lambda/sqs_consumer.py` — SQS consumer (X-Ray SDK)
- `src/multi-platform/lambda/sns_consumer.py` — SNS consumer (X-Ray SDK)
- `src/multi-platform/lambda/kinesis_consumer.py` — Kinesis consumer (X-Ray SDK)
- `src/multi-platform/*/Dockerfile` — Container images for ECS and caller
- `src/multi-platform/*/requirements.txt` — Python dependencies

### Modified Upstream Files
- `.env` — Added `AWS_REGION=us-east-1`
- `docker-compose.yml` — Passed `AWS_REGION` to collector container
- `src/otel-collector/otelcol-config-extras.yml` — X-Ray OTLP exporter for docker-compose

### Documentation (new files)
- `scripts/README.md` — This file (single entry point)

### No Upstream Code Modified
- Zero changes to any demo service source code (Go, Java, .NET, Python, Node.js, etc.)
- All OTel instrumentation uses vanilla open-source SDKs
- No AWS-proprietary SDKs in app code (except Lambda which uses X-Ray SDK)

## Architecture

```
EKS Cluster: otel-demo-multi
  multi-load-generator -> multi-frontend -> All OTel Demo Services
  multi-platform-caller (calls ECS + Lambda every 30s)
  OTel Collector -> Jaeger + Prometheus + X-Ray (sigv4auth via IRSA)

ECS Fargate (behind ALB, path-based routing)
  multi-order-processor  + OTel Collector Contrib sidecar -> X-Ray
  multi-inventory-service + OTel Collector Contrib sidecar -> X-Ray

Lambda (behind REST API Gateway with X-Ray tracing)
  multi-payment-processor  (API GW POST /payment)
  multi-sqs-consumer       (SQS trigger)
  multi-sns-consumer       (SNS trigger)
  multi-kinesis-consumer   (Kinesis trigger)
  All use ADOT Python layer for Application Signals

AWS Managed Services
  DynamoDB | S3 | SNS | SQS | Kinesis | ElastiCache | Aurora | MSK
```

Two EKS clusters run side by side:
- `otel-demo` — original Astronomy Shop (unchanged service names)
- `otel-demo-multi` — multi-platform version (`multi-` prefixed names)

## Service Inventory

### EKS Services (cluster: otel-demo-multi)

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

| Service | OTEL_SERVICE_NAME | Image Source |
|---------|-------------------|-------------|
| Order Processor | multi-order-processor | `src/multi-platform/ecs/` |
| Inventory Service | multi-inventory-service | `src/multi-platform/ec2/` |

Both behind a single ALB: `/order*` -> order-processor, `/inventory*` -> inventory-service.
Each task has an OTel Collector Contrib sidecar with sigv4auth -> X-Ray.

### Lambda Functions

| Function | OTEL_SERVICE_NAME | Trigger |
|----------|-------------------|---------|
| Payment Processor | multi-payment-processor | REST API Gateway POST /payment |
| SQS Consumer | multi-sqs-consumer | SQS queue (otel-demo-order-queue) |
| SNS Consumer | multi-sns-consumer | SNS topic (otel-demo-order-topic) |
| Kinesis Consumer | multi-kinesis-consumer | Kinesis stream (otel-demo-order-stream) |

All use ADOT Python layer + X-Ray SDK for Application Signals.

## AWS Resources

### CloudFormation Stacks

| Stack | Template | Resources |
|-------|----------|-----------|
| otel-demo-shared | `cfn/shared.yaml` | Security groups, IAM roles, DynamoDB, S3, SQS, SNS, Kinesis, ElastiCache, Aurora, MSK |
| otel-demo-ecs | `cfn/ecs.yaml` | ECS Fargate cluster, ALB, 2 task definitions with collector sidecars |
| otel-demo-lambda | `cfn/lambda.yaml` | 4 Lambda functions, REST API Gateway, event source mappings |

### Managed Services

| Service | Resource Name | Used By | Purpose |
|---------|--------------|---------|---------|
| DynamoDB | otel-demo-orders | ECS order-processor, all Lambdas | Order/payment records |
| S3 | otel-demo-assets-{account} | ECS order-processor, inventory-service | Product catalog |
| SNS | otel-demo-order-topic | ECS -> Lambda sns-consumer | Order fan-out |
| SQS | otel-demo-order-queue | ECS -> Lambda sqs-consumer | Order queue |
| Kinesis | otel-demo-order-stream | ECS -> Lambda kinesis-consumer | Order stream |
| ElastiCache | otel-demo-valkey | ECS inventory-service | Cache (TLS required) |
| Aurora | otel-demo-postgres | EKS product-catalog/reviews | Database (in-cluster pg used) |
| MSK | otel-demo-kafka | ECS order-processor (optional) | Kafka (in-cluster used by EKS) |

### IAM Roles

| Role | Used By | Permissions |
|------|---------|-------------|
| github-actions-otel-demo | GitHub Actions OIDC | Full deployment (EKS, ECS, Lambda, CFN, ECR, S3, SNS, SQS, etc.) |
| otel-demo-ecs-task-role | ECS containers | DynamoDB, S3, X-Ray, SNS, SQS, Kinesis, MSK |
| otel-demo-ecs-execution-role | ECS Fargate agent | ECR pull, CloudWatch Logs |
| otel-demo-lambda-role | All Lambda functions | DynamoDB, SQS, Kinesis, X-Ray, CloudWatch Logs |
| otel-collector-xray-policy | EKS collector (IRSA) | X-Ray PutTraceSegments, GetSamplingRules |

## Trace Flow

```
multi-platform-caller (EKS, every 30s)
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

### Telemetry Paths

| Platform | SDK | Destination |
|----------|-----|-------------|
| EKS | Vanilla OTel SDK (per language) | In-cluster collector -> Jaeger + Prometheus + X-Ray |
| ECS | Vanilla OTel Python SDK | Localhost sidecar collector -> X-Ray (sigv4auth) |
| Lambda | ADOT Python layer + X-Ray SDK | X-Ray (native Lambda integration) |

## OTel Collector Configuration

### EKS Collector (helm-values-xray.yaml / helm-values-multi.yaml)

The in-cluster OTel Collector is configured with these additions over vanilla:

1. **sigv4auth extension** — Signs OTLP HTTP requests with AWS SigV4 using IRSA credentials
2. **otlphttp/xray exporter** — Standard `otlphttp` exporter pointed at `https://xray.<region>.amazonaws.com` (NOT the `awsxray` plugin)
3. **Resource detection** — `eks` and `ec2` detectors auto-tag telemetry with `cloud.provider`, `cloud.region`, `k8s.cluster.name`, etc.
4. **Span metrics dimensions** — 12 attributes added for dependency graphs: `peer.service`, `db.system`, `messaging.system`, `rpc.service`, `rpc.method`, `http.route`, etc.

Pipeline: `App -> OTLP -> Collector -> [otlp/jaeger, spanmetrics, otlphttp/xray, debug]`

### ECS Collector Sidecar (inline config in ecs.yaml)

Each ECS task runs `otel/opentelemetry-collector-contrib` as a sidecar with:
- `sigv4auth` extension (uses ECS task role, not IRSA)
- `otlphttp/xray` exporter to X-Ray
- App sends OTLP HTTP to `localhost:4318`

## Prerequisites

- AWS CLI v2, eksctl, kubectl, Helm v3, Docker, Python 3.12+
- GitHub repo with `AWS_ROLE_ARN` secret

## Deployment

### Step 1: GitHub Actions IAM (one-time)
```bash
./scripts/setup-iam-oidc.sh <github-org/repo>
```
Add output role ARN as GitHub secret `AWS_ROLE_ARN`.

### Step 2: Deploy (pick one)

**GitHub Actions (recommended):** Push to `main` — auto-deploys both apps.

**Manual:**
```bash
./scripts/setup-eks.sh                                          # Original EKS
./scripts/deploy-multi-platform.sh --region us-east-1           # Multi EKS + shared CFN
./scripts/deploy-multi-services.sh --region us-east-1           # ECS + Lambda + caller
```

## Accessing UIs

```bash
# Original app (cluster: otel-demo)
aws eks update-kubeconfig --name otel-demo --region us-east-1
kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080

# Multi-platform app (cluster: otel-demo-multi)
aws eks update-kubeconfig --name otel-demo-multi --region us-east-1
kubectl port-forward -n otel-demo svc/frontend-proxy 8081:8080
```

| UI | URL |
|----|-----|
| Astronomy Shop | http://localhost:8080 (or 8081) |
| Grafana | http://localhost:8080/grafana |
| Jaeger | http://localhost:8080/jaeger/ui |
| X-Ray | https://us-east-1.console.aws.amazon.com/xray/home#/service-map |

## Configuration Decisions

1. **Separate EKS cluster** — Avoids Helm release conflicts between original and multi- prefixed service names
2. **useDefault.env: false** — Only way to override `OTEL_SERVICE_NAME` (Helm chart uses `fieldRef` which can't be overridden via `envOverrides`)
3. **ECS collector sidecars** — Simpler than shared NLB; each sidecar uses ECS task role for sigv4auth
4. **Vanilla OTel SDK on ECS** — User requirement; collector sidecar handles X-Ray export
5. **ADOT Python layer on Lambda** — Lambda can't reach external collector; layer provides auto-instrumentation + Application Signals
6. **REST API Gateway (v1)** — Supports X-Ray tracing natively; HTTP API (v2) does not
7. **OTEL_PROPAGATORS=xray,tracecontext,baggage** — Required for trace propagation through API Gateway (X-Ray header format)
8. **EKS access entry auto-creation** — Scripts create access entries for deploying IAM role (no manual step)
9. **Single Lambda zip** — All 4 handlers in one zip; each function references different handler
10. **ECS traces only in X-Ray** — Sidecars don't connect to EKS Jaeger/Prometheus (would need NLB)
11. **MSK not used by EKS** — MSK Serverless requires IAM auth + TLS; EKS Kafka clients don't support it
12. **ElastiCache requires TLS** — ECS inventory-service uses `ssl=True`; EKS cart uses in-cluster valkey

## Cleanup

```bash
# Multi-platform only
./scripts/cleanup-multi-platform.sh --region us-east-1 --keep-eks

# Everything
./scripts/cleanup-multi-platform.sh --region us-east-1
./scripts/cleanup-eks.sh

# Via GitHub Actions: Run workflow -> destroy
```

## Troubleshooting

- **ECS tasks not starting:** Check CloudWatch Logs `/ecs/otel-demo-multi/*`, verify ECR images, check security groups
- **Traces not in X-Ray:** EKS: verify IRSA on collector SA. ECS: check sidecar logs. Lambda: verify TracingConfig + ADOT layer
- **API Gateway missing from X-Ray:** Must be REST API (v1) with TracingEnabled. Caller needs xray propagator
- **EKS 403 on kubectl:** Scripts auto-create access entries. Manual: `aws eks create-access-entry` + `associate-access-policy`
- **CFN ROLLBACK_COMPLETE:** Scripts auto-delete and recreate
- **Lambda errors:** Ensure requirements.txt has `aws-xray-sdk>=2.12.0`
