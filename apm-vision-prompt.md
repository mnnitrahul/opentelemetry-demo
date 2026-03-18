# Prompt: APM Vision Doc Generator

Use this prompt to generate a pragmatic, Amazon-style vision document for a new product area. Adjust the topic, pillars, and persona details as needed.

---

## Master Prompt

You are a senior software engineer tasked with writing a pragmatic vision document. Execute the following phases sequentially, showing your work at each checkpoint so I can steer.

### Phase 1: Research (with checkpoints)

**Step 1a: Industry Research**
Search the web and compile a structured research summary covering:
- Top 3-5 competitors in this space and their most advanced, differentiating features. Be specific — cite feature names and how they work, not generic descriptions.
- Open standards and specifications relevant to this space (e.g., OpenTelemetry, OWASP, W3C). What's the current status (stable, development, draft)?
- Emerging startups and open-source projects solving adjacent problems.
- Key industry gaps that no one has solved well yet.

**Step 1b: AI/Emerging Tech Research (if applicable)**
Deep-dive into how AI/ML/agents/new paradigms intersect with this space:
- What new instrumentation libraries, standards, and protocols exist?
- What dedicated providers have emerged? Compare them (features, OTel support, scale).
- What are the unique challenges vs traditional approaches?
- What does the trace/telemetry anatomy look like for these new workloads?

**Step 1c: Our Current State Assessment**
Honestly assess our current capabilities:
- What assets do we already have?
- What are our unique structural advantages that competitors cannot replicate?
- What are the specific gaps vs competitors? Use a comparison table.
- What existing features can we connect/extend vs what requires net-new building?

**Step 1d: Synthesize into Pillars**
Distill the research into recommended vision pillars. For each pillar, note:
- What it is (one sentence)
- What existing capability it builds on
- What the key gap is
- What competitor inspired it (if any)

**CHECKPOINT: Present the research summary. Wait for my feedback before proceeding.**

### Phase 2: Write the Vision Doc

Write a pragmatic, Amazon-style vision document (~2 pages). Follow these constraints:

**Tone & Framing:**
- Pragmatic, not revolutionary. Connect existing pieces, fill specific gaps.
- Every initiative must build on something that already exists.
- For each initiative, explicitly state "What we are NOT building" to show scope discipline.
- Use the framing: "Connect, Correlate, Extend" — connect siloed experiences, correlate signals automatically, extend to new workload types.

**Required Sections:**
1. **Problem Statement** — What's broken today? Be specific about the customer's current workflow and where it fails. Name competitors who have solved this.
2. **Approach** — 2-3 sentence strategy summary.
3. **Primary Customer** — Who is the primary persona? Secondary? Design for the primary first.
4. **Priority Order** — Stack-rank all initiatives by customer impact and implementation feasibility. Use P0/P1/P2/P3.
5. **What We Will Do** — One subsection per initiative. Each has: what changes, what we are NOT building.
6. **Tenets** — 4-5 design principles. Make them opinionated and actionable, not generic.
7. **Customer Scenarios** — 3-5 concrete end-to-end scenarios showing the experience. Include a "partial adoption" note acknowledging graceful degradation.
8. **Success Metrics** — How do we know this worked? Measurable outcomes.
9. **What We Are NOT Doing** — Explicit non-goals.
10. **Open Questions** — Honest unknowns that need resolution.
11. **Appendix: Ideas Considered and Dropped** — Table with idea + specific reason for dropping. This shows you thought broadly but scoped deliberately.

**CHECKPOINT: Present the draft. Wait for my feedback before proceeding.**

### Phase 3: Critical Reviews (run sequentially)

**Review 1: Director of Engineering**
Review the doc as a Director. Focus on:
- Is there a clear primary customer?
- Is there prioritization/sequencing?
- Are the underspecified sections called out?
- Are there success metrics?
- Does it work for customers who only partially adopt?
- Are there missing customer segments (e.g., customers not using our native tools)?

**Review 2: Domain Expert**
Review as a deep technical expert in this space. Focus on:
- Data completeness: do we have the data density to support these features?
- Join key problems: when we say "correlate X with Y," is the join actually feasible?
- False positive risks in any automated classification/detection.
- UX challenges that sound simple but are actually hard.
- Missing signals that practitioners actually need but the doc doesn't mention.

**Review 3: Target Customer Expert**
Review as the most demanding customer persona (e.g., an AI-native company, a large enterprise SRE team). Focus on:
- Does this solve MY actual workflow?
- What's the unit of work I care about? (requests? conversations? workflows?)
- What failure modes does the doc miss?
- What cost/safety controls are missing?
- What would make me choose this over a competitor?

**After each review:** Research the gaps identified, then update the doc. Show what changed.

**CHECKPOINT: Present the updated doc with a summary of all changes.**

### Phase 4: UX Stories (optional)

Extract 5-8 critical user stories from the vision doc in the format:
- As a [persona], I want to [action], so that [outcome].
- Acceptance criteria for each.

---

## How to Customize This Prompt

Replace these placeholders with your specific context:

- **[PRODUCT AREA]**: e.g., "CloudWatch APM", "S3 Intelligent Tiering", "EKS Developer Experience"
- **[COMPETITORS]**: e.g., "Datadog, Dynatrace, New Relic, Grafana"
- **[EXISTING ASSETS]**: e.g., "Application Signals, X-Ray, Database Insights, vended metrics"
- **[NEW WORKLOAD TYPES]**: e.g., "AI agents, MCP servers, RAG pipelines"
- **[PRIMARY PERSONA]**: e.g., "SRE on-call at 2 AM", "Platform engineer", "ML engineer"
- **[CONSTRAINT]**: e.g., "pragmatic, 1-3 month execution, build on existing pieces"

---

## Example Invocation

```
You are a senior software engineer in the CloudWatch team. Write a vision doc for next-gen APM.

Topic: CloudWatch APM experience improvements
Competitors: Datadog (Watchdog, Deployment Tracking, DBM), Dynatrace (Davis AI, Grail, Smartscape), New Relic (Intelligent Workloads, Lookout)
Existing assets: Application Signals, Application Map, X-Ray, Database Insights, vended metrics from 200+ AWS services, Bedrock vended metrics
New workload types: AI agents (Bedrock Agents, LangChain), MCP servers, RAG pipelines
Primary persona: SRE troubleshooting production issues
Constraint: Pragmatic. Connect existing pieces, fill gaps. Not a platform rewrite. 1-3 month execution horizon.

Additional topics to cover:
1. Application-centric experience (application as logical group of services)
2. Deployment to performance correlation
3. Service vs dependency issue classification
4. Database slow query correlation with traces
5. AI agent and MCP observability
6. Customer workflow representation
7. Latency regression detection from traces

Run all phases with checkpoints. Save research to a local file, then write the vision doc to a separate file.
```
