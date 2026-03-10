# AWS Customizations Reference

Complete list of every change and configuration applied to run the
vanilla OpenTelemetry Demo on AWS EKS with X-Ray trace export.

No AWS-proprietary SDKs, agents, or exporters are used. Everything
is standard OTel SDK + OTel Collector Contrib.

---

## 1. GitHub OIDC → AWS IAM Trust

**What:** GitHub Actions authenticates to AWS without long-lived keys.

**Created by:** `scripts/setup-iam-oidc.sh`

| Resource | Value |
|----------|-------|
| OIDC Provider | `token.actions.githubusercontent.com` |
| IAM Role | `github-actions-otel-demo` |
| Trust | `repo:mnnitrahul/opentelemetry-demo:*` |
| GitHub Secret | `AWS_ROLE_ARN` → role ARN |

**IAM Policy** (`github-actions-otel-demo-policy`) covers:
- EKS, ECS, Lambda, API Gateway, ALB, Auto Scaling, EC2
- CloudFormation, IAM (role/policy/instance profile/OIDC management)
- X-Ray, CloudWatch Logs, ECR, S3, KMS, SSM, STS

Broad enough for future service migration without policy updates.

---

## 2. EKS Cluster

**What:** Kubernetes cluster for running the demo.

**Created by:** `setup-eks.sh` or GitHub Actions workflow

| Parameter | Value |
|-----------|-------|
| Cluster name | `otel-demo` |
| Region | `us-east-1` |
| Node type | `m5.xlarge` |
| Node count | `3` |
| OIDC | Enabled (required for IRSA) |

**EKS Access:** The cluster is created by GitHub Actions, so local
kubectl access requires:
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
Use the IAM role ARN, not the assumed-role STS ARN.

---

## 3. IRSA (IAM Roles for Service Accounts)

**What:** Gives the OTel Collector pod AWS credentials to call X-Ray.

**Created by:** `eksctl create iamserviceaccount` in the workflow

| Resource | Value |
|----------|-------|
| K8s Service Account | `otel-collector` in namespace `otel-demo` |
| IAM Role | `otel-collector-xray-role` |
| IAM Policy | `otel-collector-xray-policy` |

**IAM Policy permissions:**
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

**How it works:**
1. EKS injects `AWS_ROLE_ARN` + `AWS_WEB_IDENTITY_TOKEN_FILE` into the pod
2. `sigv4auth` extension reads these automatically
3. Signs every OTLP HTTP request with SigV4
4. Short-lived tokens, auto-rotated by EKS

**Helm workaround:** eksctl creates the SA with `managed-by: eksctl`
label. Helm needs `managed-by: Helm`. The workflow relabels it:
```bash
kubectl annotate serviceaccount otel-collector \
  meta.helm.sh/release-name=otel-demo \
  meta.helm.sh/release-namespace=otel-demo --overwrite
kubectl label serviceaccount otel-collector \
  app.kubernetes.io/managed-by=Helm --overwrite
```

---

## 4. X-Ray OTLP Endpoint

**What:** Traces exported to AWS X-Ray via standard OTLP protocol.

| Setting | Value |
|---------|-------|
| Exporter type | `otlphttp` (standard, NOT `awsxray` plugin) |
| Endpoint | `https://xray.us-east-1.amazonaws.com` |
| Auth | `sigv4auth` extension |
| Protocol | HTTP only (no gRPC) |
| Max payload | 5 MB uncompressed, 10,000 spans per batch |

**Collector config** (in `scripts/helm-values-xray.yaml`):
```yaml
extensions:
  sigv4auth:
    region: us-east-1
    service: xray

exporters:
  otlphttp/xray:
    endpoint: https://xray.us-east-1.amazonaws.com
    auth:
      authenticator: sigv4auth
```

Traces go to both Jaeger (in-cluster) and X-Ray (AWS) in parallel.

---

## 5. Resource Detection

**What:** Auto-tags all telemetry with AWS and Kubernetes metadata.

**Detectors** (all open-source OTel Contrib, not AWS-proprietary):

| Detector | Attributes added |
|----------|-----------------|
| `env` | Reads `OTEL_RESOURCE_ATTRIBUTES` env var |
| `system` | `host.name`, `os.type` |
| `eks` | `cloud.platform: aws_eks`, `k8s.cluster.name` |
| `ec2` | `cloud.provider: aws`, `cloud.region`, `cloud.account.id`, `host.id`, `host.type`, `cloud.availability_zone` |

```yaml
processors:
  resourcedetection:
    detectors: [env, system, eks, ec2]
```

---

## 6. Telemetry Pipeline (Traces)

**What:** Where traces flow and which exporters receive them.

```
App Services → (OTLP) → OTel Collector → otlp/jaeger (in-cluster)
                                        → spanmetrics (connector → metrics pipeline)
                                        → otlphttp/xray (AWS X-Ray)
                                        → debug (stdout logs)
```

Metrics stay on in-cluster Prometheus. Logs stay on in-cluster OpenSearch.

---

## 7. Metrics Pipeline (Unchanged)

No AWS endpoint for metrics. Stays fully in-cluster:

```
App Services → (OTLP) → OTel Collector → Prometheus (in-cluster)
                                        → Grafana (queries Prometheus)
```

To add CloudWatch metrics in the future, add the `awsemf` exporter
(no native OTLP endpoint for CloudWatch Metrics yet).

---

## 8. Logs Pipeline (Unchanged)

No AWS endpoint for logs configured. Stays in-cluster:

```
App Services → (OTLP) → OTel Collector → OpenSearch (in-cluster)
```

AWS does have a native OTLP endpoint for CloudWatch Logs at
`https://logs.<region>.amazonaws.com/v1/logs`. To add it:
```yaml
exporters:
  otlphttp/cloudwatch-logs:
    endpoint: https://logs.us-east-1.amazonaws.com
    headers:
      x-aws-log-group: "otel-demo"
      x-aws-log-stream: "collector"
    auth:
      authenticator: sigv4auth
```

---

## 9. Docker Compose Changes (Local Dev)

For local docker-compose runs (not EKS):

| File | Change |
|------|--------|
| `.env` | Added `AWS_REGION=us-east-1` |
| `docker-compose.yml` | Passed `AWS_REGION` to collector container |
| `src/otel-collector/otelcol-config-extras.yml` | X-Ray exporter + sigv4auth (hardcoded us-east-1) |

Local runs need AWS credentials mounted into the collector container.

---

## 10. Files Changed from Upstream

| File | Purpose |
|------|---------|
| `.env` | Added `AWS_REGION` |
| `docker-compose.yml` | Passed `AWS_REGION` to collector |
| `src/otel-collector/otelcol-config-extras.yml` | X-Ray exporter for docker-compose |
| `scripts/setup-iam-oidc.sh` | GitHub OIDC + IAM role + policy |
| `scripts/setup-eks.sh` | Local EKS cluster creation |
| `scripts/cleanup-eks.sh` | Local EKS teardown |
| `scripts/helm-values-xray.yaml` | All Helm overrides for AWS |
| `scripts/README.md` | Deployment guide |
| `scripts/AWS_CUSTOMIZATIONS.md` | This file |
| `.github/workflows/eks-deploy.yml` | CI/CD deploy/destroy workflow |

---

## Quick Reproduce

To recreate this entire setup from scratch:

```bash
# 1. IAM setup (one-time)
./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo

# 2. Add AWS_ROLE_ARN secret to GitHub repo

# 3. Push and trigger deploy workflow
git push
# Actions → "EKS Deploy / Destroy" → Run workflow → deploy

# 4. Grant local kubectl access
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
