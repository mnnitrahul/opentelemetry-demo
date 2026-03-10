# Multi-Platform Deployment Plan

Refactor the OpenTelemetry Demo to run across EKS, ECS, Lambda, and EC2
with AWS-managed dependencies (DynamoDB, S3, SQS) to simulate a real-world
distributed architecture.

## Service Distribution

| Platform | Services | Reason |
|----------|----------|--------|
| EKS | frontend, frontend-proxy, load-generator, flagd, flagd-ui, otel-collector, jaeger, grafana, prometheus, opensearch, kafka, postgresql, valkey-cart, accounting, fraud-detection, llm | Core app + all infra/telemetry |
| ECS + ALB (ASG capacity) | checkout, cart, product-catalog, product-reviews | Long-running gRPC services |
| Lambda + API Gateway | ad, recommendation, currency, quote, email | Stateless request-response (HTTP) |
| EC2 ASG + ALB | payment, shipping | Simulates legacy on-instance services |

## AWS-Managed Dependencies (New)

| Service | AWS Resource | How it's used |
|---------|-------------|---------------|
| DynamoDB | Table: `otel-demo-orders` | checkout writes order records after PlaceOrder |
| S3 | Bucket: `otel-demo-assets-{account}` | image-provider reads product images |
| SQS | Queue: `otel-demo-notifications` | email service reads from SQS instead of direct gRPC |

These add AWS SDK spans to traces, showing DynamoDB/S3/SQS as
dependencies in X-Ray service map.

## Architecture

```
                         Internet
                            │
                     frontend-proxy (EKS)
                            │
                       frontend (EKS)
                            │
     ┌──────────┬───────────┼───────────┬──────────────┐
     │          │           │           │              │
     ▼          ▼           ▼           ▼              ▼
  ECS+ALB   ECS+ALB     Lambda+APIGW  Lambda+APIGW  EC2+ALB
  checkout   cart        ad            currency      payment
  prod-cat   prod-rev    recommend.    quote         shipping
     │                   email
     │
     ├──→ DynamoDB (order records)
     ├──→ Kafka (EKS) → accounting, fraud-detection
     │
  S3 ←── image-provider (EKS)
  SQS ←── checkout → email (Lambda)

  All services → OTel Collector (EKS, internal ALB)
               → X-Ray + Jaeger + Prometheus
```

## Implementation Phases

### Phase 1: Shared Infrastructure
- VPC with public/private subnets (or reuse EKS VPC)
- Security groups for cross-platform communication
- ECR repos (not needed — using public ghcr.io images)
- DynamoDB table, S3 bucket, SQS queue
- IAM roles for ECS tasks, Lambda functions, EC2 instances
- Internal ALB for OTel Collector (so non-EKS services can send telemetry)

### Phase 2: ECS Deployment
- ECS cluster with ASG capacity provider
- ALB with gRPC-compatible target groups
- Task definitions for: checkout, cart, product-catalog, product-reviews
- ECS services behind ALB
- X-Ray tracing enabled on task definitions

### Phase 3: Lambda Deployment
- Lambda functions from container images: ad, recommendation, currency, quote, email
- API Gateway HTTP API with routes for each service
- ADOT Lambda layer for OTel instrumentation
- Application Signals enabled
- X-Ray active tracing on API Gateway and Lambda

### Phase 4: EC2 ASG Deployment
- Launch template with Docker + docker-compose for payment, shipping
- ALB with target groups
- ASG with desired=2, min=1, max=4
- User data script to pull and run containers

### Phase 5: Wiring
- Update EKS Helm values with ECS ALB, APIGW, EC2 ALB endpoints
- Expose OTel Collector via internal ALB
- Add sidecar/env config for non-EKS services to send OTLP to collector ALB
- Add AWS SDK calls (DynamoDB, S3, SQS) to relevant services

### Phase 6: Cleanup
- Single cleanup script that tears down in reverse order
- Lambda + APIGW → ECS → EC2 ASG → shared infra → EKS (optional)

## CloudFormation Stacks

| Stack | Resources | Depends on |
|-------|-----------|-----------|
| `otel-demo-shared` | VPC data, SGs, DynamoDB, S3, SQS, IAM roles | EKS cluster (for VPC) |
| `otel-demo-collector-alb` | Internal ALB for OTel Collector | EKS, shared |
| `otel-demo-ecs` | ECS cluster, ASG, capacity provider, ALB, task defs, services | shared |
| `otel-demo-lambda` | Lambda functions, API Gateway, ADOT layer | shared |
| `otel-demo-ec2` | Launch template, ASG, ALB, target groups | shared |

## Service Communication Changes

| From | To (current) | To (new) |
|------|-------------|----------|
| frontend → cart | `cart:7070` (K8s DNS) | ECS ALB: `cart.ecs.internal:7070` |
| frontend → checkout | `checkout:5050` (K8s DNS) | ECS ALB: `checkout.ecs.internal:5050` |
| frontend → ad | `ad:9555` (K8s DNS) | APIGW: `https://xxx.execute-api.us-east-1.amazonaws.com/ad` |
| frontend → currency | `currency:7001` (K8s DNS) | APIGW: `https://xxx.execute-api.us-east-1.amazonaws.com/currency` |
| frontend → payment | `payment:50051` (K8s DNS) | EC2 ALB: `payment.ec2.internal:50051` |
| checkout → email | `email:6060` (K8s DNS) | SQS queue (async) |
| All → collector | `otel-collector:4317` (K8s DNS) | Collector ALB: `collector.internal:4317` |

## OTel Instrumentation by Platform

| Platform | How instrumented | Collector endpoint |
|----------|-----------------|-------------------|
| EKS | Already instrumented (OTel SDK in each service) | `otel-collector:4317` (K8s DNS) |
| ECS | Same container images, same SDK | Collector internal ALB |
| Lambda | ADOT Lambda layer + Application Signals | Collector internal ALB |
| EC2 | Same container images, same SDK | Collector internal ALB |

## Files to Create

```
scripts/
  cfn/
    shared.yaml          # DynamoDB, S3, SQS, SGs, IAM roles
    collector-alb.yaml   # Internal ALB for OTel Collector
    ecs.yaml             # ECS cluster, ALB, tasks, services
    lambda.yaml          # Lambda functions, API Gateway
    ec2-asg.yaml         # Launch template, ASG, ALB
  deploy-multi-platform.sh   # Deploys all CFN stacks in order
  cleanup-multi-platform.sh  # Tears down all stacks
  helm-values-multi.yaml     # Updated Helm values with external endpoints
```

## Estimated Effort

| Phase | Complexity | Files |
|-------|-----------|-------|
| Phase 1: Shared infra | Medium | `shared.yaml` |
| Phase 2: ECS | High | `ecs.yaml` |
| Phase 3: Lambda | High | `lambda.yaml` |
| Phase 4: EC2 ASG | Medium | `ec2-asg.yaml` |
| Phase 5: Wiring | Medium | `helm-values-multi.yaml`, `collector-alb.yaml` |
| Phase 6: Cleanup | Low | `cleanup-multi-platform.sh` |

## Open Questions

1. The demo services use gRPC. Lambda + API Gateway only supports HTTP.
   For Lambda services (ad, recommendation, currency, quote, email),
   we need to either:
   a. Use the HTTP endpoints these services already expose (some do)
   b. Put an Envoy sidecar on EKS that translates gRPC→HTTP before
      calling API Gateway
   
   The frontend already calls these via gRPC. Option (b) is cleaner
   but adds complexity. Option (a) requires checking which services
   have HTTP endpoints.

2. Adding AWS SDK calls (DynamoDB, S3, SQS) requires code changes to
   the services. These are minimal (a few lines per service) but mean
   we're modifying the upstream application code. Is that acceptable?
