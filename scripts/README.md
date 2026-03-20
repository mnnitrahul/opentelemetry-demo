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
- `scripts/cfn/ec2-asg-pricing.yaml` — EC2 ASG pricing service: DynamoDB table, ALB, launch template, ASG with target-tracking scaling
- `.github/workflows/eks-deploy.yml` — GitHub Actions: deploy/destroy original EKS app
- `.github/workflows/multi-platform-deploy.yml` — GitHub Actions: deploy/destroy both apps

### OTel Collector Configuration (new files)
- `scripts/helm-values-xray.yaml` — Helm overrides for original EKS app (sigv4auth, X-Ray exporter, resource detection, span metrics dimensions)
- `scripts/helm-values-multi.yaml` — Helm overrides for multi-platform app (all services with `multi-` prefixed names, `useDefault.env: false`)

### Application Code (new files)
- `src/multi-platform/ecs/app.py` — Order processor (Flask + vanilla OTel auto-instrumentation)
- `src/multi-platform/ecs-java/` — Order processor Java (Spring Boot + OTel Java agent)
- `src/multi-platform/ecs-vertx/` — Order processor Vert.x (Vert.x 4.5 + OTel Java agent, tests reactive SQL client instrumentation)
- `src/multi-platform/ec2/app.py` — Inventory service (Flask + vanilla OTel auto-instrumentation)
- `src/multi-platform/ec2-asg/app.py` — Pricing service (Flask + vanilla OTel auto-instrumentation, DynamoDB + S3)
- `src/multi-platform/caller/app.py` — Cross-platform caller (OTel auto-instrumentation, separate trace per call)
- `src/multi-platform/lambda/payment_processor.py` — Payment handler (X-Ray SDK)
- `src/multi-platform/lambda/sqs_consumer.py` — SQS consumer (X-Ray SDK)
- `src/multi-platform/lambda/sns_consumer.py` — SNS consumer (X-Ray SDK)
- `src/multi-platform/lambda/kinesis_consumer.py` — Kinesis consumer (X-Ray SDK)
- `src/multi-platform/lambda/msk_consumer.py` — MSK consumer (X-Ray SDK)
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

EC2 ASG (behind ALB)
  multi-pricing-service  (DynamoDB + S3, OTel auto-instrumentation)

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

| Service | OTEL_SERVICE_NAME | Framework | Image Source | ALB Path |
|---------|-------------------|-----------|-------------|----------|
| Order Processor | multi-order-processor | Python/Flask | `src/multi-platform/ecs/` | `/order*`, `/order-slow` |
| Order Processor Java | multi-order-processor-java | Java/Spring Boot | `src/multi-platform/ecs-java/` | `/order-java*`, `/order-java-slow` |
| Order Processor Vert.x | multi-order-processor-vertx | Java/Vert.x | `src/multi-platform/ecs-vertx/` | `/order-vertx*`, `/order-vertx-slow` |
| Inventory Service | multi-inventory-service | Python/Flask | `src/multi-platform/ec2/` | `/inventory*` |

All behind a single ALB with path-based routing. Each task has an OTel Collector Contrib sidecar with sigv4auth + ECS resource detection -> X-Ray.

Auto-instrumentation:
- Python services: `opentelemetry-instrument` CLI via Dockerfile
- Java services: `-javaagent:opentelemetry-javaagent.jar` (vanilla OTel, not ADOT)

Slow query endpoints (`/order-slow`, `/order-java-slow`, `/order-vertx-slow`) run `SELECT pg_sleep(2)` on Aurora to simulate slow DB queries. The caller triggers these every ~5 minutes.

### Lambda Functions

| Function | OTEL_SERVICE_NAME | Trigger |
|----------|-------------------|---------|
| Payment Processor | multi-payment-processor | REST API Gateway POST /payment |
| SQS Consumer | multi-sqs-consumer | SQS queue (otel-demo-order-queue) |
| SNS Consumer | multi-sns-consumer | SNS topic (otel-demo-order-topic) |
| Kinesis Consumer | multi-kinesis-consumer | Kinesis stream (otel-demo-order-stream) |
| MSK Consumer | multi-msk-consumer | MSK Serverless topic (otel-demo-orders) |

All use ADOT Python layer + X-Ray SDK for Application Signals.

## AWS Resources

### CloudFormation Stacks

| Stack | Template | Resources |
|-------|----------|-----------|
| otel-demo-shared | `cfn/shared.yaml` | Security groups, IAM roles, DynamoDB, S3, SQS, SNS, Kinesis, ElastiCache, Aurora, MSK |
| otel-demo-ecs | `cfn/ecs.yaml` | ECS Fargate cluster, ALB, 2 task definitions with collector sidecars |
| otel-demo-lambda | `cfn/lambda.yaml` | 4 Lambda functions, REST API Gateway, event source mappings |
| otel-demo-ec2-pricing | `cfn/ec2-asg-pricing.yaml` | EC2 ASG, ALB, DynamoDB pricing table, target-tracking scaling |

### Managed Services

| Service | Resource Name | Used By | Purpose |
|---------|--------------|---------|---------|
| DynamoDB | otel-demo-orders | ECS order-processor, all Lambdas | Order/payment records |
| DynamoDB | otel-demo-pricing | EC2 ASG pricing-service | Product pricing data |
| S3 | otel-demo-assets-{account} | ECS order-processor, inventory-service | Product catalog |
| SNS | otel-demo-order-topic | ECS -> Lambda sns-consumer | Order fan-out |
| SQS | otel-demo-order-queue | ECS -> Lambda sqs-consumer | Order queue |
| Kinesis | otel-demo-order-stream | ECS -> Lambda kinesis-consumer | Order stream |
| ElastiCache | otel-demo-valkey | ECS inventory-service | Cache (TLS required) |
| Aurora | otel-demo-postgres | ECS order-processor, EKS product-catalog/reviews | Order records (PostgreSQL) |
| MSK | otel-demo-kafka | ECS order-processor | Order event streaming (Kafka IAM auth) |

### IAM Roles

| Role | Used By | Permissions |
|------|---------|-------------|
| github-actions-otel-demo | GitHub Actions OIDC | Full deployment (EKS, ECS, Lambda, CFN, ECR, S3, SNS, SQS, etc.) |
| otel-demo-ecs-task-role | ECS containers | DynamoDB, S3, X-Ray, CloudWatch, SNS, SQS, Kinesis, MSK, Aurora (password auth) |
| otel-demo-ecs-execution-role | ECS Fargate agent | ECR pull, CloudWatch Logs |
| otel-demo-lambda-role | All Lambda functions | DynamoDB, SQS, Kinesis, X-Ray, CloudWatch, CloudWatch Logs |
| otel-demo-ec2-instance-role | EC2 ASG instances | S3, X-Ray, CloudWatch, DynamoDB read/write |
| otel-collector-xray-policy | EKS collector (IRSA) | X-Ray PutTraceSegments, GetSamplingRules, CloudWatch * |

## Trace Flow

Each service call creates its own independent trace (not one giant trace).

```
multi-platform-caller (EKS, every 30s, separate trace per call)
  |-> ECS ALB /order -> multi-order-processor (Python)
  |     |-> DynamoDB, S3, API Gateway, inventory, SNS, SQS, Kinesis, Aurora, MSK
  |-> ECS ALB /order-java -> multi-order-processor-java (Spring Boot)
  |     |-> DynamoDB, S3, API Gateway, inventory, SNS, SQS, Kinesis, Aurora, MSK
  |-> ECS ALB /order-vertx -> multi-order-processor-vertx (Vert.x)
  |     |-> DynamoDB, S3, Aurora (native + RxJava2 wrapped PG client)
  |-> API Gateway /payment -> multi-payment-processor (Lambda) -> DynamoDB
  |-> ECS ALB /inventory -> multi-inventory-service -> ElastiCache, S3
  |-> EC2 ASG ALB /price -> multi-pricing-service -> DynamoDB, S3

Every 10th iteration (~5 min): calls /order-slow, /order-java-slow, /order-vertx-slow
  -> SELECT pg_sleep(2) on Aurora (2-second DB span for slow query testing)
```

### Telemetry Paths

| Platform | SDK | Destination |
|----------|-----|-------------|
| EKS | Vanilla OTel SDK (per language) | In-cluster collector -> Jaeger + Prometheus + X-Ray + CloudWatch Metrics (granite) |
| ECS Python | `opentelemetry-instrument` CLI | Localhost sidecar collector -> X-Ray + CloudWatch Metrics (granite) |
| ECS Java (Spring Boot) | OTel Java agent (`-javaagent`) | Localhost sidecar collector -> X-Ray + CloudWatch Metrics (granite) |
| ECS Java (Vert.x) | OTel Java agent (`-javaagent`) | Localhost sidecar collector -> X-Ray + CloudWatch Metrics (granite) |
| EC2 ASG Python | `opentelemetry-instrument` CLI | Localhost sidecar collector (otel-collector-contrib on same EC2 instance) -> X-Ray + CloudWatch Metrics (granite) |
| Lambda | ADOT Python layer + X-Ray SDK | X-Ray (native Lambda integration) |

### Known Instrumentation Gaps

| Gap | Language | Detail |
|-----|----------|--------|
| S3 bucket name missing | Python | botocore instrumentor doesn't capture `aws.s3.bucket`. Java does. |
| SQS queue URL missing | Python | botocore instrumentor doesn't capture `aws.sqs.queue.url`. Java does. |
| SNS topic ARN missing | Python | botocore instrumentor doesn't capture `sns.topic.arn`. Java does. |
| Kinesis stream name missing | Python | botocore instrumentor doesn't capture `kinesis.stream_name`. Java does. |
| Vert.x PG shows as UnknownRemoteService | Java/Vert.x | Vert.x SQL client instrumentation doesn't set `db.system`, `server.address`, `db.name`. JDBC does. |
| Flask high-cardinality operations | Python | Unmatched routes use raw path as span name (100+ bot operations). Spring Boot normalizes to `/**`. |
| EC2 ASG name not auto-detected | Python/All | The OTel `ec2` resource detector does not discover the Auto Scaling Group name. Only `host.id`, `host.type`, `cloud.region`, `cloud.account.id`, `cloud.platform`, `cloud.availability_zone`, `host.image.id`, and `host.name` are auto-detected. ASG name requires manual `OTEL_RESOURCE_ATTRIBUTES` or a custom resource detector. |

### EC2 ASG Instrumentation Notes

The EC2 ASG pricing service uses vanilla OTel auto-instrumentation with zero custom code or resource attributes. Here is what the OTel `ec2` resource detector and Python auto-instrumentors provide out of the box:

**Resource attributes (from `ec2` detector):**
- `cloud.provider`, `cloud.platform` (aws_ec2), `cloud.region`, `cloud.availability_zone`, `cloud.account.id`
- `host.id` (instance ID), `host.type` (e.g. t3.small), `host.name` (private DNS), `host.image.id` (AMI)

**Not available from vanilla OTel on EC2:**
- Auto Scaling Group name — no built-in detector
- Instance tags — EC2 resource detector doesn't read tags
- Launch template name/version

**Flask auto-instrumentor (`opentelemetry.instrumentation.flask`) provides:**
- `http.method`, `http.route`, `http.status_code`, `http.target`, `http.scheme`
- `net.host.name`, `net.host.port`, `net.peer.ip`, `net.peer.port`
- `http.user_agent`, `http.flavor`
- Span name format: `{METHOD} {route}` (e.g. `GET /price`)

**Botocore auto-instrumentor (`opentelemetry.instrumentation.botocore`) provides:**
- `rpc.system` (aws-api), `rpc.service` (DynamoDB/S3), `rpc.method` (PutItem/GetObject)
- `db.system` (dynamodb), `db.operation` (PutItem/GetItem/Scan)
- `aws.dynamodb.table_names` (array of table names)
- `server.address`, `server.port`, `http.status_code`
- `aws.request_id`, `retry_attempts`
- Note: S3 bucket name is NOT captured by the Python botocore instrumentor (Java does capture it)

**EC2 ASG collector architecture:**
The pricing service runs two Docker containers on each EC2 instance:
1. `pricing` — Flask app with `opentelemetry-instrument` CLI (sends OTLP HTTP to localhost:4318)
2. `otel-collector` — `otel/opentelemetry-collector-contrib` with sigv4auth, ec2 resource detection, exports to X-Ray and CloudWatch Metrics

This mirrors the ECS sidecar pattern but uses Docker host networking (`172.17.0.1:4318`) instead of localhost since the containers are on the Docker bridge network.

## OTel Collector Configuration

### EKS Collector (helm-values-xray.yaml / helm-values-multi.yaml)

The in-cluster OTel Collector is configured with these additions over vanilla:

1. **sigv4auth extension** — Signs OTLP HTTP requests with AWS SigV4 using IRSA credentials
2. **sigv4auth/metrics extension** — Separate SigV4 signer for CloudWatch metrics endpoint (service: `monitoring`)
3. **otlphttp/xray exporter** — Standard `otlphttp` exporter pointed at `https://xray.<region>.amazonaws.com` (NOT the `awsxray` plugin)
4. **otlphttp/cloudwatch-metrics exporter** — Standard `otlphttp` exporter pointed at `https://granite.amazonaws.com` (pre-prod CloudWatch Metrics OTLP endpoint)
5. **Resource detection** — `eks` and `ec2` detectors auto-tag telemetry with `cloud.provider`, `cloud.region`, etc. **Note:** The OTel `eks` detector cannot auto-detect the EKS cluster name. If you need `k8s.cluster.name` as a resource attribute, you must set it manually via `OTEL_RESOURCE_ATTRIBUTES=k8s.cluster.name=<your-cluster>` on the collector or application pods.
6. **Span metrics dimensions** — 12 attributes added for dependency graphs: `peer.service`, `db.system`, `messaging.system`, `rpc.service`, `rpc.method`, `http.route`, etc.

Pipeline:
- Traces: `App -> OTLP -> Collector -> [otlp/jaeger, spanmetrics, otlphttp/xray, debug]`
- Metrics: `App -> OTLP -> Collector -> [otlphttp/prometheus, otlphttp/cloudwatch-metrics, debug]`

### ECS Collector Sidecar (inline config in ecs.yaml)

Each ECS task runs `otel/opentelemetry-collector-contrib` as a sidecar with:
- `resourcedetection` processor with `ecs` and `ec2` detectors (adds `cloud.platform: aws_ecs`, cluster ARN, task ARN, launch type). **Note:** For ECS, the cluster name is derived automatically from the ECS task metadata (cluster ARN).
- `sigv4auth` extension (uses ECS task role, not IRSA) for X-Ray traces
- `sigv4auth/metrics` extension (service: `monitoring`) for CloudWatch metrics
- `otlphttp/xray` exporter to X-Ray
- `otlphttp/cloudwatch-metrics` exporter to `https://granite.amazonaws.com` (pre-prod CloudWatch Metrics OTLP endpoint)
- App sends OTLP HTTP to `localhost:4318`
- Java sidecars also accept metrics and logs pipelines (Java agent exports all 3 signals)

### CloudWatch Metrics OTLP Endpoint

The demo sends metrics to the CloudWatch Metrics OTLP endpoint (currently using the pre-prod granite endpoint).

**Configuration:**
- Endpoint: `https://granite.amazonaws.com` (pre-prod). Production will be `https://monitoring.<region>.amazonaws.com`
- Auth: SigV4 with `service: monitoring` (separate from X-Ray which uses `service: xray`)
- Protocol: HTTP only (no gRPC), same as X-Ray/Logs OTLP endpoints
- Compression: gzip

**IAM permissions required:** `cloudwatch:*` (currently broad for testing; production should use `cloudwatch:PutMetricData`)

**Resource attribute notes:**
- EKS: The OTel `eks` resource detector does NOT auto-detect the cluster name. To have `k8s.cluster.name` appear as a dimension in CloudWatch, set it explicitly: `OTEL_RESOURCE_ATTRIBUTES=k8s.cluster.name=otel-demo`
- ECS: The `ecs` resource detector derives the cluster name from the ECS task metadata endpoint (cluster ARN). No manual configuration needed.

**Known data quality issues with the demo:**
- Some spanmetrics dimensions (`peer.service`, `http.route`, `db.system`, etc.) emit empty string values when the source span lacks those attributes. The granite endpoint rejects datapoints with blank attribute values (partial success — other datapoints in the same metric are accepted).
- Some host/infrastructure metrics have non-string attribute types that the endpoint rejects (HTTP 400 — entire ResourceMetrics batch dropped).

## Prerequisites

Install these tools before starting:

```bash
# AWS CLI v2
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"  # macOS
sudo installer -pkg AWSCLIV2.pkg -target /

# eksctl
brew install eksctl          # macOS
# or: curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz"

# kubectl
brew install kubectl         # macOS

# Helm v3
brew install helm            # macOS

# Docker Desktop (for building ECS/caller images)
# https://www.docker.com/products/docker-desktop/

# Python 3.12+ with pip (for Lambda packaging)
brew install python@3.12     # macOS
```

Verify:
```bash
aws --version        # >= 2.x
eksctl version       # >= 0.170
kubectl version --client
helm version         # >= 3.x
docker --version
python3 --version    # >= 3.12
```

## Setup (one-time per AWS account)

### Step 1: Configure AWS CLI

```bash
# Option A: SSO login (recommended)
aws configure sso
aws sso login --profile <your-profile>
export AWS_PROFILE=<your-profile>

# Option B: Access keys
aws configure
# Enter Access Key ID, Secret Access Key, region: us-east-1

# Verify
aws sts get-caller-identity
```

### Step 2: Create GitHub OIDC + IAM Role

This creates an OIDC identity provider in your AWS account so GitHub Actions
can assume an IAM role without storing AWS credentials as secrets.

```bash
# Replace with your GitHub org/repo
./scripts/setup-iam-oidc.sh <github-org/repo>

# Example:
./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo
```

The script:
1. Creates OIDC provider `token.actions.githubusercontent.com` (idempotent)
2. Creates IAM policy `github-actions-otel-demo-policy` with permissions for EKS, ECS, Lambda, CloudFormation, ECR, S3, SNS, SQS, Kinesis, DynamoDB, ElastiCache, RDS, MSK, IAM, EC2, API Gateway, X-Ray, CloudWatch
3. Creates IAM role `github-actions-otel-demo` with OIDC trust for your repo
4. Prints the role ARN

### Step 3: Add GitHub Secret

1. Go to your repo: `https://github.com/<org>/<repo>/settings/secrets/actions/new`
2. Click "New repository secret"
3. Name: `AWS_ROLE_ARN`
4. Value: paste the role ARN from Step 2 output (e.g., `arn:aws:iam::123456789012:role/github-actions-otel-demo`)
5. Click "Add secret"

### Step 4: Enable GitHub Actions

1. Go to `https://github.com/<org>/<repo>/settings/actions`
2. Ensure "Allow all actions and reusable workflows" is selected
3. Under "Workflow permissions", select "Read and write permissions"

## Deploy

### Option A: GitHub Actions (recommended)

Push to `main` — auto-deploys everything:
```bash
git add -A
git commit -m "deploy"
git push origin main
```

Or trigger manually:
1. Go to `https://github.com/<org>/<repo>/actions`
2. Click "Multi-Platform Deploy" workflow
3. Click "Run workflow"
4. Select `deploy` action, confirm region `us-east-1`
5. Click "Run workflow"

The workflow deploys in order:
1. Original EKS app on `otel-demo` cluster (~15 min first time)
2. Multi-platform EKS app on `otel-demo-multi` cluster (~15 min first time)
3. Shared CloudFormation stack (DynamoDB, S3, SNS, SQS, Kinesis, ElastiCache, Aurora, MSK)
4. Builds Docker images, pushes to ECR
5. Packages Lambda functions, uploads to S3
6. Deploys ECS + Lambda CloudFormation stacks
7. Deploys caller pod on EKS

### Option B: Manual (from local machine)

```bash
# 1. Deploy original EKS app (creates otel-demo cluster)
./scripts/setup-eks.sh

# 2. Deploy multi-platform EKS cluster + shared infrastructure
./scripts/deploy-multi-platform.sh --region us-east-1 --cluster otel-demo

# 3. Build images, package Lambda, deploy ECS + Lambda stacks
./scripts/deploy-multi-services.sh --region us-east-1
```

### Post-Deploy: Grant Local kubectl Access

If the cluster was created by GitHub Actions, your local IAM identity
needs an access entry to use kubectl:

```bash
# Get your IAM role ARN
aws sts get-caller-identity --query Arn --output text
# If it shows assumed-role, extract the role name and construct:
# arn:aws:iam::<ACCOUNT_ID>:role/<ROLE_NAME>

# Grant access to both clusters
for CLUSTER in otel-demo otel-demo-multi; do
  aws eks create-access-entry \
    --cluster-name $CLUSTER --region us-east-1 \
    --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE>

  aws eks associate-access-policy \
    --cluster-name $CLUSTER --region us-east-1 \
    --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE> \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
    --access-scope type=cluster
done

# Update kubeconfig
aws eks update-kubeconfig --name otel-demo --region us-east-1
aws eks update-kubeconfig --name otel-demo-multi --region us-east-1

# Verify
kubectl get nodes
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
11. **MSK used by ECS only** — MSK Serverless requires IAM auth + TLS; ECS order-processor uses `aws-msk-iam-sasl-signer-python` for OAUTHBEARER auth; EKS Kafka clients (Go Sarama) don't support IAM auth
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
