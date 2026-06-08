# Module 2 — Clip 4: Demo: LangGraph agent triage with PostgreSQL and API tool boundaries (6 minutes)

## Why this matters

**The problem:** When a data quality check fails at 2 a.m., someone has to inspect the metadata, find the right runbook, judge the severity, and decide what to do. Teams want to automate that triage with an agent, but an agent that takes actions on its own can quietly trigger the wrong fix on production data. How do you let an agent reason through multiple steps without handing it the keys to the warehouse?

**What you will see:** A real LangGraph `StateGraph` that moves through explicit nodes — `inspect_metadata`, `retrieve_runbook`, `classify_severity`, `recommend_action` — and then stops at an `approval_gate`. Every tool call is captured in a Postgres receipts table, the agent state is structured JSON instead of free-form logs, and the final decision is recorded as `review_required` instead of being executed automatically. A second incident demonstrates a conditional edge: low-severity work is auto-logged and never reaches the approval gate.

**What you walk away with:** A repeatable design for multi-step decision pipelines that automate the tedious investigation work (2a) while integrating database and API tools through narrow, traceable contracts (2b). You see exactly where to put the human approval gate so the agent advises but never acts unsupervised — and you can prove it from the database.

## Overview

This demo runs a real LangGraph workflow for a failed NorthWind finance data quality check. The Mermaid state diagram is auto-generated from the compiled graph topology — it is the actual workflow, not a hand-drawn picture. Every node writes an audit row to `agent_tool_calls`, and the terminal `approval_gate` writes a decision with `status="review_required"` so the trusted finance tables stay untouched.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 2a | Design multi-step decision pipelines so learners can automate complex but common processes |
| 2b | Integrate tools (databases, APIs, pipelines) to enable LLM actions |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| Mermaid state diagram from the compiled graph highlights `inspect_metadata`, `retrieve_runbook`, `recommend_action`, `approval_gate` | Step 1 | 2a |
| Agent state JSON shows `incident_id`, `selected_edge`, evidence summary, and decision reason | Step 2 | 2a, 2b |
| PostgreSQL `agent_tool_calls` table shows `tool_name`, `input_hash`, `output_status`, and timestamp for every node | Step 3 | 2b |
| PostgreSQL `agent_decisions` table shows `review_required` instead of an automatic production write | Step 4 | 2a, 2b |
| Conditional edge routes a low-severity incident to `auto_log` (no approval gate, no trusted write) | Step 5 | 2a |

## Prerequisites

1. Server is running: `curl -s http://localhost:8000/health | python3 -m json.tool`
2. Knowledge base is seeded (8 reference documents — the agent retrieves the data-quality runbook from here)
3. Incident catalog is seeded (3 NorthWind finance incidents)

To start from a clean state:
```bash
./scripts/module2-demo-reset.sh
```

## Demo steps

### Step 1: Show the LangGraph topology (LO 2a)

**Goal**: Prove the workflow is an explicit graph compiled from code — the diagram is the source of truth, not a marketing slide.

```bash
curl -s http://localhost:8000/agent/graph | python3 scripts/fmt.py --type mermaid \
  --title "LangGraph topology (compiled, not hand-drawn)" \
  --why "The Mermaid source comes from compiled.get_graph().draw_mermaid()"
```

**Expected output**: Mermaid source emitted by `compiled.get_graph().draw_mermaid()`, plus a node list where the four narrated nodes are marked with ★:

- ★ inspect_metadata
- ★ retrieve_runbook
- ★ recommend_action
- ★ approval_gate

The output also includes `classify_severity` and `auto_log` as context (no ★ — they support Steps 2 and 5).

**Equivalent direct view** of the compiled graph from a Python shell:

```bash
python3 -c "from app.services.agent_graph import graph_topology; print(graph_topology()['mermaid'])"
```

**What the learner should notice**: Every transition is explicit. The diagram is generated from the compiled `StateGraph`, so it can never drift from the code.

### Step 2: Trigger the agent on a high-severity incident (LO 2a, 2b)

**Goal**: Run the workflow end-to-end and show the agent state as structured JSON.

```bash
curl -s http://localhost:8000/agent/triage \
  -H "Content-Type: application/json" \
  -d @data/payloads/agent_triage.json | python3 scripts/fmt.py --type triage \
  --title "Agent state — INC-2024-FIN-001 (merchant_revenue_total)" \
  --why "Structured agent state JSON, not free-form scrolling logs"
```

**Expected output (all fields the outline names are ★-highlighted)**:

- ★ incident_id: `INC-2024-FIN-001`
- ★ severity: `high` (30% deviation > 20% threshold)
- ★ selected_edge: `recommend_action`
- ★ recommended_action: pause downstream pipeline and investigate source extraction
- ★ evidence_summary: references data quality runbook DOC-005
- ★ decision_reason: source system returned fewer records despite healthy API status
- ★ review_required: true
- ★ path: `inspect_metadata → retrieve_runbook → classify_severity → recommend_action → approval_gate`

**What the learner should notice**: The state is one compact JSON object with the exact fields the rest of the team needs. The path line shows which nodes ran. `review_required=true` is the workflow stopping at the approval gate.

### Step 3: Show the agent_tool_calls table in Postgres (LO 2b)

**Goal**: Prove every tool call is auditable in real Postgres.

```bash
curl -s "http://localhost:8000/admin/agent-tool-calls?incident_id=INC-2024-FIN-001" | \
  python3 scripts/fmt.py --type tool-calls \
  --title "agent_tool_calls receipts (PostgreSQL)" \
  --why "Every node call: tool_name, input_hash, output_status, timestamp"
```

**Expected output**: A 5-row table where every row is starred and carries the four narrated fields:

- ★ tool_name (inspect_metadata, retrieve_runbook, classify_severity, recommend_action, approval_gate)
- ★ input_hash (sha256, first 12 chars shown)
- ★ output_status (success / error)
- ★ timestamp (created_at, ISO-8601)

**Direct psql proof** (when the Postgres container is up — works in a second terminal):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT tool_name, left(input_hash, 12) AS input_hash, output_status, created_at \
   FROM agent_tool_calls \
   WHERE incident_id = 'INC-2024-FIN-001' \
   ORDER BY created_at;"
```

**What the learner should notice**: Each node in the LangGraph topology produced exactly one row. The input hash makes identical inputs detectable; the timestamps prove ordering.

### Step 4: Show the agent_decisions table — `review_required` (LO 2a, 2b)

**Goal**: Prove the agent stopped at the approval gate instead of auto-writing to a trusted table.

```bash
curl -s "http://localhost:8000/admin/agent-decisions?limit=1" | \
  python3 scripts/fmt.py --type agent-decisions \
  --title "agent_decisions (latest)" \
  --why "Approval gate writes review_required — no automatic production write"
```

**Expected output**:

- ★ incident_id: `INC-2024-FIN-001`
- ★ status: `review_required`
- ★ severity: `high`
- ★ selected_edge: `recommend_action`
- ★ recommended_action: pause downstream pipeline and investigate source extraction
- ★ decision_reason: source extraction filter or upstream schema change suspected
- ★ review_required: true

**Direct psql proof** (when the Postgres container is up):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT incident_id, status, severity, selected_edge \
   FROM agent_decisions ORDER BY created_at DESC LIMIT 1;"
```

**What the learner should notice**: The decision row carries `status=review_required` and `selected_edge=recommend_action`. The trusted finance tables (`merchant_transactions`, `refunds`) are unchanged — the agent recommends, a human approves.

### Step 5: Show the conditional edge in action (LO 2a)

**Goal**: Prove the workflow really branches based on state — not every path goes to `approval_gate`.

```bash
curl -s http://localhost:8000/agent/triage \
  -H "Content-Type: application/json" \
  -d @data/payloads/agent_triage_low.json | python3 scripts/fmt.py --type triage \
  --title "Agent state — INC-2024-FIN-003 (low-severity branch)" \
  --why "Conditional edge: low severity ⇒ auto_log, not approval_gate"
```

**Expected output**:

- ★ incident_id: `INC-2024-FIN-003`
- ★ severity: `low` (5% deviation < 20% threshold)
- ★ selected_edge: `auto_log`
- ★ review_required: false
- ★ path: `inspect_metadata → retrieve_runbook → classify_severity → auto_log`

**What the learner should notice**: The same compiled graph routed this incident to `auto_log` because the conditional edge on `classify_severity` chose the low-severity branch. No approval row is required because there is no proposed action on the trusted tables.

## Best-practice callout

**Approval gates protect trusted systems.**

Agents propose; humans approve. Every tool call is recorded in `agent_tool_calls`, every decision lands in `agent_decisions` with an explicit status, and the conditional edge keeps low-severity work from ever reaching the gate. The trusted finance tables are off-limits to the agent by design.

## Preflight check

Before running the demo, execute the preflight script to verify all steps produce correct output:

```bash
module2/scripts/preflight_check.sh
```

This runs every demo step, captures commands and output, maps each step to its learning objective, and saves the log to `module2/preflight_log.txt`. It also reports the storage backend (`postgres` when Docker is up, `memory` otherwise).

## Cleanup

```bash
./scripts/module2-demo-reset.sh
```

## Key files

- `app/services/agent_graph.py` — Real compiled `StateGraph` (topology source of truth)
- `app/routers/agent.py` — `/agent/triage`, `/agent/graph`, `/agent/state/{id}`, `/agent/decisions`
- `app/db/postgres.py` — Real-PG-with-memory-fallback for `agent_tool_calls` and `agent_decisions`
- `app/services/llm.py` — Deterministic severity + action stub
- `data/payloads/agent_triage.json` — High-severity demo payload (INC-2024-FIN-001)
- `data/payloads/agent_triage_low.json` — Low-severity demo payload (INC-2024-FIN-003)
- `data/seed/incidents.json` — 3 NorthWind finance incident records
- `scripts/fmt.py` — `--type triage`, `--type mermaid`, `--type tool-calls`, `--type agent-decisions`
