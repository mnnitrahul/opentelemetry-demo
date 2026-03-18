# CloudWatch APM Vision — Research Document

**Author:** agarwalr | **Date:** 2026-03-17 | **Status:** Phase 1 Complete (Research)

---

## Table of Contents

1. [APM Industry Competitive Intelligence](#1-apm-industry-competitive-intelligence)
2. [AI Agent Observability Deep-Dive](#2-ai-agent-observability-deep-dive)
3. [CloudWatch Current State & Gaps](#3-cloudwatch-current-state--gaps)
4. [Key Themes for Vision Doc](#4-key-themes-for-vision-doc)

---

## 1. APM Industry Competitive Intelligence

### 1.1 Intelligent Root Cause Analysis (Service vs Dependency, Logical vs Infra)

**Datadog Watchdog**
- ML-based anomaly detection that auto-correlates across metrics, traces, and logs
- Automatically surfaces root cause — distinguishes between deployment-caused issues vs upstream dependency failures
- Zero-config. Root Cause Analysis and Log Anomaly Detection require no additional setup
- Available to all APM and Log Management users out of the box

**Dynatrace Davis AI + Grail**
- Causal AI engine running on Grail data lakehouse
- Builds real-time dependency model (Smartscape) to determine if a problem originates in your service, a dependency, or infrastructure
- Classifies problems as application, service, or infrastructure-level automatically
- Hyper-modal AI: combines causal, predictive, and generative AI for detailed root cause + impact analysis
- Automated anomaly detectors on Grail — customers can create custom Davis AI anomaly detectors for business-specific requirements
- Problems app presents every aspect of an incident backed by Grail data and Davis AI analysis

**New Relic Lookout**
- Deviation-based detection across all telemetry
- Highlights which entity is the actual source of degradation
- Change Tracking links deployments to performance changes

### 1.2 Latency Regression Detection

This is the hard problem. Exceptions are explicit; latency shifts are statistical.

**State of the Art Approaches:**
- Compare full latency distribution histograms (not just averages) pre/post deployment
- OTel span duration histograms enable this — an average can stay the same while tail latency doubles
- Need to compare the full shape of the latency distribution

**Datadog Deployment Tracking**
- Unified version tag correlates deploys with error rates, latency, request volume per endpoint
- Visualizes key performance metrics (requests/sec, error rate) during every code deployment
- Auto-flags regressions tied to specific deploys
- Identifies new error types for specific endpoints during deployments
- Works in both containerized and non-containerized environments

**Dynatrace Davis AI**
- Detects anomalies in response time baselines using adaptive thresholds per service/endpoint
- Predictive analytics to foresee potential issues before they occur

**Key Industry Gap:**
- Identifying *which span* in a trace caused the latency shift (not just that the overall trace got slower)
- Most tools detect the symptom (service X is slow) but not the specific code path causing it
- P95/P99 tail percentiles are critical — they reflect the experience of the slowest requests

### 1.3 Deployment & Code Integration

**Datadog Deployment Tracking**
- Uses unified version tag to analyze recent deployments
- Extends existing APM capabilities
- Visualizes key performance metrics during every code deployment

**New Relic Change Tracking**
- Links deployments to performance changes
- Supports GitHub webhook integration

**Industry Gap:**
- None of the major APMs deeply connect to GitHub issues/PRs — this is a whitespace opportunity
- Connecting "issue filed → code committed → deployed → performance impact" is not solved

### 1.4 Workflow / Business Transaction Mapping

**Dynatrace Business Analytics**
- Maps business-level KPIs to technical transactions
- Supports multi-step user journeys
- Batch job monitoring as first-class citizens with performance trends, failure pinpointing, bottleneck detection

**Industry Gap:**
- Most APMs represent flat service-to-service maps
- Complex nested workflows (e.g., order → payment → inventory → shipping with sub-steps) are poorly represented
- No standard for representing customer-defined business workflows with nested steps where each step makes multiple API calls

### 1.5 Service Maps & Dependency Visualization

**Datadog**
- Auto-traces requests from any popular library or framework
- Tracks data flows automatically and clusters services based on interdependencies in real-time
- ML-based Watchdog surfaces and auto-detects errors with zero configuration

**Dynatrace Smartscape**
- Real-time topology model of entire environment
- Used as foundation for causal AI root cause analysis

---

## 2. AI Agent Observability Deep-Dive

### 2.1 Standards Layer

#### OpenTelemetry GenAI Semantic Conventions (v1.40.0)

Dedicated section under OTel semconv: `gen-ai/` with sub-specs for Agent Spans, MCP, Metrics, Events.

**Three key agent span types:**

| Span Type | Operation Name | Use Case |
|---|---|---|
| Create Agent | `create_agent` | Agent creation (remote services like Bedrock Agents, OpenAI Assistants) |
| Invoke Agent | `invoke_agent` | Agent invocation. CLIENT kind for remote, INTERNAL for in-process |
| Execute Tool | `execute_tool` | Tool execution as child spans within agent trace |

**Key Attributes:**
- `gen_ai.agent.id` — unique identifier of the agent
- `gen_ai.agent.name` — human-readable name (e.g., "Math Tutor", "Fiction Writer")
- `gen_ai.agent.version` — version of the agent
- `gen_ai.agent.description` — free-form description
- `gen_ai.conversation.id` — unique identifier for conversation/session/thread
- `gen_ai.data_source.id` — data source identifier (for RAG applications)
- `gen_ai.tool.definitions` — list of tool definitions available to the agent
- `gen_ai.system_instructions` — system message/instructions provided to the model
- `gen_ai.input.messages` / `gen_ai.output.messages` — full chat history (opt-in, PII sensitive)

**Token Tracking:**
- `gen_ai.usage.input_tokens`
- `gen_ai.usage.output_tokens`
- `gen_ai.usage.cache_read.input_tokens`

**Provider-Specific Conventions:**
- AWS Bedrock (`aws.bedrock`) — dedicated semantic conventions
- OpenAI, Anthropic, Azure AI Inference, Cohere, DeepSeek, Gemini, Vertex AI, Groq, Mistral AI, Perplexity, xAI

**Span Kind Guidance:**
- `CLIENT`: Remote agent services (OpenAI Assistants API, AWS Bedrock Agents)
- `INTERNAL`: In-process agents (LangChain agents, CrewAI agents)

**MCP Semantic Conventions:**
- Dedicated page under `gen-ai/mcp/`
- MCP attributes registered in OTel registry under `mcp.*` namespace

**Status:** "Development" — not yet stable, but adoption accelerating (30% QoQ growth per industry reports)

#### OWASP Agent Observability Standard (AOS)

- Extends OTel and OCSF (Open Cybersecurity Schema Framework) — does NOT create new standards
- Maps to existing ones: OTel for tracing, OCSF for security events, CycloneDX/SPDX for inspectability
- Key concepts:
  - **Guardian Agent**: Policy enforcement agent that monitors other agents
  - **Standardized multi-agent trace views**: Holistic view across agent-to-agent interactions
  - **Instrumentation hooks**: For MCP and A2A (Agent-to-Agent) protocols
- Focus areas: auditability, compliance (SOC 2, GDPR), decision chain transparency

#### Microsoft Azure AI Foundry

- Contributing to OTel GenAI conventions
- Building unified multi-agent observability on W3C Trace Context
- Standardized logging for quality, performance, safety, and cost metrics across multi-agent systems
- Copilot Chat exports traces, metrics, and events via OTel following GenAI Semantic Conventions

### 2.2 Dedicated AI Observability Providers

| Provider | Key Differentiator | MCP Support | OTel Native | Scale |
|---|---|---|---|---|
| **Langfuse** | Open-source, self-hosted. Prompt management + cost tracking + evaluation datasets. Strong privacy story. | Via OTel | Yes | Growing OSS community |
| **Arize Phoenix** | First to ship MCP client-server tracing (April 2025). Embedding visualization, RAG quality scoring, drift detection. Integration with Oracle Agent Spec. | Yes (native) | Yes (OpenInference) | Enterprise |
| **LangSmith** | Tight LangChain integration. "Polly" AI assistant for understanding large traces. Evaluation + prompt playground. Agent observability powers agent evaluation. | Via LangChain | Partial | Dominant in LangChain ecosystem |
| **Sentry** | Launched MCP Server Monitoring (Aug 2025). Tracks every client, tool, and request. Single function call wrapper. | Yes (native) | Yes | 60M req/month, 5000+ orgs |
| **AgentOps** | Lightweight agent-specific monitoring. Session replay for agent runs. | Partial | Yes | Startup |
| **Traceloop/OpenLLMetry** | Auto-instrumentation for 40+ AI frameworks via CLI. Zero-code setup. | Via OTel | Yes (core) | OSS standard |
| **Helicone** | Lightweight API proxy monitoring. Caching, rate limiting, cost tracking. | No | Partial | Developer-focused |
| **Maxim AI** | Distributed tracing, multi-agent workflow support, evaluation capabilities, cross-functional collaboration. | Yes | Yes | Enterprise |

### 2.3 MCP Observability — The Emerging Frontier

MCP introduces unique observability challenges because it creates client-server boundaries within AI agent workflows.

**What needs to be traced:**
- Tool name and description
- Input parameters (with PII redaction)
- Execution duration
- Output summary or error status
- Parent span linking to the originating agent decision
- Transport type (stdio, SSE, HTTP)
- Client identity

**Sentry's Approach (Aug 2025):**
- Wrap MCP server with single function call → full visibility
- Tracks: client activity, transport distribution, tool and resource performance, errors (including silent ones MCP hides)
- Scaled from 30M to 60M requests/month
- 5,000+ organizations using it
- Gartner predicts by 2026, 75% of API gateway vendors and 50% of iPaaS vendors will have MCP features

**Arize Phoenix's Approach (April 2025):**
- First to ship MCP client-server tracing using OTel context propagation
- OpenInference-based instrumentation
- End-to-end traces across MCP client-server boundaries
- Runtime-agnostic observability with single setup step

**IBM Instana:**
- MCP observability integration providing deep visibility into MCP server and client interactions

**Key Insight:**
- MCP servers are often maintained by data/tool owners (not the agent developer), creating an observability ownership gap — similar to microservice boundary challenges
- Context propagation across MCP boundaries requires W3C Trace Context headers
- Silent errors in MCP are a major problem — MCP protocol can hide errors from the agent

### 2.4 AI Agent Trace Anatomy

A typical AI agent trace tree looks like:

```
invoke_agent "OrderProcessor" (root span)
├── chat (LLM call - reasoning step 1)
│   └── response: "I need to check inventory first"
├── execute_tool "check_inventory" (MCP server call)
│   ├── mcp.client → mcp.server (context propagation)
│   └── db.query "SELECT * FROM inventory WHERE..."
├── chat (LLM call - reasoning step 2)
│   └── response: "Inventory available, proceeding to payment"
├── execute_tool "process_payment" (MCP server call)
│   ├── http.request POST /payments
│   └── response: success
├── chat (LLM call - reasoning step 3)
│   └── response: "Payment processed, creating shipment"
└── execute_tool "create_shipment" (API call)
    └── http.request POST /shipments
```

**Key differences from traditional traces:**
- Multiple LLM calls interspersed with tool calls (reasoning loop)
- Agent may backtrack or retry (non-linear flow)
- Each LLM call has token usage and cost attributes
- Tool calls may cross MCP boundaries (distributed)
- The "why" (reasoning) is as important as the "what" (action)

### 2.5 What Makes AI Agent Observability Different from Traditional APM

| Dimension | Traditional APM | AI Agent Observability |
|---|---|---|
| Determinism | Same input → same output | Same input → different output (non-deterministic) |
| Failure modes | Exceptions, timeouts, errors | Hallucinations, policy violations, quality degradation, cost spikes |
| Trace shape | Linear request→response chains | Branching decision trees with loops (agent may retry, backtrack) |
| Key metrics | Latency, error rate, throughput | Token usage, cost/request, eval scores, guardrail violations |
| Duration | Milliseconds to seconds | Seconds to minutes (long-running agents) |
| Cost model | Compute-based (predictable) | Token-based (can explode unpredictably) |
| Quality measurement | Binary (success/failure) | Continuous (quality scores, groundedness, relevance) |
| Audit requirements | Standard logging | Full decision chain transparency |
| Debugging | Stack traces, logs | Reasoning chains, prompt analysis, tool call sequences |

### 2.6 Key Metrics for AI Workloads

**Cost & Usage:**
- Token usage (input/output/cached) per model call
- Cost per conversation/session (with attribution by team/project/user)
- Cache hit rate for prompt caching

**Performance:**
- Latency per LLM call and per tool execution
- Agent loop count (reasoning steps before completion)
- Tool call success/failure rate per tool
- Time-to-first-token (streaming scenarios)

**Quality & Safety:**
- Evaluation scores (groundedness, relevance, safety)
- Guardrail violation rate
- RAG retrieval quality (precision, recall, relevance)
- Hallucination detection rate

### 2.7 Auto-Instrumentation Libraries

| Library | Coverage | Setup |
|---|---|---|
| **OpenLLMetry (Traceloop)** | 40+ frameworks (LangChain, LlamaIndex, OpenAI, Anthropic, Bedrock, etc.) | CLI-based, zero-code |
| **OpenInference (Arize)** | LLM workflows, optimized for Phoenix | Single setup step |
| **OpenLIT** | Observability + built-in guardrails | Combined approach |
| **AG2 OTel Tracing** | Multi-agent systems (AG2/AutoGen framework) | Native integration |
| **Oracle Agent Spec** | Runtime-agnostic agent tracing | Spec-based |

Framework-specific auto-instrumentation:
- `LangchainInstrumentor().instrument()` — covers chains, agents, tools, vector stores
- Similar one-liner instrumentors for LlamaIndex, CrewAI, OpenAI Agents SDK, Microsoft Semantic Kernel

---

## 3. CloudWatch Current State & Gaps

### 3.1 Current APM Assets

**Application Signals (GA, actively evolving):**
- Auto-instrumentation for ECS, EKS, Lambda, EC2
- Prebuilt dashboards, SLOs
- SLO Recommendations, Service-Level SLOs, SLO Performance Report (March 2026)
- Application Map: auto-discovers service topology WITHOUT requiring instrumentation
- Contextual troubleshooting drawer with metrics and actionable insights
- Last deployment status visible in Application Map
- Automated audit findings concerning service performance

**Other Assets:**
- X-Ray traces
- ServiceLens
- CloudWatch Synthetics (canaries)
- CloudWatch RUM
- Container Insights
- Lambda Insights
- Contributor Insights
- Internet Monitor

### 3.2 AWS-Native Advantages (Competitors Cannot Replicate)

1. **Vended metrics/logs from 200+ AWS services** — zero instrumentation needed (ALB, API Gateway, Lambda, ECS, EKS, DynamoDB, SQS, SNS, Step Functions, Bedrock, etc.)
2. **Deep Bedrock integration** — model invocation metrics, token counts, guardrail metrics, agent session management
3. **Step Functions visual workflow execution** — per-step metrics, natural workflow model
4. **CodePipeline/CodeDeploy deployment events** — natively available
5. **Resource metadata** — CloudFormation stacks, tags, account topology, VPC context, IAM roles
6. **Cross-account observability** — built-in
7. **CloudWatch MCP Server** — already exists for querying operational data from developer tools

### 3.3 Key Gaps vs Competitors

| Capability | Datadog/Dynatrace | CloudWatch Today |
|---|---|---|
| Intelligent root cause analysis | Watchdog/Davis AI (ML/causal AI) | ❌ Manual investigation |
| Deployment-correlated regression detection | Auto-flags regressions per deploy | ❌ No deployment correlation |
| GitHub/code integration | Partial (deployment tracking) | ❌ None |
| Latency anomaly detection on traces | Adaptive thresholds, histogram comparison | ❌ Manual |
| Service vs dependency issue classification | Automatic (Smartscape/Watchdog) | ❌ Manual |
| Logical vs infra issue classification | Automatic | ❌ Manual |
| Business workflow mapping | Dynatrace Business Analytics | ❌ Limited to Step Functions |
| AI agent trace visualization | Emerging (via OTel) | ❌ Not available |
| MCP server monitoring | Sentry (native), Arize (native) | ❌ Not available |
| LLM cost attribution dashboards | Langfuse, Helicone, Datadog LLM Obs | ❌ Not available |
| Evaluation/quality scoring | LangSmith, Arize, Langfuse | ❌ Not available |

---

## 4. Key Themes for Vision Doc

Based on research, these are the recommended pillars for the vision document:

### Pillar 0: Application-Centric Experience (Foundation)
- Application is the primary unit of navigation — not services, not metrics
- Auto-infer application boundaries from CloudFormation stacks, tags, trace patterns, ECS/EKS groupings
- Allow manual refinement and custom grouping
- Every dashboard, alarm, SLO, and incident scoped to an application
- Software Catalog with ownership, contacts, runbooks, linked repos
- Scorecard/governance rules per application (inspired by Datadog Software Catalog)
- Application-level health score, cost attribution, dependency mapping

### Pillar 1: Zero-Instrumentation APM via AWS Resource Intelligence
- Leverage vended metrics, logs, and resource metadata from 200+ AWS services
- Auto-correlate across ALB → Lambda → DynamoDB → SQS without customer instrumentation
- Use CloudFormation/tags/account topology for context no third-party can match

### Pillar 2: Intelligent Root Cause Analysis
- Service vs dependency issue classification (inspired by Dynatrace Smartscape)
- Logical vs infrastructure issue classification
- Deployment-correlated regression detection (inspired by Datadog Deployment Tracking)
- Latency distribution comparison pre/post deployment (histogram-based, not just averages)
- Identify which specific span in a trace caused latency shift

### Pillar 3: Code-to-Observability Pipeline
- Connect GitHub issues → code commits → deployments → performance impact
- CodePipeline/CodeDeploy/CodeCommit native integration
- Whitespace opportunity — no competitor does this end-to-end

### Pillar 4: Customer Workflow Representation
- Support nested multi-step business workflows beyond Step Functions
- Each step can make multiple API calls — represent this in service map and service list
- Step Functions as the natural backbone, extended to generic workflow definitions
- Workflow-level SLOs and health indicators

### Pillar 5: AI Agent & MCP Observability
- Native Bedrock Agent tracing with OTel GenAI semantic conventions
- MCP server monitoring (tool calls, latency, errors, cost)
- Agent trace visualization (reasoning chains, tool call trees, branching decisions)
- Token usage and cost attribution dashboards
- Guardrail violation monitoring
- Multi-agent workflow visualization
- Leverage existing Bedrock vended metrics as foundation

### Pillar 6: Advanced Trace Analysis
- Latency regression detection using span duration histogram comparison
- Anomaly detection on trace data (not just metrics)
- Identify the specific span/code path causing latency shifts
- Exception detection is easy — latency change detection is the hard problem to solve

### Pillar 7: Database Observability Integrated into APM
- Trace-to-query-to-execution-plan correlation (inspired by Datadog DBM + APM)
- Click a slow database span in a trace → see the normalized query, execution plan, and DB load
- Query regression detection across deployments
- DynamoDB deep integration: throttling, consumed capacity, hot partition detection correlated with traces
- AI-powered root cause: "this query regressed and here are the affected services"

---

## 5. Application-Centric Observability & Application Definition

### 5.1 The Shift: Service-Centric → Application-Centric

Traditional APM is service-centric — each microservice is monitored independently. But customers think in terms of "applications" — a logical grouping of services that together deliver a business capability (e.g., "Checkout", "Search", "Recommendations"). The industry is shifting toward application-centric observability where the primary unit of monitoring is the application, not the individual service.

**Why this matters:**
- A single user request traverses dozens of services — monitoring each independently creates fragmented views
- Teams own applications, not individual services — ownership and accountability maps to applications
- SLOs, error budgets, and business KPIs are defined at the application level
- Incident response starts with "which application is impacted?" not "which service is failing?"
- Application-level blast radius analysis is more actionable than service-level

### 5.2 How Competitors Define "Application"

#### Datadog: Software Catalog + Custom Entities

- **Software Catalog** is the central registry — a "source of truth" for all components an organization operates
- Evolved from Service Catalog → Software Catalog to include any component type
- **Custom Entity Types** (Sep 2025): Platform teams can define any component — pipelines, libraries, AI agents, data jobs — as first-class entities
- Entity definition via YAML (apiVersion: v3), GitHub, API, or Terraform
- Each entity has: metadata, tags, links (runbooks, docs, repos), contacts, owner, additionalOwners
- **Teams** feature: Groups users by business units or project groups, scopes visibility to relevant resources
- **Scorecards**: Apply targeted rules per entity type (e.g., require version updates for libraries, CVE checks)
- **Key insight**: Datadog lets you model YOUR architecture YOUR way — not a fixed hierarchy

#### New Relic: Intelligent Workloads

- **Workloads** (original): All entities that combine to deliver a service are grouped using existing tags (e.g., multiple microservices, database, storage)
- **Intelligent Workloads** (Feb 2026): Automate discovery and mapping of complex dependencies for 360-degree view of performance, infrastructure, user impact, and business outcomes
- Aligns system health with business KPIs
- Automates service discovery — no manual grouping required
- Provides "Observability Beyond Human Scale" — AI-driven grouping and insight

#### Dynatrace: Automatic Detection + Custom Rules

- **Automatic application detection**: Deployed applications and microservices are automatically detected based on deployment properties (application identifier, URL patterns, server name)
- **Service Detection Rules**: Custom rules to fine-tune how services are detected and grouped
- **Cloud application and workload detection**: Automatic detection in Cloud Foundry, Docker, Kubernetes/OpenShift — groups similar processes into process groups and services
- **Application Detection Rules**: Define complex patterns to group RUM monitoring traffic into applications (beyond simple domain-based splitting)
- **Smartscape topology**: Automatically maps relationships between applications, services, processes, and hosts
- **Key insight**: Dynatrace auto-discovers the application topology and lets you customize grouping rules — the default is "it just works"

### 5.3 How to Define an Application — Approaches

| Approach | How It Works | Pros | Cons |
|---|---|---|---|
| **Tag-based grouping** | Services tagged with `app:checkout` are grouped together | Simple, flexible, works with existing tagging | Requires discipline, tags can drift |
| **Auto-discovery from traces** | Services that frequently communicate are auto-grouped | Zero-config, reflects actual behavior | May group unrelated services, noisy |
| **Infrastructure-based** | Services in same CloudFormation stack / ECS cluster / K8s namespace | Leverages existing infra boundaries | Infra boundaries ≠ application boundaries |
| **Manifest/catalog definition** | YAML/API definition of application → services mapping | Explicit, version-controlled, precise | Manual maintenance overhead |
| **Hybrid (recommended)** | Auto-discover + allow manual override/refinement | Best of both worlds | More complex to implement |

### 5.4 CloudWatch Current State

**What exists:**
- Application Signals Application Map: Auto-discovers and organizes services into groups based on configurations and relationships
- Supports custom grouping that aligns with business perspective (announced late 2025)
- Application Map displays nodes representing groups — drill down to view services and dependencies
- Resource Groups: Tag-based grouping of AWS resources (but not application-aware)

**What's missing:**
- No Software Catalog equivalent — no central registry of all components with ownership, contacts, runbooks
- No custom entity types — can't model libraries, pipelines, AI agents as first-class entities
- No scorecard/governance rules per application
- No automatic application detection from trace patterns
- Application definition is limited to what Application Signals auto-discovers + manual grouping
- No business KPI alignment at the application level

### 5.5 AWS-Native Opportunity for Application Definition

CloudWatch has unique signals that competitors cannot access for defining applications:

1. **CloudFormation Stacks**: A stack often represents an application — all resources in a stack are logically related
2. **ECS Services / EKS Namespaces**: Container groupings often map to applications
3. **Tags**: `aws:cloudformation:stack-name`, custom `Application` tags, `Team` tags
4. **Service Catalog / AppRegistry**: AWS Service Catalog AppRegistry already defines applications as collections of resources
5. **Step Functions State Machines**: Each state machine is a workflow/application
6. **CodePipeline**: Each pipeline deploys an application — the pipeline definition IS the application definition
7. **Resource Groups**: Already exist but not connected to observability
8. **X-Ray Groups**: Trace-based grouping with filter expressions

**The vision**: Automatically infer application boundaries from AWS resource relationships (CloudFormation, tags, trace patterns) and let customers refine. The application becomes the primary navigation unit in CloudWatch — every dashboard, alarm, SLO, and incident is scoped to an application.

### 5.6 What Application-Centric Experience Looks Like

**Entry point**: Customer opens CloudWatch → sees list of their Applications (not services, not metrics)

**Per-application view includes:**
- Health score (composite of SLOs, error rates, latency)
- Service map scoped to this application
- Last deployment status and performance impact
- SLOs and error budget burn rate
- Active incidents and alarms
- Owning team and contacts
- Dependencies (other applications this one depends on)
- Downstream consumers (applications that depend on this one)
- Cost attribution (compute, LLM tokens, data transfer)
- Linked resources (runbooks, docs, repos, pipelines)

**Key UX principle**: Start at the application, drill down to services, then to traces/logs/metrics. Never start at raw telemetry.

## 6. Database Observability & Slow Query Detection

### 6.1 Why Database Insight Matters for APM

Database queries are the most common root cause of application latency. A slow query doesn't just affect the database — it cascades through the entire request path. APM without database observability is incomplete because you can see *that* a service is slow but not *why* (the answer is often a specific SQL statement).

The key capability gap: connecting an APM trace span (e.g., "DynamoDB GetItem took 800ms") to the specific query, its execution plan, and the database-level metrics that explain the slowness.

### 6.2 How Competitors Do It

#### Datadog Database Monitoring (DBM)

- **Correlates DBM and APM traces**: From an APM trace, click on a database span to see the exact normalized query, its execution plan, and historical performance
- **Query regression detection**: Automatically detects when a query's performance degrades — compares current execution metrics against historical baselines
- **EXPLAIN ANALYZE integration**: Runs EXPLAIN ANALYZE on slow queries and associates the plan output with the underlying query AND related APM traces — full correlation from trace → query → execution plan
- **Normalized queries**: Strips PII from query parameters for safe storage and analysis
- **Supported databases**: PostgreSQL, MySQL, SQL Server, Oracle, MongoDB, Redis, and more
- **Key insight**: The trace-to-query-to-execution-plan pipeline is the killer feature — developers see the slow span in a trace and can immediately understand the database-level root cause

#### Dynatrace Database Monitoring

- **Automatic root cause analysis**: If database queries or commits slow down, Davis AI notifies immediately and shows which services are impacted
- **Query-level analytics with proactive health scoring**: AI-powered analysis of query performance trends
- **Top 200 queries monitoring**: Focuses on top 200 queries by resource consumption and execution time, sampled every 1 minute
- **Normalized queries**: Replaces literal parameter values with placeholders (PII protection)
- **Execution plan analysis**: DBAs can analyze query plans to optimize statement performance
- **Seamless integration with application monitoring**: Database issues are correlated with application-level performance data
- **Supported databases**: IBM DB2, MariaDB, SQL Server, MySQL, Oracle, PostgreSQL, SAP HANA, Snowflake
- **Key insight**: Davis AI correlates database slowness with application impact automatically — "this query slowed down, and here are the 5 services affected"

#### New Relic Database Monitoring

- Integrated into APM — database calls visible as spans in distributed traces
- Query analysis with slow query detection
- Less deep than Datadog/Dynatrace on execution plan analysis

### 6.3 CloudWatch Current State

**What exists:**
- **CloudWatch Database Insights** (replacing Performance Insights, which reaches EOL June 30, 2026):
  - Standard mode: Basic monitoring with 7-day retention
  - Advanced mode: Execution plans, on-demand analysis, extended retention
  - Slow SQL Queries section in Database Insights dashboard
  - DB load visualization — shows which queries contribute most to database load
  - Supports RDS (PostgreSQL, MySQL, MariaDB, Oracle, SQL Server) and Aurora
- **Vended metrics**: RDS/Aurora vend CPU, connections, storage, query latency metrics to CloudWatch automatically
- **Slow query logging**: Can be configured to capture slow queries in CloudWatch Logs, with log metric filters for alarming

**What's missing:**
- **No trace-to-query correlation**: Cannot click a database span in X-Ray/Application Signals and see the specific query + execution plan (Datadog's killer feature)
- **No query regression detection**: No automatic detection of query performance degradation over time
- **No cross-signal correlation**: Database Insights and Application Signals are separate experiences — no unified view showing "this trace is slow because this query regressed"
- **No DynamoDB query analysis**: Database Insights covers RDS/Aurora but not DynamoDB, which is the most common database for serverless workloads
- **No AI-powered root cause**: No equivalent to Davis AI saying "this query slowed down and here are the affected services"

### 6.4 AWS-Native Opportunity

1. **Database Insights + Application Signals integration**: Connect X-Ray trace spans to Database Insights query data — when a trace shows a slow DB span, link directly to the query, its execution plan, and DB load at that time
2. **DynamoDB deep integration**: DynamoDB already vends metrics (consumed capacity, throttling, latency per table/index). Correlate these with trace spans to show "this GetItem was slow because the table was throttling" — no competitor can do this for DynamoDB
3. **Aurora query plan analysis**: Aurora provides query execution plans — surface these in the APM trace context
4. **Query regression detection**: Compare query performance histograms across deployments (same approach as Pillar 6 latency regression, but at the query level)
5. **ElastiCache/MemoryDB**: Redis/Memcached vended metrics can explain cache miss patterns that cause database load spikes

### 6.5 The Vision for Database in APM

The developer experience should be:
1. See a slow trace in Application Signals
2. Click the database span → see the normalized query, execution plan, and DB load at that moment
3. See if this query regressed (historical comparison)
4. See if the root cause is the query itself (bad plan) or the database (resource saturation, throttling)
5. For DynamoDB: see consumed capacity, throttling events, and hot partition detection correlated with the trace

This closes the most common "last mile" gap in APM troubleshooting.

## References

- [OTel GenAI Agent Spans Spec](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-agent-spans/)
- [OTel GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [OWASP Agent Observability Standard](https://aos.owasp.org/)
- [OTel Blog: AI Agent Observability](https://opentelemetry.io/blog/2025/ai-agent-observability/)
- [Sentry MCP Server Monitoring](https://blog.sentry.io/introducing-mcp-server-monitoring)
- [Arize Phoenix MCP Tracing](https://arize.com/docs/phoenix/release-notes/04-2025/04-18-2025-tracing-for-mcp-client-server-applications)
- [AWS Application Signals](https://aws.amazon.com/cloudwatch/features/application-signals/)
- [AWS Application Map GA](https://aws.amazon.com/about-aws/whats-new/2025/10/application-map-generally-available-amazon-cloudwatch)
- [Datadog Watchdog](https://www.datadoghq.com/product/platform/watchdog/)
- [Dynatrace Davis AI RCA](https://www.dynatrace.com/news/blog/transform-your-operations-with-davis-ai-root-cause-analysis/)
- [Latency Regression via OTel Histograms](https://oneuptime.com/blog/post/2026-02-06-detect-latency-regression-otel-span-histograms/view)
- [Azure AI Foundry Multi-Agent Observability](https://techcommunity.microsoft.com/t5/azure-ai-foundry-blog/azure-ai-foundry-advancing-opentelemetry-and-delivering-unified/ba-p/4456039)
- [AG2 OpenTelemetry Tracing](https://docs.ag2.ai/0.11.0/docs/blog/2026/02/08/AG2-OpenTelemetry-Tracing/)
- [LangSmith Agent Observability](https://blog.langchain.com/agent-observability-powers-agent-evaluation/)

1. **Write Vision Doc** — 2-pager Amazon-style document using these research findings
2. **Director Review** — Critical review pass with feedback
3. **Revision** — Incorporate feedback and finalize
4. **UX Stories** — Extract critical user stories from the vision
- [New Relic Intelligent Workloads](https://newrelic.com/blog/apm/introducing-intelligent-workloads-providing-business-aligned-observability)
- [Datadog Software Catalog Custom Entities](https://www.datadoghq.com/blog/software-catalog-custom-entities/)
- [Dynatrace Service Detection Rules](https://docs.dynatrace.com/docs/analyze-explore-automate/services/service-detection-v1/customize-service-detection)
- [CloudWatch Application Map GA](https://aws.amazon.com/about-aws/whats-new/2025/10/application-map-generally-available-amazon-cloudwatch)
- [Datadog DBM + APM Correlation](https://docs.datadoghq.com/database_monitoring/connect_dbm_and_apm/)
- [Datadog Query Regression Detection](https://www.datadoghq.com/blog/database-monitoring-query-regressions/)
- [Dynatrace Database Monitoring](https://www.dynatrace.com/platform/database-observability/)
- [CloudWatch Database Insights](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_DatabaseInsights.SlowSQL.html)
- [Performance Insights to Database Insights Transition](https://repost.aws/articles/ARelTfHKHvTBC78mc-CNVqmA/performance-insights-to-cloudwatch-database-insights)

---

## Next Steps (Phase 2)

1. **Write Vision Doc** — 2-pager Amazon-style document using these research findings (8 pillars: Pillar 0-7)
2. **Director Review** — Critical review pass with feedback
3. **Revision** — Incorporate feedback and finalize
4. **UX Stories** — Extract critical user stories from the vision
