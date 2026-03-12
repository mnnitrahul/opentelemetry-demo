# AWS Deployment Scripts

Deploy the OpenTelemetry Astronomy Shop demo on AWS with X-Ray tracing.

Two deployment modes are available:

## 1. Single-Cluster EKS (original demo)

Runs the full demo on one EKS cluster with X-Ray export via OTel Collector.

```bash
./scripts/setup-iam-oidc.sh <github-org/repo>   # One-time IAM setup
./scripts/setup-eks.sh                            # Create cluster + deploy
```

Teardown: `./scripts/cleanup-eks.sh`

## 2. Multi-Platform (EKS + ECS + Lambda)

Extends the demo across EKS, ECS Fargate, and Lambda with cross-platform
X-Ray tracing. Full documentation:

**[MULTI_PLATFORM_README.md](MULTI_PLATFORM_README.md)** — single entry point for:
- Architecture and service inventory (20+ EKS services, 2 ECS, 4 Lambda)
- All AWS resources and IAM roles
- Step-by-step deployment (GitHub Actions or manual)
- 12 configuration changes with reason and impact
- Troubleshooting guide

```bash
./scripts/setup-iam-oidc.sh <github-org/repo>                    # One-time IAM setup
./scripts/deploy-multi-platform.sh --region us-east-1             # EKS + shared infra
./scripts/deploy-multi-services.sh --region us-east-1             # ECS + Lambda
```

Or just push to `main` — GitHub Actions deploys both modes automatically.

## Reference

- [MULTI_PLATFORM_README.md](MULTI_PLATFORM_README.md) — Multi-platform deployment guide
- [AWS_CUSTOMIZATIONS.md](AWS_CUSTOMIZATIONS.md) — Deep dive on OTel Collector config (sigv4auth, X-Ray exporter, resource detection, span metrics dimensions)

## Prerequisites

- AWS CLI v2, eksctl, kubectl, Helm v3, Docker, Python 3.12+
- GitHub repo with `AWS_ROLE_ARN` secret (from `setup-iam-oidc.sh`)

## Accessing the UIs

```bash
kubectl port-forward -n otel-demo svc/frontend-proxy 8080:8080   # Original
kubectl port-forward -n otel-demo svc/frontend-proxy 8081:8080   # Multi (different cluster)
```

| UI | URL |
|----|-----|
| Astronomy Shop | http://localhost:8080 |
| Grafana | http://localhost:8080/grafana |
| Jaeger | http://localhost:8080/jaeger/ui |
| X-Ray | https://us-east-1.console.aws.amazon.com/xray/home#/service-map |
