# Multi-Platform OpenTelemetry Demo

Extends the OpenTelemetry Astronomy Shop demo to run across multiple AWS
compute platforms (EKS, ECS, Lambda, EC2) with cross-platform tracing
via AWS X-Ray.

## Architecture

```
EKS Cluster (otel-demo-multi)
├── Full OTel Demo App (frontend, load-generator, all services)
├── OTel Collector → Jaeger + Prometheus + X-Ray
├── Grafana, Prometheus, OpenSearch
└── multi-platform-caller pod → calls ECS, Lambda, EC2

ECS Fargate (order-processor)
├── Flask app + X-Ray daemon sidecar
├── Writes to DynamoDB, reads S3
├── Calls Lambda (via API Gateway) and EC2 (via ALB)
└── Traces → X-Ray via daemon

Lambda (payment-processor)
├── Python function behind API Gateway HTTP API
├── Writes to DynamoDB
└── Traces → X-Ray natively (built-in)

EC2 ASG (inventory-service)
├── Flask app + X-Ray daemon (Docker containers)
├── Reads/writes ElastiCache Redis, reads S3
└── Traces → X-Ray via daemon

AWS Managed Services
├── DynamoDB (otel-demo-orders)
├── S3 (otel-demo-assets-{account})
├── SQS (otel-demo-notifications)
├── ElastiCache Serverless (Valkey/Redis)
├── Aurora Serverless v2 (PostgreSQL)
└── MSK Serverless (Kafka)
```

## Prerequisites

- AWS CLI configured with admin credentials
- [eksctl](https://eksctl.io/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- Docker (for building service images)
- Python 3.12+ (for Lambda packaging)
- GitHub repo with `AWS_ROLE_ARN` secret configured

## Quick Start (GitHub Actions)

```bash
# 1. Set up IAM (one-time per account)
./scripts/setup-iam-oidc.sh <github-org/repo>

# 2. Add AWS_ROLE_ARN secret to GitHub repo

# 3. Push to main — auto-deploys both apps
git push

# Or trigger manually:
# Actions → "Multi-Platform Deploy" → Run workflow → deploy
```

The workflow deploys:
1. Original EKS-only app on `otel-demo` cluster
2. Multi-platform app on `otel-demo-multi` cluster + ECS/Lambda/EC2

## Manual Deployment

```bash
# Step 1: IAM setup
./scripts/setup-iam-oidc.sh <github-org/repo>

# Step 2: Deploy original EKS app
./scripts/setup-eks.sh

# Step 3: Deploy multi-platform (creates second EKS cluster + CFN stacks)
./scripts/deploy-multi-platform.sh --region us-east-1 --cluster otel-demo

# Step 4: Deploy ECS/Lambda/EC2 services
./scripts/deploy-multi-services.sh --region us-east-1
```

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
| X-Ray | https://us-east-1.console.aws.amazon.com/xray/home#/service-map |

## Telemetry Configuration

### EKS Services (OTel Collector)

Services send OTLP to the in-cluster OTel Collector which exports to:
- Jaeger (in-cluster, for open-source trace viewing)
- Prometheus (in-cluster, for metrics + Grafana dashboards)
- X-Ray (via `otlphttp/xray` exporter with `sigv4auth`)

Key Helm values (`helm-values-multi.yaml`):
```yaml
opentelemetry-collector:
  config:
    extensions:
      sigv4auth:
        region: us-east-1
        service: xray
    exporters:
      otlphttp/xray:
        endpoint: https://xray.us-east-1.amazonaws.com
        auth:
          authenticator: sigv4auth
    service:
      pipelines:
        traces:
          exporters: [otlp/jaeger, debug, spanmetrics, otlphttp/xray]
```

IRSA provides AWS credentials to the collector pod:
```bash
eksctl create iamserviceaccount --name otel-collector --namespace otel-demo \
  --cluster otel-demo-multi --attach-policy-arn <xray-policy-arn> \
  --role-name otel-collector-xray-role-multi --approve
```

### ECS Services (X-Ray SDK + Daemon Sidecar)

The ECS task runs two containers:
1. Application container with `aws-xray-sdk` Python library
2. X-Ray daemon sidecar (`public.ecr.aws/xray/aws-xray-daemon`)

The X-Ray SDK auto-patches boto3 and requests:
```python
from aws_xray_sdk.core import xray_recorder, patch_all
from aws_xray_sdk.ext.flask.middleware import XRayMiddleware

xray_recorder.configure(service='multi-order-processor')
patch_all()  # Patches boto3, requests, etc.
XRayMiddleware(app, xray_recorder)
```

IAM: ECS task role needs `xray:PutTraceSegments` with `Resource: *`.

### Lambda Functions (X-Ray SDK + Native Tracing)

Lambda has built-in X-Ray support. The function uses:
```python
from aws_xray_sdk.core import xray_recorder, patch_all
patch_all()  # Patches boto3 calls
```

CloudFormation: `TracingConfig: Mode: Active` on the function.
IAM: Lambda role needs `xray:PutTraceSegments`.

### EC2 Services (X-Ray SDK + Daemon Container)

EC2 instances run two Docker containers:
1. Application container with `aws-xray-sdk`
2. X-Ray daemon container (`public.ecr.aws/xray/aws-xray-daemon`)

Both run via Docker on the instance. The daemon listens on UDP port 2000.
IAM: EC2 instance role needs `xray:PutTraceSegments` + ECR pull.

## Service Names

All multi-platform services use `service.namespace=otel-demo-multi`:

| Platform | Service | service.name |
|----------|---------|-------------|
| EKS | All demo services | Original names (frontend, checkout, etc.) |
| ECS | Order Processor | multi-order-processor |
| Lambda | Payment Processor | multi-payment-processor |
| EC2 | Inventory Service | multi-inventory-service |

## AWS Managed Services

| Service | Resource | Used By |
|---------|----------|---------|
| DynamoDB | otel-demo-orders | ECS (order records), Lambda (payments) |
| S3 | otel-demo-assets-{account} | ECS (catalog), EC2 (catalog) |
| SQS | otel-demo-notifications | Checkout → Email |
| ElastiCache | otel-demo-valkey | EC2 inventory (cache) |
| Aurora | otel-demo-postgres | Product catalog, reviews |
| MSK | otel-demo-kafka | Accounting, fraud-detection |

## CloudFormation Stacks

| Stack | Resources |
|-------|-----------|
| otel-demo-shared | SGs, IAM roles, DynamoDB, S3, SQS, ElastiCache, Aurora, MSK |
| otel-demo-ecs | ECS Fargate cluster, ALB, task definition with X-Ray sidecar |
| otel-demo-lambda | Lambda function, API Gateway HTTP API |
| otel-demo-ec2 | EC2 ASG, ALB, launch template with X-Ray daemon |

## Cleanup

```bash
# Destroy multi-platform only (keeps original EKS app)
./scripts/cleanup-multi-platform.sh --region us-east-1 --keep-eks

# Destroy everything
./scripts/cleanup-multi-platform.sh --region us-east-1
./scripts/cleanup-eks.sh
```

## Troubleshooting

See the troubleshooting section in `scripts/README.md`.

## Limitations and Design Decisions

### Shared OTel Collector for X-Ray Export

All services (EKS, ECS, EC2) send OTLP to a single OTel Collector
running on the EKS cluster, exposed via an internal NLB. The collector
handles sigv4 authentication for X-Ray export using IRSA credentials.

**Why:** X-Ray's OTLP endpoint requires AWS Signature V4 on every
request. The vanilla OTel SDK doesn't support sigv4 natively. Rather
than adding AWS-specific auth to each service, the collector centralizes
it. The `sigv4auth` extension is open-source (OTel Collector Contrib).

**Alternative:** Run a collector sidecar on each ECS task and EC2
instance with its own IAM role. This adds complexity but removes the
NLB dependency.

### Lambda Uses X-Ray SDK (Not OTel SDK)

Lambda functions use the AWS X-Ray SDK instead of vanilla OTel SDK
because Lambda has built-in X-Ray support and cannot reach the
external OTel Collector. The X-Ray SDK auto-patches boto3 calls and
uses Lambda's built-in X-Ray daemon.

### Helm Chart OTEL_SERVICE_NAME Override

The OTel Demo Helm chart sets `OTEL_SERVICE_NAME` via Kubernetes
`fieldRef` (pod label). This cannot be overridden via `envOverrides`
without creating duplicate env keys. The workaround is `useDefault.env: false`
with complete env blocks for every service — verbose but the only way
to set custom service names.

### MSK Serverless Not Used

MSK Serverless requires IAM auth + TLS which the demo's Kafka clients
(Go Sarama, Java) don't support without code changes. Kafka runs as
an in-cluster pod instead. MSK Serverless infrastructure exists in the
shared CFN stack but is unused.

### ElastiCache Serverless Requires TLS

ElastiCache Serverless (Valkey) requires TLS connections. The Python
Redis client supports this with `ssl=True`. The EKS cart service uses
the in-cluster valkey-cart pod (no TLS) while the ECS inventory service
connects to ElastiCache Serverless with TLS.
