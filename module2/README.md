# Module 2 — Clip 4: LangGraph agent triage with PostgreSQL and API tools

## Why this matters

**The problem:** When a data quality check fails at 2 a.m., someone has to inspect the metadata, find the right runbook, judge the severity, and decide what to do. Teams want to automate that triage with an agent, but an agent that takes actions on its own can quietly trigger the wrong fix on production data. How do you let an agent reason through multiple steps without handing it the keys?

**What you will see:** A LangGraph agent that moves through explicit nodes — inspect metadata, retrieve the runbook, classify severity, recommend an action — and then stops at an approval gate. Every tool call is recorded, and the final decision is marked review_required instead of being executed automatically.

**What you walk away with:** A design for multi-step decision pipelines that automate the tedious investigation work (2a) while integrating database and API tools through narrow, traceable contracts (2b). You see exactly where to put the human approval gate so the agent advises but never acts unsupervised.

## Overview

This demo runs a LangGraph workflow for a failed NorthWind finance data quality check. It shows the agent stepping through inspect_metadata, retrieve_runbook, classify_severity, and recommend_action nodes, then stopping at an approval gate. Every tool call is recorded in PostgreSQL and the final decision requires human review.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 2a | Design multi-step decision pipelines so learners can automate complex, but common processes |
| 2b | Integrate tools (databases, APIs, pipelines) to enable LLM actions |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| State diagram shows the workflow graph with node progression | Step 1 | 2a |
| Agent state JSON shows incident_id, evidence summary, and decision reason | Step 2 | 2a, 2b |
| agent_tool_calls table shows tool name, output status, and timestamp | Step 3 | 2b |
| agent_decisions table shows review_required instead of automatic production write | Step 4 | 2a, 2b |

## Prerequisites

1. Server is running: `curl -s http://localhost:8000/health`
2. Knowledge base is seeded

## Demo steps

### Step 1: Show the LangGraph state diagram (LO 2a)

**Goal**: Visualize the agent workflow graph before executing it

```bash
curl -s http://localhost:8000/agent/graph | python3 -m json.tool
```

**Expected output**: State diagram showing nodes: inspect_metadata, retrieve_runbook, classify_severity, recommend_action, approval_gate with conditional transitions.

**What the learner should notice**: Every transition is explicit. The agent follows a defined graph, not open-ended reasoning.

### Step 2: Run the triage workflow for a data quality incident (LO 2a, 2b)

**Goal**: Execute the full agent workflow and show structured state at each step

```bash
curl -s http://localhost:8000/agent/triage \
  -H "Content-Type: application/json" \
  -d @data/payloads/anomaly_triage.json | python3 -m json.tool
```

**Expected output**:
- incident_id: INC-3001
- severity: high (40 percent deviation exceeds 10 percent threshold)
- root_cause_hypothesis: source system returned fewer records despite healthy API status
- recommended_action: pause downstream pipeline and investigate source extraction
- evidence_summary: references the data quality runbook DOC-005
- review_required: true

**What the learner should notice**: The agent classified the severity based on deviation percentage, recommended a specific action, and set review_required=true — it does not auto-execute.

### Step 3: Verify tool calls in the agent state (LO 2b)

**Goal**: Prove every tool invocation is traceable in the metadata store

```bash
curl -s http://localhost:8000/agent/state/INC-3001 | python3 -m json.tool
```

**Expected output**: Agent state showing tool calls in order: inspect_metadata, retrieve_runbook, classify_severity, recommend_action, approval_gate — each with output data.

**What the learner should notice**: The chronological order matches the state diagram. Every tool call is recorded with its input and output.

### Step 4: Verify the approval gate decision (LO 2a, 2b)

**Goal**: Prove the agent stopped at the approval gate instead of auto-executing

```bash
curl -s http://localhost:8000/agent/decisions | python3 -m json.tool
```

**Expected output**: Decision record showing incident_id=INC-3001, severity=high, recommended_action describing pipeline pause, review_required=true.

**What the learner should notice**: review_required=true is the approval gate. The agent recommends but does not act on production systems.

## Key takeaway

Approval gates protect trusted systems from autonomous agent actions.

## Preflight check

```bash
module2/scripts/preflight_check.sh
```

Runs every demo step, captures output, and saves the log to `module2/preflight_log.txt` with LO coverage mapping.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/routers/agent.py` — Agent triage endpoint
- `app/services/llm.py` — Deterministic LLM responses
- `app/db/postgres.py` — In-memory tool call and decision storage
- `data/payloads/anomaly_triage.json` — Demo payload
