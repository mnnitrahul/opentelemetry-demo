# AWS Customizations Reference

Complete list of every change and configuration applied to run the
vanilla OpenTelemetry Demo on AWS EKS with X-Ray trace export.

No AWS-proprietary SDKs, agents, or exporters are used. Everything
is standard OTel SDK + OTel Collector Contrib.

---

# Part A: AWS Infrastructure & Permissions

These are AWS-side setup steps. They have nothing to do with OpenTelemetry
configuration — they create the compute environment and grant access.

---

## A1. GitHub OIDC → AWS IAM Trust

**Why:** GitHub Actions needs to create AWS resources (EKS cluster, IAM roles)
without storing long-lived AWS access keys as secrets. OIDC federation lets
GitHub prove its identity to AWS using short-lived tokens.

**How:** `scripts/setup-iam-oidc.sh` creates:

| Resource | Value |
|----------|-------|
| OIDC Provider | `token.actions.githubusercontent.com` |
| IAM Role | `github-actions-otel-demo` |
| Trust | `repo:mnnitrahul/opentelemetry-demo:*` |
| GitHub Secret | `AWS_ROLE_ARN` → role ARN |

IAM Policy (`github-actions-otel-demo-policy`) covers:
- EKS, ECS, Lambda, API Gateway, ALB, Auto Scaling, EC2
- CloudFormation, IAM (role/policy/instance profile/OIDC management)
- X-Ray, CloudWatch Logs, ECR, S3, KMS, SSM, STS

**Impact:** Without this, GitHub Actions cannot authenticate to AWS at all.
The broad policy scope is intentional — it supports future migration of
services to ECS, Lambda, API Gateway without needing policy updates.

---

## A2. EKS Cluster

**Why:** The demo is a microservice application that needs a Kubernetes
cluster to run. EKS provides managed Kubernetes on AWS.

**How:** Created by `setup-eks.sh` or the GitHub Actions workflow.

| Parameter | Value |
|-----------|-------|
| Cluster name | `otel-demo` |
| Region | `us-east-1` |
| Node type | `m5.xlarge` (16 GB RAM) |
| Node count | `3` |
| OIDC | Enabled (required for IRSA in A3) |

**Impact:** This is the compute cost — 3x m5.xlarge instances running 24/7.
The demo needs ~4-6 GB RAM across all services, so m5.xlarge with 3 nodes
provides headroom. Destroy when not in use to avoid cost.

---

## A3. EKS Access for Local kubectl

**Why:** EKS only grants cluster access to the IAM identity that created it.
Since GitHub Actions created the cluster, your local IAM role has no access
by default. You need to explicitly grant it.

**How:**
```bash
# Create access entry for your IAM role
aws eks create-access-entry \
  --cluster-name otel-demo --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE> \
  --type STANDARD

# Attach admin policy
aws eks associate-access-policy \
  --cluster-name otel-demo --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

# Update kubeconfig
aws eks update-kubeconfig --name otel-demo --region us-east-1
```

Use the IAM role ARN (e.g., `arn:aws:iam::123456:role/Admin`),
not the assumed-role STS ARN.

**Impact:** Without this, all kubectl commands fail with "the server has
asked for the client to provide credentials." This is a one-time step
per IAM identity.

---

## A4. IRSA (IAM Roles for Service Accounts)

**Why:** The OTel Collector pod needs AWS credentials to sign requests to
the X-Ray OTLP endpoint. IRSA injects short-lived, auto-rotating AWS
credentials into the pod without storing keys anywhere.

**How:** Created by `eksctl create iamserviceaccount` in the workflow.

| Resource | Value |
|----------|-------|
| K8s Service Account | `otel-collector` in namespace `otel-demo` |
| IAM Role | `otel-collector-xray-role` |
| IAM Policy | `otel-collector-xray-policy` |

IAM Policy permissions:
```json
{
  "Action": [
    "xray:PutTraceSegments",
    "xray:PutTelemetryRecords",
    "xray:GetSamplingRules",
    "xray:GetSamplingTargets"
  ],
  "Resource": "*"
}
```

Credential flow:
1. EKS injects `AWS_ROLE_ARN` + `AWS_WEB_IDENTITY_TOKEN_FILE` into the pod
2. The `sigv4auth` extension (see B1) reads these automatically
3. Short-lived tokens, auto-rotated by EKS — no static keys

**Impact:** Without IRSA, the collector has no AWS credentials and X-Ray
export fails with 403. This is the bridge between Kubernetes and AWS IAM.

---

## A5. Helm Service Account Ownership Workaround

**Why:** eksctl creates the `otel-collector` service account with label
`managed-by: eksctl`. When Helm tries to deploy, it refuses to manage
a resource it didn't create. Helm requires `managed-by: Helm`.

**How:** The workflow relabels the SA after IRSA creation:
```bash
kubectl annotate serviceaccount otel-collector \
  meta.helm.sh/release-name=otel-demo \
  meta.helm.sh/release-namespace=otel-demo --overwrite
kubectl label serviceaccount otel-collector \
  app.kubernetes.io/managed-by=Helm --overwrite
```

**Impact:** Without this, `helm install` fails with "invalid ownership
metadata" error. The SA keeps its IRSA IAM role annotation — only the
management labels change.

---

# Part B: OpenTelemetry Collector Configuration

These are changes to the OTel Collector config deployed via Helm values
(`scripts/helm-values-xray.yaml`). No application code changes — only
collector pipeline configuration.

---

## B1. SigV4 Auth Extension

**Why:** AWS OTLP endpoints require every HTTP request to be signed with
AWS Signature V4. This is how AWS authenticates the caller and checks
IAM permissions. Without it, X-Ray rejects requests with 403.

**How:** Added as a collector extension:
```yaml
extensions:
  sigv4auth:
    region: us-east-1
    service: xray
```

The extension picks up AWS credentials from IRSA (see A4) automatically
via the standard AWS credential chain (env vars → instance metadata).

**Impact:** Every OTLP HTTP request to X-Ray gets an `Authorization` header
with a SigV4 signature. Zero overhead on application services — only the
collector is affected. This is the only AWS-specific component in the
collector config; it's open-source (OTel Contrib), not AWS-proprietary.

---

## B2. X-Ray OTLP Exporter

**Why:** To send traces to AWS X-Ray for service map visualization,
trace analysis, and integration with other AWS services. X-Ray provides
a managed tracing backend without running your own infrastructure.

**How:** Uses the standard `otlphttp` exporter (NOT the `awsxray` plugin)
pointed at AWS's native OTLP endpoint:
```yaml
exporters:
  otlphttp/xray:
    endpoint: https://xray.us-east-1.amazonaws.com
    auth:
      authenticator: sigv4auth
```

Added to the traces pipeline alongside existing exporters:
```yaml
service:
  pipelines:
    traces:
      exporters: [otlp/jaeger, spanmetrics, otlphttp/xray, debug]
```

| Setting | Value |
|---------|-------|
| Exporter type | `otlphttp` (vanilla OTel, not `awsxray`) |
| Endpoint | `https://xray.<region>.amazonaws.com` |
| Protocol | HTTP only (no gRPC support) |
| Max payload | 5 MB uncompressed, 10,000 spans per batch |

**Impact:** Traces are sent to both Jaeger (in-cluster) and X-Ray (AWS)
in parallel. No impact on application services — they still send OTLP to
the collector as before. Adds minor network overhead for the second export.
X-Ray costs scale with trace volume (first 100k traces/month free).

---

## B3. Resource Detection (EKS + EC2)

**Why:** Without this, telemetry has no cloud context — you can't tell if
a service is running on EKS vs ECS vs Lambda, which region, which account,
or which cluster. Resource detection auto-discovers this metadata so you
can filter and group telemetry by cloud attributes.

**How:** Added `eks` and `ec2` detectors to the `resourcedetection` processor:
```yaml
processors:
  resourcedetection:
    detectors: [env, system, eks, ec2]
```

| Detector | What it queries | Attributes added |
|----------|----------------|-----------------|
| `env` | `OTEL_RESOURCE_ATTRIBUTES` env var | User-defined attributes |
| `system` | Local OS | `host.name`, `os.type` |
| `eks` | K8s API + EC2 IMDS | `cloud.platform: aws_eks`, `k8s.cluster.name` |
| `ec2` | EC2 IMDS (`169.254.169.254`) | `cloud.provider: aws`, `cloud.region`, `cloud.account.id`, `host.id`, `host.type`, `cloud.availability_zone` |

All four detectors are open-source OTel Contrib components. They run once
at collector startup, query metadata, and attach attributes to every
span/metric/log flowing through.

**Impact:** Every piece of telemetry gets enriched with cloud context.
In X-Ray, Grafana, or Prometheus you can filter by `cloud.platform`,
`cloud.region`, `k8s.cluster.name`, etc. If the collector isn't on
EKS/EC2, those detectors silently return nothing — no errors. Negligible
performance impact (one-time metadata query at startup).

---

## B4. Span Metrics Dimensions

**Why:** By default, the `spanmetrics` connector only generates metrics
with `service.name`, `span.name`, `span.kind`, and `status.code` labels.
This tells you "frontend handled 100 requests" but not "frontend called
checkout 50 times via gRPC" or "cart wrote to Redis 200 times." Adding
dependency and operation attributes as metric dimensions lets you answer
these questions from Prometheus without querying traces.

**How:** Added 12 span attributes as metric dimensions:
```yaml
connectors:
  spanmetrics:
    dimensions:
      - name: peer.service
      - name: server.address
      - name: net.peer.name
      - name: db.system
      - name: messaging.system
      - name: http.route
      - name: rpc.service
      - name: rpc.method
      - name: db.operation
      - name: db.name
      - name: messaging.operation
      - name: messaging.destination
```

**Dimensions explained:**

Dependency identification (who does this service call?):

| Dimension | Purpose | Example |
|-----------|---------|---------|
| `peer.service` | Target service name on client spans | `checkout` |
| `server.address` | Target host (fallback when peer.service absent) | `checkout:8080` |
| `net.peer.name` | Target host (legacy semantic convention) | `checkout` |
| `db.system` | Database type (for DB calls) | `redis`, `postgresql` |
| `messaging.system` | Message broker type (for async calls) | `kafka` |

Operation identification (what operation was performed?):

| Dimension | Purpose | Example |
|-----------|---------|---------|
| `http.route` | HTTP route pattern | `/api/products/{productId}` |
| `rpc.service` | gRPC service name | `oteldemo.CartService` |
| `rpc.method` | gRPC method name | `GetCart` |
| `db.operation` | Database operation | `SELECT`, `INSERT` |
| `db.name` | Database name | `otel` |
| `messaging.operation` | Messaging operation | `publish`, `receive` |
| `messaging.destination` | Queue/topic name | `orders` |

**Example PromQL queries:**
```promql
# Frontend dependencies by peer service
rate(traces_span_metrics_duration_milliseconds_count{
  service_name="frontend", span_kind="SPAN_KIND_CLIENT"
}[5m])

# Slowest gRPC operations (P95)
histogram_quantile(0.95, rate(traces_span_metrics_duration_milliseconds_bucket{
  rpc_service!=""
}[5m]))

# Database operation breakdown
rate(traces_span_metrics_duration_milliseconds_count{
  db_system!=""
}[5m])

# Kafka messaging throughput
rate(traces_span_metrics_duration_milliseconds_count{
  messaging_system="kafka"
}[5m])
```

**Impact:** Significantly increases metric cardinality in Prometheus.
Each unique combination of dimensions creates a new time series. For this
demo with ~18 services it's manageable. In production with high-cardinality
attributes (e.g., unique URLs in `http.route`), monitor Prometheus memory
and trim dimensions you don't actively query.

---

## B5. Telemetry Pipelines Summary

**Traces pipeline (customized):**
```
App Services → (OTLP) → OTel Collector → otlp/jaeger (in-cluster)
                                        → spanmetrics (connector → metrics)
                                        → otlphttp/xray (AWS X-Ray)
                                        → debug (stdout)
```

**Metrics pipeline (unchanged from vanilla):**
```
App Services → (OTLP) → OTel Collector → Prometheus (in-cluster)
                                        → Grafana (queries Prometheus)
```
Future: Add `awsemf` exporter for CloudWatch Metrics (no native OTLP
endpoint for CloudWatch Metrics yet).

**Logs pipeline (unchanged from vanilla):**
```
App Services → (OTLP) → OTel Collector → OpenSearch (in-cluster)
```
Future: Add `otlphttp` exporter to `https://logs.<region>.amazonaws.com/v1/logs`
for CloudWatch Logs (native OTLP endpoint available).

---

# Part C: Local Development & Files

---

## C1. Docker Compose Changes

**Why:** For local development without EKS, the docker-compose setup also
needs the X-Ray exporter configured.

| File | Change | Why |
|------|--------|-----|
| `.env` | Added `AWS_REGION=us-east-1` | Region variable for collector |
| `docker-compose.yml` | Passed `AWS_REGION` to collector container | Collector needs region at runtime |
| `src/otel-collector/otelcol-config-extras.yml` | X-Ray exporter + sigv4auth | Collector config for docker-compose |

Local runs need AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
mounted or passed into the collector container since there's no IRSA locally.

---

## C2. Files Changed from Upstream

| File | Category | Purpose |
|------|----------|---------|
| `.env` | Local dev | Added `AWS_REGION` |
| `docker-compose.yml` | Local dev | Passed `AWS_REGION` to collector |
| `src/otel-collector/otelcol-config-extras.yml` | OTel config | X-Ray exporter for docker-compose |
| `scripts/setup-iam-oidc.sh` | Infrastructure | GitHub OIDC + IAM role + policy |
| `scripts/setup-eks.sh` | Infrastructure | Local EKS cluster creation |
| `scripts/cleanup-eks.sh` | Infrastructure | Local EKS teardown |
| `scripts/helm-values-xray.yaml` | OTel config | All Helm overrides (B1-B4) |
| `scripts/README.md` | Docs | Deployment guide |
| `scripts/AWS_CUSTOMIZATIONS.md` | Docs | This file |
| `.github/workflows/eks-deploy.yml` | CI/CD | Deploy/destroy workflow |

---

## Quick Reproduce

```bash
# 1. IAM setup (one-time)
./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo

# 2. Add AWS_ROLE_ARN secret to GitHub repo

# 3. Push and trigger deploy workflow
git push
# Actions → "EKS Deploy / Destroy" → Run workflow → deploy

# 4. Grant local kubectl access (one-time per IAM identity)
aws eks create-access-entry --cluster-name otel-demo --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<ROLE> --type STANDARD
aws eks associate-access-policy --cluster-name otel-demo --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<ROLE> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
aws eks update-kubeconfig --name otel-demo --region us-east-1

# 5. Access
kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080
# http://localhost:8080          — Astronomy Shop
# http://localhost:8080/grafana  — Grafana (admin/admin)
# http://localhost:8080/jaeger/ui — Jaeger
# http://localhost:8080/loadgen  — Load Generator
# X-Ray: https://us-east-1.console.aws.amazon.com/xray/home#/traces
```
