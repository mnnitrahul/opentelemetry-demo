# AWS Deployment Scripts

Scripts for deploying the OpenTelemetry Demo to AWS EKS with X-Ray trace integration.

## Architecture

```
Microservices → OTel Collector → Jaeger (traces, in-cluster)
                               → Prometheus (metrics, in-cluster)
                               → X-Ray (traces, AWS-managed via OTLP endpoint)
                               → OpenSearch (logs, in-cluster)

Grafana queries Jaeger + Prometheus for dashboards.
X-Ray traces available in the AWS Console.
```

## Prerequisites

- AWS CLI configured with admin credentials
- [eksctl](https://eksctl.io/) — `brew install eksctl`
- [kubectl](https://kubernetes.io/docs/tasks/tools/) — `brew install kubectl`
- [Helm](https://helm.sh/docs/intro/install/) — `brew install helm`

## Quick Start (Local)

```bash
# 1. Set up IAM (one-time)
./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo

# 2. Create EKS cluster and deploy
./scripts/setup-eks.sh

# 3. Access the demo
kubectl port-forward -n otel-demo svc/otel-demo-frontend-proxy 8080:8080
# Open http://localhost:8080

# 4. View X-Ray traces
# https://us-east-1.console.aws.amazon.com/xray/home?region=us-east-1#/traces

# 5. Tear down when done
./scripts/cleanup-eks.sh
```

## Quick Start (GitHub Actions)

```bash
# 1. Set up IAM (one-time)
./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo
# Copy the printed role ARN

# 2. Add the role ARN as a GitHub secret
#    Go to: Settings → Secrets and variables → Actions → New repository secret
#    Name:  AWS_ROLE_ARN
#    Value: arn:aws:iam::<ACCOUNT_ID>:role/github-actions-otel-demo

# 3. Push and trigger
git push -u origin main
#    Go to: Actions → "EKS Deploy / Destroy" → Run workflow → deploy

# 4. Destroy when done
#    Actions → "EKS Deploy / Destroy" → Run workflow → destroy
```

## Granting Local kubectl Access

The EKS cluster is created by GitHub Actions, so your local IAM identity
won't have cluster access by default. To grant it:

```bash
# 1. Create an access entry for your IAM role/user
aws eks create-access-entry \
  --cluster-name otel-demo \
  --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE> \
  --type STANDARD

# 2. Attach the cluster admin policy
aws eks associate-access-policy \
  --cluster-name otel-demo \
  --region us-east-1 \
  --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/<YOUR_ROLE> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster

# 3. Update kubeconfig
aws eks update-kubeconfig --name otel-demo --region us-east-1

# 4. Verify
kubectl get nodes
```

Note: Use the IAM role ARN (e.g., `arn:aws:iam::123456:role/Admin`),
not the assumed-role STS ARN.

## Accessing the UIs

After deployment, port-forward the frontend proxy:

```bash
kubectl port-forward -n otel-demo svc/otel-demo-frontend-proxy 8080:8080
```

Then open:

| UI | URL |
|----|-----|
| Astronomy Shop | http://localhost:8080 |
| Grafana | http://localhost:8080/grafana |
| Jaeger | http://localhost:8080/jaeger/ui |
| Load Generator | http://localhost:8080/loadgen |
| X-Ray Console | https://us-east-1.console.aws.amazon.com/xray/home?region=us-east-1#/traces |

Grafana default credentials: `admin` / `admin`

The load generator starts automatically with 5 simulated users, so
traces and metrics appear in all dashboards within a minute of deployment.

## Scripts

| Script | Purpose |
|--------|---------|
| `setup-iam-oidc.sh` | Creates GitHub OIDC provider, IAM policy, and IAM role. Idempotent. |
| `setup-eks.sh` | Creates EKS cluster, IRSA for X-Ray, deploys demo via Helm. |
| `cleanup-eks.sh` | Tears down Helm release, IRSA, IAM policy, and EKS cluster. |

## Configuration

All scripts default to:

| Parameter | Value |
|-----------|-------|
| Region | `us-east-1` |
| Cluster name | `otel-demo` |
| Node type | `m5.xlarge` |
| Node count | `3` |
| Namespace | `otel-demo` |

Edit the variables at the top of each script to change these.

The GitHub Actions workflow exposes these as inputs when triggering manually.
The deploy workflow is idempotent — it skips cluster creation if the cluster
already exists and uses `helm upgrade --install` for re-deploys.

## IAM Permissions

The `setup-iam-oidc.sh` script creates a policy covering:

- EKS, ECS, Lambda, API Gateway, ALB, Auto Scaling, EC2
- CloudFormation, IAM (role/policy/instance profile management)
- X-Ray, CloudWatch Logs, ECR, S3, KMS, SSM, STS

This is broad enough to support future migration of services to ECS, Lambda,
API Gateway, etc. without needing policy updates.

## What Changed from Upstream

- `src/otel-collector/otelcol-config-extras.yml` — Added X-Ray OTLP exporter with SigV4 auth
- `.env` — Added `AWS_REGION=us-east-1`
- `docker-compose.yml` — Passed `AWS_REGION` to collector container
- `scripts/` — Deployment and IAM scripts (this directory)
- `.github/workflows/eks-deploy.yml` — GitHub Actions workflow for deploy/destroy

## Next Steps

- [ ] Verify traces in X-Ray console and Jaeger UI
- [ ] Explore Grafana dashboards (span metrics, service latencies, infrastructure)
- [ ] Add `awsemf` exporter to send metrics to CloudWatch alongside Prometheus
- [ ] Replace in-cluster databases with AWS serverless equivalents:
  - PostgreSQL → Aurora Serverless v2
  - Valkey → ElastiCache Serverless
  - Kafka → MSK Serverless
  - OpenSearch → OpenSearch Serverless
- [ ] Expose frontend via ALB Ingress Controller instead of port-forward
- [ ] Split services across ECS, Lambda, API Gateway for a hybrid architecture
- [ ] Add CloudWatch Logs OTLP endpoint for logs export
- [ ] Set up CloudWatch alarms based on OTel metrics

## Troubleshooting: Multi-Platform Deployment

### CloudFormation stack stuck in ROLLBACK_COMPLETE or ROLLBACK_FAILED

The deploy script auto-detects these states and deletes the stack before
recreating. If it doesn't, manually delete:

```bash
aws cloudformation delete-stack --stack-name <stack-name> --region us-east-1
aws cloudformation wait stack-delete-complete --stack-name <stack-name> --region us-east-1
```

### Lambda "does not have permission to access the ECR image"

Lambda container images must come from ECR (not ghcr.io). The deploy script
mirrors images from ghcr.io to ECR and sets a repo policy allowing Lambda
to pull. If this fails:

1. Check the deploy logs for "Warning: could not set repo policy" messages
2. Manually set the policy on each ECR repo:

```bash
for svc in adservice recommendationservice currencyservice quoteservice emailservice; do
  aws ecr set-repository-policy \
    --repository-name "otel-demo/${svc}" \
    --region us-east-1 \
    --policy-text '{"Version":"2012-10-17","Statement":[{"Sid":"LambdaECRPull","Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":["ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"]}]}'
done
```

3. The Lambda execution role also needs `AmazonEC2ContainerRegistryReadOnly`
   managed policy (already added to the shared CFN stack).

### Lambda layers not supported with container images

Lambda container images cannot use layers (like the ADOT Lambda layer).
OTel instrumentation must be baked into the container image. The demo
images already include OTel SDKs, so spans are generated without the
ADOT layer. X-Ray active tracing (`TracingConfig: Active`) provides
AWS-vended traces automatically.

### ECS tasks crash-looping (VALKEY_ADDR, DB_CONNECTION_STRING, KAFKA_ADDR)

ECS services are deployed with `DesiredCount: 0` initially. The deploy
script scales them up after all infrastructure is ready. If tasks crash
after scaling:

- **cart**: Needs `VALKEY_ADDR` pointing to ElastiCache Serverless.
  ElastiCache Serverless requires TLS — the connection string must use
  `ssl=true` or the `rediss://` scheme.
- **product-catalog / product-reviews**: Need `DB_CONNECTION_STRING`
  pointing to Aurora Serverless v2. No TLS issues — plain connections work.
- **checkout**: Needs `KAFKA_ADDR` pointing to MSK Serverless bootstrap
  brokers. MSK Serverless requires TLS + IAM auth — the Kafka client
  must be configured for SASL/IAM authentication.

### IAM permission errors during CloudFormation deployment

The GitHub Actions IAM role needs broad permissions for CloudFormation
to create resources. If you see "not authorized to perform" errors:

1. Check which action is missing in the error message
2. Add it to `scripts/setup-iam-oidc.sh`
3. Re-run: `./scripts/setup-iam-oidc.sh mnnitrahul/opentelemetry-demo`
4. Push and re-trigger the workflow

Current wildcard permissions: `s3:*`, `sqs:*`, `dynamodb:*`, `logs:*`,
`elasticache:*`, `rds:*`, `kafka:*`, `kafka-cluster:*`.

### ALB target group protocol version errors

- `GRPC` and `HTTP2` protocol versions require HTTPS listeners (TLS certs)
- For plain HTTP listeners, omit `ProtocolVersion` (defaults to HTTP1)
- The demo uses HTTP1 target groups since we don't have TLS certificates

### service.name collision between EKS-only and multi-platform deployments

All multi-platform services use `multi-` prefixed `OTEL_SERVICE_NAME`
(e.g., `multi-checkout`, `multi-frontend`) and `service.namespace=otel-demo-multi`.
The original EKS-only deployment uses unprefixed names. Both can send
traces to the same X-Ray account without collision.
