# Module 2 Clip 4 — Learning Objective coverage

This document maps every demo step in `module2/README.md` to the
specific Learning Objective sub-elements the clip is approved to cover.
Used by the author and by the curriculum reviewer to verify that the
demo stays inside the approved scope.

## Approved LOs for Module 2 Clip 4

| LO | Description |
|----|-------------|
| 2a | Design multi-step decision pipelines so learners can automate complex, but common processes |
| 2b | Integrate tools (databases, APIs, pipelines) to enable LLM actions |

## Step-to-LO mapping

| Step | Title | LO | Proof emitted on screen |
|------|-------|----|-------------------------|
| 1 | Show the LangGraph topology | 2a | Mermaid source derived from `compiled.get_graph().draw_mermaid()`; the four outline-named nodes (`inspect_metadata`, `retrieve_runbook`, `recommend_action`, `approval_gate`) are starred |
| 2 | Trigger the agent on a high-severity incident | 2a, 2b | Agent state JSON with `incident_id`, `selected_edge`, `evidence_summary`, `decision_reason`, `review_required` |
| 2b | Active path on the Mermaid diagram | 2a | `GET /agent/graph?incident_id=X` appends a Mermaid `classDef active` styling the nodes that actually executed; `active_path` line is starred |
| 3 | `agent_tool_calls` receipts | 2b | Five rows showing `tool_name`, `input_hash`, `output_status`, `created_at` per node — direct `psql` proof included |
| 4 | `agent_decisions` (approval gate) | 2a, 2b | Single row with `status=review_required`; no row in any trusted finance table |
| 5 | Conditional edge to `auto_log` | 2a | Same agent fired with a 5% deviation; `selected_edge=auto_log`, `review_required=false` — proves dynamic routing |

## Tech stack used in this clip

| Component | Where it is exercised |
|-----------|-----------------------|
| FastAPI | `POST /agent/triage`, `GET /agent/graph`, `GET /admin/agent-tool-calls`, `GET /admin/agent-decisions` |
| LangGraph | Compiled `StateGraph` in `app/services/agent_graph.py` — six nodes, one conditional edge |
| PostgreSQL | `agent_tool_calls` and `agent_decisions` tables (real PG via `asyncpg`) |
| pgvector | `retrieve_runbook` node uses `pgvector.retrieve_similar_docs(doc_type="runbook")` against the `reference_docs` table seeded in Module 1 |
| DuckDB | Source warehouse stays untouched on purpose — the demo's whole point is that the approval gate keeps the agent away from trusted finance tables |

## Out-of-scope items (intentionally not in the demo)

- Open-ended agent reasoning, broad tool access, or unrestricted SQL — outline forbids these
- Cross-clip references to Module 1 (boundaries), Module 3 (orchestration), or Module 4 (validation)
- Optional or "advanced" steps — every step in the README is required

## Verifying coverage

Run the preflight; the log at `module2/preflight_log.txt` ends with the LO
coverage block. If every check passes, the demo is aligned with the
outline as approved.

```bash
module2/scripts/preflight_check.sh
```
