# Module 2 — Clip 4: Demo: LangGraph agent triage with PostgreSQL and API tools

## Overview
This demo runs a LangGraph workflow for a failed NorthWind finance data quality check. It shows the agent stepping through inspect_metadata, retrieve_runbook, classify_severity, and recommend_action nodes, then stopping at an approval gate. Every tool call is recorded in PostgreSQL and the final decision requires human review.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 2a | Design multi-step decision pipelines so learners can automate complex, but common processes |
| 2b | Integrate tools (databases, APIs, pipelines) to enable LLM actions |

## What this demo proves

| Proof point | Step |
|-------------|------|
| Mermaid state diagram shows the workflow graph with active node progression | Step 1 |
| Agent state JSON shows incident_id, selected edge, evidence summary, and decision reason | Step 2 |
| PostgreSQL agent_tool_calls table shows tool name, input hash, output status, and timestamp | Step 3 |
| PostgreSQL agent_decisions table shows review_required instead of automatic production write | Step 4 |

## Pre-recording setup
1. Run `module2/scripts/demo_up.sh` off-camera
2. Verify server healthy: `curl -s http://localhost:8000/health`
3. Verify PostgreSQL tables exist (agent_tool_calls, agent_decisions)
4. Terminal zoom set for mobile readability

## Demo steps

### Step 1: Show the LangGraph state diagram (LO 2a)
**Goal**: Visualize the agent workflow graph before executing it

```bash
curl -s http://localhost:8000/agent/graph | python3 scripts/fmt.py --type raw
```

**Expected output**: Mermaid-compatible state diagram text showing nodes: inspect_metadata, retrieve_runbook, classify_severity, recommend_action, approval_gate. Edges show conditional transitions.

**Narration note**: Walk through each node and explain the purpose. Highlight that every transition is explicit, not hidden.

### Step 2: Run the triage workflow for a data quality incident (LO 2a, 2b)
**Goal**: Execute the full agent workflow and show structured state at each step

```bash
curl -s http://localhost:8000/agent/triage -H "Content-Type: application/json" -d @data/payloads/anomaly_triage.json | python3 scripts/fmt.py --type triage
```

**Expected output**: Formatted agent response showing:
- incident_id: INC-3001
- severity: high (40 percent deviation exceeds 10 percent threshold)
- root_cause_hypothesis: source system returned fewer records despite healthy API status
- recommended_action: pause downstream pipeline and investigate source extraction
- evidence_summary: references the data quality runbook DOC-005
- review_required: true

**Narration note**: Read the severity, the root cause hypothesis, and the recommended action. Explain that review_required=true means this does not auto-execute.

### Step 3: Verify tool calls recorded in PostgreSQL (LO 2b)
**Goal**: Prove every tool invocation is traceable in the metadata store

```bash
docker exec northwind-postgres psql -U northwind -c "SELECT tool_name, output_status, created_at FROM agent_tool_calls WHERE incident_id='INC-3001' ORDER BY created_at"
```

**Expected output**: Table showing 4 tool calls in order:
1. inspect_metadata - success
2. retrieve_runbook - success
3. classify_severity - success
4. recommend_action - success

**Narration note**: Point out the chronological order matches the state diagram. Every tool call has a status and timestamp.

### Step 4: Verify the approval gate decision in PostgreSQL (LO 2a, 2b)
**Goal**: Prove the agent stopped at the approval gate instead of auto-executing

```bash
docker exec northwind-postgres psql -U northwind -c "SELECT incident_id, severity, recommended_action, review_required FROM agent_decisions WHERE incident_id='INC-3001'"
```

**Expected output**: Single row showing incident_id=INC-3001, severity=high, recommended_action describing pipeline pause, review_required=true

**Narration note**: Emphasize that review_required=true is the approval gate. The agent recommends but does not act on production systems.

## Callout
Approval gates protect trusted systems from autonomous agent actions

## Cleanup
Run `module2/scripts/demo_down.sh` after recording

## Key files
- `app/routers/agent.py` - Agent triage endpoint
- `app/services/llm_stub.py` - Deterministic LLM responses
- `app/db/postgres_client.py` - PostgreSQL tool call and decision storage
- `data/payloads/anomaly_triage.json` - Demo payload
