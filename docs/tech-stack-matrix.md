# Tech-stack coverage matrix — Designing Data Systems with LLMs

Maps every tool listed in the outline's **Author Notes** to the module
and clip that actually exercises it. The author runs the preflight
check for each module to confirm the tool is exercised live (not just
imported), and this matrix records the resulting alignment.

## Outline-mandated tech stack (Author Notes)

| Component | Module 1 | Module 2 | Module 3 | Module 4 |
|-----------|----------|----------|----------|----------|
| FastAPI | ✅ `/enrich/feedback`, `/admin/metrics`, `/admin/reference-docs`, `/admin/llm-decisions` | ✅ `/agent/triage`, `/agent/graph`, `/admin/agent-tool-calls`, `/admin/agent-decisions` | ⏳ Planned: Airflow tasks call existing `/enrich/feedback` | ⏳ Planned: validation result endpoints |
| DuckDB | ✅ `raw.feedback`, `trusted.feedback_enriched` row counts shown | ➖ Not exercised (agent stays away from trusted tables by design — that is the proof) | ⏳ Planned: trusted vs. quarantine routing per batch | ⏳ Planned: `trusted.feedback_enriched` vs. `quarantine.llm_outputs` |
| PostgreSQL | ✅ `reference_docs`, `llm_decisions` | ✅ `agent_tool_calls`, `agent_decisions` | ⏳ Planned: `pipeline_runs` table for orchestration metadata | ⏳ Planned: validation summary table |
| pgvector | ✅ 8 reference docs with 384-dim embeddings + cosine retrieval | ✅ `retrieve_runbook` node reuses pgvector retrieval | ➖ Not directly exercised (orchestration concern) | ⏳ Planned: source-citation grounding check |
| LangGraph | ➖ Not in scope | ✅ Real compiled `StateGraph` with conditional edges + auto-generated Mermaid | ➖ Not in scope | ➖ Not in scope |
| Apache Airflow | ➖ Not in scope | ➖ Not in scope | ⏳ Planned: Docker image + `northwind_llm_enrichment` DAG | ⏳ Planned: validation branching DAG |
| Deterministic LLM stub | ✅ `classify_feedback` | ✅ `classify_severity`, `recommend_action` | ⏳ Planned: same stub invoked via FastAPI | ⏳ Planned: returns ambiguous outputs to test validators |
| Docker Compose | ✅ `pgvector/pgvector:pg16` | ✅ Same image, reused | ⏳ Planned: + Airflow services | ⏳ Planned: same stack |

Legend: ✅ exercised live in the demo, ⏳ planned in a future phase, ➖ intentionally not exercised in this module.

## Module 2 verification command

After preflight passes, run these to confirm Module 2 actually used the
real Postgres + pgvector + LangGraph stack:

```bash
# LangGraph: compiled graph emits a Mermaid topology
curl -s http://localhost:8000/agent/graph | python3 -c "import json,sys; d=json.load(sys.stdin); print('nodes:', len(d['nodes']), 'edges:', len(d['edges']))"

# PostgreSQL: real rows in agent_tool_calls and agent_decisions
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT count(*) AS tool_calls FROM agent_tool_calls;
   SELECT count(*) AS decisions FROM agent_decisions;"

# pgvector: reference_docs still queryable for runbook retrieval
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT doc_id, doc_type FROM reference_docs WHERE doc_type ILIKE '%runbook%';"
```

A working Module 2 returns: `nodes: 8`, `edges: 9`, tool_calls ≥ 5,
decisions ≥ 1, and at least one runbook reference doc.
