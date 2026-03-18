# CloudWatch APM: Closing the Experience Gap

**Author:** agarwalr | **Date:** 2026-03-17 | **Status:** Draft v2 (post Director review)

---

## 1. The Problem

CloudWatch has the telemetry. Application Signals auto-instruments services across ECS, EKS, Lambda, and EC2. The Application Map auto-discovers topology. Database Insights monitors query performance. X-Ray captures traces. Over 200 AWS services vend metrics and logs without customer instrumentation. Bedrock vends model invocation metrics and guardrail data.

The pieces exist. The problem is they don't talk to each other, and the experience doesn't match how customers actually troubleshoot.

When a customer's checkout flow degrades after a deployment, here is what they do today: open Application Signals to see service health, switch to X-Ray to find slow traces, open Database Insights in a separate tab to check query performance, manually check CodeDeploy for recent deployments, and grep CloudWatch Logs for exceptions. They are the correlation engine. Every competitor — Datadog, Dynatrace, New Relic — has solved this by connecting these signals into a single troubleshooting flow. We have not.

Additionally, two shifts are creating new gaps:

First, customers increasingly think in terms of *applications* (a logical group of services delivering a business capability), not individual services. Datadog's Software Catalog, New Relic's Intelligent Workloads, and Dynatrace's automatic application detection all reflect this. Application Signals' Application Map has started this journey with auto-discovered service groups, but the experience is still service-first.

Second, AI agent workloads are growing rapidly on Bedrock and open-source frameworks. These workloads have fundamentally different observability needs — reasoning chains, tool calls, MCP server interactions, token costs, guardrail violations — and OpenTelemetry has defined GenAI semantic conventions to standardize this telemetry. We are not yet consuming these signals.

This document proposes targeted improvements that connect existing CloudWatch capabilities and fill specific gaps — not a platform rewrite.

### Data Foundation: Sampling and Metrics

A critical enabler: Application Signals computes service-level metrics (latency, error rate, throughput) from 100% of spans before sampling traces for storage. This means our deployment correlation (3.2) and issue classification (3.4) can operate on complete metrics data, not sampled traces. However, trace-level features (3.7 span-level latency comparison, 3.3 trace-to-DB correlation) operate on sampled trace data. For these features, statistical reliability depends on sample size. We should document minimum traffic thresholds for reliable span-level comparisons and consider offering configurable sampling rates for customers who want higher fidelity.

---

## 2. Approach: Connect, Correlate, Extend

Our strategy is three verbs:

- **Connect** existing CloudWatch experiences that are currently siloed (Application Signals ↔ Database Insights ↔ Deployment events ↔ Logs)
- **Correlate** signals automatically so the customer doesn't have to be the correlation engine (deployment → regression, trace span → query → execution plan, service fault → dependency vs own code)
- **Extend** to new workload types using open standards (AI agents, MCP, business workflows)

### Primary Customer

The primary customer is the **SRE / on-call engineer** investigating a production issue at 2 AM. Every design decision optimizes for their workflow: fast triage, quick classification (my code? dependency? infrastructure?), and a clear path to root cause. The secondary customer is the **developer** investigating a post-deployment regression during business hours. The tertiary customer is the **ML/AI engineer** operating agent workloads. We design for the SRE first and validate that the experience also serves developers and ML engineers.

### Priority Order

Not all seven initiatives are equal. We sequence by customer impact and implementation feasibility:

| Priority | Initiative | Why This Order |
|---|---|---|
| P0 | 3.2 Deployment → Performance correlation | Highest-frequency pain point. Uses existing data (CodeDeploy events + Application Signals metrics). Mostly a rendering/UX change. Quick win. |
| P0 | 3.4 Enrich traces with correlated logs (inline) | Already partially exists (trace-to-log correlation). Surfacing logs inline in trace view is a rendering change. Highest-impact for SRE "2 AM troubleshooting" persona. |
| P0 | 3.5 Issue classification (service vs dependency, code vs infra) | Core SRE need. Uses existing dependency graph and infrastructure metrics. Rule-based, no ML. |
| P1 | 3.1 Application as entry point | Foundational UX change. Builds on existing Application Map grouping. Enables all other initiatives to be application-scoped. |
| P1 | 3.3 Trace → Database query correlation | High-value for the "last mile" of troubleshooting. DynamoDB correlation is the flagship differentiator — no competitor can match it. Requires cross-team work with Database Insights team. |
| P2 | 3.8 Trace-level latency comparison | Powerful debugging tool. Pure visualization on existing data. Lower priority because it serves the developer persona more than the SRE. Note: reliability depends on sampling rate. |
| P2 | 3.7 AI Agent / MCP observability | Forward-looking, growing customer base. Bedrock vended metrics make the Bedrock path fast. OTel GenAI conventions are still "Development" status (see risk mitigation). |
| P3 | 3.6 Workflow representation | Valuable but narrower audience. Step Functions integration is straightforward; generic workflow config needs more design. |

---

## 3. What We Will Do

### 3.1 Make the Application the Entry Point

Application Signals' Application Map already auto-discovers and organizes services into groups. We build on this.

**What changes:**
- The CloudWatch APM landing page becomes a list of applications with composite health scores (derived from existing SLOs, error rates, latency metrics). Customers click into an application, not a service.
- Each application shows: owning team (from resource tags), last deployment status (from CodeDeploy/CodePipeline events already available in CloudWatch), active alarms, SLO burn rate, and dependency health.
- Application boundaries are auto-inferred from existing signals: CloudFormation stack membership, ECS service groupings, EKS namespace, resource tags (`Application`, `Team`), and trace communication patterns. Customers refine with manual overrides — the same custom grouping capability Application Map already supports. **Honest caveat:** Auto-inference will produce wrong groupings for a significant percentage of customers — many have one giant CloudFormation stack, inconsistent tags, or EKS namespaces that don't map to applications. Wrong groupings erode trust faster than no groupings. Therefore: auto-inferred groups are presented as *suggestions* ("we think these services form an application — confirm or edit"). Manual grouping is the primary mechanism. Auto-inference is a convenience, not a requirement.
- Application-scoped views for service map, traces, logs, and metrics — filtering by application context, not requiring customers to manually scope every query.

**What we are NOT building:** A full software catalog (Backstage/Datadog Software Catalog equivalent). We use existing AWS resource metadata — tags, CloudFormation, AppRegistry — as the lightweight catalog. No new metadata schema for customers to adopt.

### 3.2 Connect Deployments to Performance

CodeDeploy and CodePipeline already emit deployment events that CloudWatch can access. Application Signals already tracks latency and error rates per service and API.

**What changes:**
- Deployment events appear as vertical markers on Application Signals performance charts (latency, error rate, throughput). When a customer sees a latency spike, they immediately see "deployment v2.3.1 happened here."
- For each deployment, we show a before/after comparison of key metrics — p50, p95, p99 latency, error rate — for the APIs in that service. This is a comparison view, not ML-based anomaly detection. The customer judges whether the change is a regression.
- When a regression is identified, we link to the deployment details: what changed (version/commit info from CodeDeploy), which pipeline triggered it.
- Stretch: integrate with GitHub webhooks to show commit messages and PR links alongside deployment markers. CodeCommit integration is simpler and can come first.

**Non-AWS deployment tools:** Many EKS customers deploy with ArgoCD, Helm, Spinnaker, or Flux — not CodeDeploy. We support these through two mechanisms: (a) Kubernetes deployment events are available via the K8s API and Container Insights already monitors EKS — we surface K8s rollout events as deployment markers regardless of which tool triggered them. (b) AWS recently launched EKS Capability for Argo CD as a managed service — we can consume ArgoCD sync events natively. For other tools, customers can push deployment events via the CloudWatch API (a lightweight integration).

**What we are NOT building:** Automated regression detection with ML (Datadog Watchdog equivalent). We start with a visual comparison tool. Automated detection can follow once we have the data pipeline.

### 3.3 Connect Traces to Database Queries

Application Signals captures trace spans for database calls. Database Insights captures query performance, execution plans, and DB load. Today these are separate experiences.

**What changes:**
- When a customer clicks a database span in a trace, they see the normalized query, its execution time relative to historical baseline, and a link to the Database Insights view for that query at that point in time.
- For RDS/Aurora: surface the execution plan from Database Insights in the trace context. The customer sees the slow span AND understands why (full table scan, missing index, lock contention).
- Slow query alarms: when Database Insights detects a query regression, surface it in the Application Signals service view for the application that uses that database.

**DynamoDB deep correlation (key differentiator):** This deserves special emphasis. DynamoDB is the most-used database for serverless and modern workloads on AWS. No competitor can correlate DynamoDB operations with application traces at the level we can. We correlate trace spans with DynamoDB vended metrics — consumed capacity per operation, throttling events, table/index-level latency, and hot partition detection. When a GetItem span is slow, we show whether the table was throttling, which partition was hot, and whether provisioned capacity was exhausted. This is potentially the single most differentiated feature in this entire document — it should be treated as a flagship capability, not a sub-bullet.

**What we are NOT building:** A new database monitoring product. We connect Database Insights (which already exists and is replacing Performance Insights) to Application Signals traces.

### 3.4 Enrich Traces with Correlated Logs

Application Signals already supports trace-to-log correlation — it auto-injects trace IDs and span IDs into application logs and displays related log entries on the trace details page. This exists today but is underutilized.

**What changes:**
- When a trace span shows an error, we automatically surface the relevant log lines (filtered by trace ID and time window) inline in the trace view — not as a separate tab the customer has to navigate to.
- For the SRE troubleshooting at 2 AM, the flow is: see error span → see the exception stack trace from the log right there → understand the root cause. No context switching to CloudWatch Logs Insights.
- For AWS service spans (Lambda, API Gateway), correlate with the service's CloudWatch Log Group automatically using resource metadata.

**What we are NOT building:** A new log search engine. We use existing CloudWatch Logs Insights queries, scoped by trace ID and time window, and render the results inline in the trace view.

### 3.5 Classify Issues: Service vs Dependency, Code vs Infrastructure

Application Signals already knows the dependency graph from traces. CloudWatch already has infrastructure metrics (CPU, memory, throttling) for the underlying compute.

**What changes:**
- When a service shows elevated errors or latency, we check its dependencies (from the trace-derived dependency graph). If a dependency is also degraded, we surface "dependency issue — [Payment Service] is experiencing elevated error rates" rather than just showing the symptom on the caller.
- We correlate application-level signals with infrastructure signals for the same compute. If latency spikes coincide with ECS task CPU > 90% or DynamoDB throttling, we tag the issue as "infrastructure" and suggest scaling. If application errors spike with normal infrastructure metrics, we tag it as "application/code" and point to recent deployments.
- This is rule-based correlation using existing signals, not ML. The rules are: check dependency health first, then check infrastructure metrics, then check for recent deployments.

**Classification logic (deterministic rules):**
1. When a service's error rate or p95 latency exceeds its SLO threshold (or a configurable baseline):
2. Check downstream dependencies: if any dependency's error rate or latency also exceeds its baseline *and* the caller's errors correlate with the dependency's errors (same time window, error responses match dependency calls), classify as **dependency issue** and name the dependency.
3. If dependencies are healthy, check infrastructure: if the service's compute shows CPU > 85%, memory > 90%, or the backing AWS resource shows throttling (DynamoDB, SQS, Lambda concurrency), classify as **infrastructure issue** and name the resource.
4. If infrastructure is healthy, check deployments: if a deployment occurred within the lookback window (configurable, default 2 hours), classify as **possible deployment regression** and link to the deployment.
5. If none of the above, classify as **unknown — requires investigation** and surface the raw signals.

**Acknowledged limitation:** These rules will produce false positives (e.g., a dependency blip that coincides with but doesn't cause the caller's issue). A specific blind spot: shared-cause scenarios where two services degrade simultaneously due to a common root cause (AZ failure, shared database saturation, network partition) — the rules may incorrectly label one as a "dependency issue" when both are victims. We start with this as a *suggestion* in the troubleshooting drawer, not an authoritative verdict. Customers validate and we iterate on the rules based on feedback.

**What we are NOT building:** A causal AI engine (Dynatrace Davis). We build deterministic correlation rules using signals we already have. This covers the 80% case.

### 3.6 Support Customer Workflows in the Application Map

Customers have multi-step business workflows where each step involves multiple services. The Application Map shows service-to-service edges but not the business workflow structure.

**What changes:**
- For Step Functions: each state machine appears as a workflow node in the Application Map. Customers can expand it to see per-step health (success rate, latency). Step Functions already provides this data — we surface it in the Application Map context rather than requiring customers to switch to the Step Functions console.
- For non-Step-Functions workflows: customers can define a workflow as an ordered list of services/APIs using a simple configuration (tag-based or YAML). The Application Map renders these as grouped, ordered nodes. Per-step SLOs can be set on each service/API in the workflow. The configuration lives as a CloudWatch resource (similar to how SLOs are defined today) and can be created via console, CLI, or CloudFormation. Example: `workflow: [validate-service:/validate, payment-service:/charge, inventory-service:/reserve, shipping-service:/ship]`.
- Workflow-level health: composite health score across all steps. "The Order Processing workflow is degraded because the Payment step has a 2% error rate."

**What we are NOT building:** A generic workflow orchestration engine. We render existing workflows (Step Functions natively, others via lightweight config) in the observability context.

### 3.7 AI Agent and MCP Observability

Bedrock already vends model invocation metrics (latency, token counts, throttling, guardrail violations). OpenTelemetry GenAI semantic conventions (v1.40.0) define standardized spans for agent invocations (`invoke_agent`), tool executions (`execute_tool`), and MCP interactions. Auto-instrumentation libraries (OpenLLMetry, OpenInference) exist for LangChain, CrewAI, and other frameworks.

**What changes:**
- Application Signals ingests OTel GenAI spans and renders agent traces as structured views — showing the reasoning chain (LLM calls), tool invocations, and MCP server calls as a tree, not a flat span waterfall. This is a rendering change on existing X-Ray/OTel trace data. **Design risk:** Agent traces are non-linear — agents loop, backtrack, and branch. A tree view works for simple agents but becomes unwieldy when an agent loops 8 times or delegates to sub-agents. We start with single-agent, linear-chain rendering (which covers the majority of Bedrock Agent and simple LangChain workloads) and iterate on the UX for complex branching/looping patterns based on real customer traces.
- For Bedrock Agents: zero-instrumentation agent observability using vended metrics and traces. Token usage, cost per conversation, guardrail violation rate, and tool call success rates as prebuilt dashboard widgets.
- For open-source frameworks on ECS/EKS: support OTel GenAI auto-instrumentation (OpenLLMetry covers 40+ frameworks with zero-code setup). Application Signals already supports OTel — this is about recognizing and rendering `gen_ai.*` attributes.
- MCP tool call monitoring: when agent traces include MCP tool calls (via OTel context propagation), surface tool-level metrics — latency, error rate, invocation count per tool. Flag silent MCP errors that the protocol hides from the agent.
- Cost dashboard: aggregate token usage across Bedrock model invocations, broken down by application/service/agent. Bedrock already vends this data — we aggregate and visualize it.

**Conversation-level aggregation:** AI workloads think in conversations (sessions), not individual requests. A single conversation may span dozens of LLM calls and tool invocations over minutes. OTel GenAI conventions define `gen_ai.conversation.id` — we aggregate metrics at this level: cost per conversation, tool calls per conversation, latency per conversation, guardrail violations per conversation. This is the unit AI engineers care about. Without this, cost and performance data is fragmented across individual spans.

**Cost alerting (critical for AI workloads):** Token costs can explode — a single agent stuck in a reasoning loop can burn thousands of dollars in minutes. Industry data shows agents running 62-136x the cost of single-turn inference. We provide:
- Cost anomaly alarms: "Agent X's cost per conversation exceeded 3x its 7-day rolling average" — built on CloudWatch Anomaly Detection applied to token cost metrics.
- Budget thresholds per application/agent with automatic alarms.
- Loop detection: flag conversations where the agent's reasoning step count exceeds a configurable threshold (e.g., >15 LLM calls in a single conversation).

This is not optional — it's a safety requirement for production AI workloads.

**Guardrail violation trending:** Bedrock guardrail violations are an operational proxy for quality degradation. If violations spike 5x this week vs last week — even with zero errors and normal latency — something changed (model update, stale RAG data, prompt drift). We surface guardrail violation trends as a first-class metric alongside latency and error rate, with alarms.

**RAG pipeline visibility:** Most production AI agents use RAG (query → embedding → vector search → retrieve documents → LLM call). Each step can degrade independently. OTel GenAI conventions include `retrieval` as an operation type and `gen_ai.data_source.id` for data sources. We render RAG steps as distinct spans in the agent trace: embedding latency, vector search latency, number of documents retrieved, and (for Bedrock Knowledge Bases) retrieval relevance scores. This gives visibility into the most common AI architecture pattern.

**What we are NOT building:** An evaluation/quality scoring platform (LangSmith/Langfuse territory). We focus on operational observability — performance, cost, errors, guardrails — not prompt engineering or output quality assessment. We also defer multi-model routing observability (which model handled which traffic, fallback triggers) to a later phase — it requires understanding the customer's routing logic which varies widely.

**Spec stability risk:** OTel GenAI semantic conventions are currently "Development" status, not stable. The spec could change before stabilization. Mitigation: we adopt the conventions behind a feature flag, pin to a specific semconv version (v1.40.0), and track the spec working group. Bedrock-vended telemetry is not affected by this risk since we control that format. The risk is limited to open-source framework instrumentation (LangChain, CrewAI) which uses the OTel conventions.

### 3.8 Trace-Level Latency Comparison

**What changes:**
- For any two time windows (typically pre/post deployment), show a side-by-side comparison of latency distributions at the span level — not just the root trace.
- For each span in the trace, show the p50/p95/p99 delta between the two windows. Highlight spans where latency increased significantly.
- This is a query/visualization feature on existing trace data, not a new data pipeline. X-Ray/Application Signals already stores span durations — we add a comparison view.

**What we are NOT building:** Automated "this span caused the regression" detection. We provide the comparison tool; the customer identifies the culprit. Automation can follow.

---

## 4. Tenets

1. **Connect before you build.** If two existing CloudWatch features have the data, connect them before building something new.
2. **Application-first navigation.** Every experience starts with the application. Drill down to services, then to traces/logs/metrics.
3. **Rules before ML.** Deterministic correlation rules using existing signals cover the 80% case. ML-based detection is a follow-on, not a prerequisite.
4. **AWS depth, open standards.** Build on OTel for interoperability. Go deeper with AWS-native signals (vended metrics, resource metadata, DynamoDB internals) that no OTel-only solution can provide.
5. **Render, don't re-ingest.** For AI agent traces, workflow visualization, and database correlation — the data already exists. We need better rendering and cross-linking, not new data pipelines.

---

## 5. Customer Scenarios

**Scenario 1: Post-deployment regression**
SRE opens CloudWatch → sees "Checkout" application health is degraded → Application Signals shows p95 latency increased 40ms → deployment marker shows v2.3.1 deployed 30 minutes ago → before/after comparison highlights the `inventory-check` span increased by 35ms → clicks the database span → sees the `SELECT * FROM inventory` query switched to a full table scan after a schema migration in the deployment → links to the CodeDeploy deployment details and commit.

**Scenario 2: Dependency vs own code**
Alarm fires for "Search" application → Application Signals shows elevated error rates → dependency check shows the downstream "Product Catalog" service is returning 503s → issue classified as "dependency issue" → SRE pages the Product Catalog team instead of investigating their own code.

**Scenario 3: AI agent cost spike**
ML engineer gets a cost anomaly alarm: "Customer Support Agent cost per conversation exceeded 3x its 7-day average." Opens CloudWatch → conversation-level dashboard shows average cost jumped from $0.12 to $0.38 per conversation → drills into high-cost conversations → sees the agent is making 3x more tool calls per conversation since a prompt change, with several conversations flagged for loop detection (>15 reasoning steps) → one MCP tool (`knowledge-base-search`) has a new 2-second latency causing retries → guardrail violation trend shows a 5x spike this week → engineer reverts the prompt change and investigates the MCP server latency.

**Scenario 4: Workflow degradation**
Product manager checks "Order Processing" workflow → per-step health shows the "Payment" step has 2% error rate (SLO breach) → drills into Payment step → sees it's a DynamoDB throttling issue on the transactions table → infrastructure classification confirms it's not a code bug → team increases DynamoDB provisioned capacity.

**Partial adoption note:** These scenarios assume full feature adoption. In practice, customers may not have Database Insights enabled, may not use CodeDeploy, or may not have consistent tags. The experience degrades gracefully: without deployment events, the deployment marker simply doesn't appear. Without Database Insights, the database span shows trace-level timing but not the query/execution plan. Without tags, application grouping falls back to trace-based auto-discovery. Each feature adds value independently — they don't require all-or-nothing adoption.

---

## 6. Success Metrics

| Metric | How We Measure | Target |
|---|---|---|
| MTTR reduction for Application Signals users | Compare mean time from alarm to resolution before/after, using CloudWatch incident data | 20% reduction |
| Application-scoped view adoption | % of Application Signals users who navigate via application entry point vs direct service access | >50% within 6 months of launch |
| Deployment correlation usage | % of services with deployment markers visible on performance charts | >30% of Application Signals services |
| Cross-feature navigation | Click-through rate from trace span → Database Insights, from alarm → deployment details | Baseline + 3x |
| AI observability adoption | Number of applications with GenAI trace data rendered in Application Signals | Track growth, no hard target (emerging market) |

---

## 7. What We Are NOT Doing

- Not building a causal AI engine (Davis/Watchdog equivalent). We start with deterministic rules.
- Not building a software catalog or IDP. We use existing AWS resource metadata.
- Not building an LLM evaluation platform. We do operational observability for AI workloads.
- Not replacing Database Insights. We connect it to Application Signals.
- Not building a CI/CD tool. We consume deployment events.
- Not rewriting the CloudWatch console. We add application-scoped views and cross-linking to existing experiences.

---

## 8. Open Questions

1. Should DynamoDB trace-to-metrics correlation be a separate launch or bundled with the Database Insights ↔ Application Signals connection?
2. For AI agent trace rendering — do we build a custom visualization or extend the existing X-Ray trace view with GenAI-aware formatting?
3. GitHub integration: start with read-only (show commit info alongside deployments) or bidirectional (create GitHub issues from alarms)?
4. How do we handle the application definition cold-start for customers who don't use CloudFormation or consistent tagging?
5. **Vended metrics join keys:** Correlating vended metrics with trace spans requires reliable join keys (table name, queue URL, function name). For DynamoDB and Lambda this is straightforward. For ALB → Lambda → SQS chains, the resource relationships (which ALB target group maps to which Lambda, which SQS queue feeds which consumer) exist in CloudFormation/tags but may not be reliably available at query time. Do we need a resource relationship graph, or can we rely on trace-derived topology?
6. **Alarm enrichment:** If we classify issues as dependency/infrastructure/code, should this classification enrich CloudWatch Alarms to enable smarter routing (infrastructure issue → page platform team, code issue → page service owner)? This is high-value but touches the alarm pipeline.

---

## Appendix A: Research

See `apm-vision-research.md` for detailed competitive intelligence, AI observability landscape analysis, OTel GenAI semantic conventions reference, and database observability research.

## Appendix B: Ideas Considered and Dropped

| Idea | Why Dropped |
|---|---|
| **Build a full Software Catalog (Backstage/Datadog equivalent)** | Too large a scope. Requires customers to adopt a new metadata schema, build integrations with repos/runbooks/contacts. We can get 80% of the value by using existing AWS resource metadata (tags, CloudFormation, AppRegistry) as a lightweight catalog. Revisit if customer demand materializes. |
| **ML-based automated regression detection (Watchdog equivalent)** | Requires significant ML investment, training data, and tuning to avoid false positives. A visual before/after comparison tool delivers immediate value with zero ML risk. We build the data pipeline now (deployment ↔ metrics correlation) and can layer ML on top later. |
| **Causal AI root cause engine (Davis AI equivalent)** | Multi-year investment to build a causal dependency model with predictive capabilities. Dynatrace has invested a decade in this. Deterministic rule-based correlation (check dependencies → check infra → check deployments) covers the 80% case and ships in weeks, not years. |
| **LLM evaluation and quality scoring platform** | This is LangSmith/Langfuse/Arize territory — prompt management, evaluation datasets, groundedness scoring, hallucination detection. It's a different product category (AI engineering tooling) not an APM feature. We focus on operational observability: is the agent fast, cheap, and not violating guardrails? |
| **Generic business workflow orchestration engine** | Building a workflow definition and execution engine is out of scope. Step Functions already does this. For non-Step-Functions workflows, a lightweight config (ordered list of services/APIs) is sufficient for observability purposes. We render workflows, we don't run them. |
| **Full GitHub bidirectional integration** | Creating GitHub issues from CloudWatch alarms, syncing status back, managing PR workflows — this is a deep integration that touches authentication, permissions, and multiple GitHub APIs. Start with read-only: show commit info and PR links alongside deployment markers. Bidirectional can follow based on adoption. |
| **Custom entity types for libraries, pipelines, AI agents** | Datadog's Software Catalog supports custom entity types (libraries, pipelines, data jobs as first-class entities with scorecards). Valuable but requires building an entity model, governance framework, and scorecard engine. Out of scope for the initial push. Application-level grouping of services is the higher-priority problem. |
| **Automated span-level regression attribution** | "This specific span caused the latency regression" requires statistical analysis across thousands of traces, baseline modeling per span, and careful handling of variance. We provide the comparison tool (show span-level p50/p95/p99 deltas between two time windows) and let the customer identify the culprit. Automation is a fast-follow. |
| **Multi-agent workflow visualization** | Complex multi-agent systems (Agent A delegates to Agent B which calls Agent C) create deeply nested trace trees. Purpose-built visualization for this is valuable but niche. We start with single-agent trace rendering (reasoning chain + tool calls) which covers the majority of current Bedrock Agent and LangChain workloads. Multi-agent follows as adoption grows. |
| **Prompt/response content capture and analysis** | Capturing full LLM prompts and responses in traces is supported by OTel GenAI conventions (opt-in, PII-sensitive). Storing and analyzing this content raises significant data privacy, cost, and compliance concerns. We capture metadata (token counts, latency, model, tool calls) but not content. Content capture can be an opt-in feature with appropriate guardrails later. |
| **Multi-model routing observability** | Production AI systems route between models (Claude for complex, Haiku for simple, fallback on throttling). Observing which model handled which traffic and why requires understanding the customer's routing logic, which varies widely. We capture `gen_ai.request.model` and `gen_ai.response.model` per span — customers can filter/group by model. Purpose-built routing dashboards are a follow-on. |
| **MCP server inventory and fleet management** | At scale, AI-native companies run 50+ MCP servers and need a fleet view (which servers exist, which agents use them, health across all servers). This is a catalog/discovery problem similar to the Software Catalog we deferred. We start with passive MCP metrics from traces; an active MCP fleet dashboard follows as adoption grows. |
