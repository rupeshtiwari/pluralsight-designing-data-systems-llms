# Designing Data Systems with LLMs

Pluralsight course demo project for **Designing Data Systems with LLMs** by Rupesh Tiwari.

## Course overview

NorthWind Markets operates a multi-vendor marketplace. The data team owns daily pipelines that land operational data into DuckDB warehouse tables, store reference documents and decision traces in PostgreSQL with pgvector, and expose LLM-assisted enrichment through a FastAPI service. Every module advances the same NorthWind system through four production asks: feedback classification, dispute summarization, anomaly triage, and catalog metadata enrichment.

**Duration**: 60 minutes (4 modules, 15 minutes each)

## Technical stack

| Component | Purpose |
|-----------|---------|
| FastAPI | LLM enrichment service with deterministic stub |
| DuckDB | Warehouse tables (raw, trusted, quarantine schemas) |
| PostgreSQL + pgvector | Metadata store, decision traces, reference doc embeddings |
| Apache Airflow | Batch orchestration with static and dynamic DAGs |
| LangGraph | Bounded agentic workflows with approval gates |
| Docker Compose | Full environment (PostgreSQL, FastAPI, Airflow) |
| Python 3.12 | All application and script code |

## Project structure

```
repo-root/
  README.md                    # This file
  setup-macos.sh               # One-click Mac setup
  docker-compose.yml           # Full Docker environment
  Dockerfile                   # FastAPI service image
  requirements.txt             # Python dependencies
  .env.example                 # Environment variable template
  app/                         # FastAPI application
    main.py                    # App entry point with health and admin endpoints
    config.py                  # Configuration constants
    routers/
      enrichment.py            # /enrich/feedback, /enrich/dispute, /enrich/catalog
      agent.py                 # /agent/triage, /agent/state, /agent/decisions
      pipeline.py              # /pipeline/batch-enrich, /pipeline/runs, /pipeline/trigger
      validation.py            # /validate/output, /validate/rules, /validate/batch-report
    services/
      llm_stub.py              # Deterministic LLM (no GPU, no API key)
      llm.py                   # Async LLM wrapper
      retrieval.py             # pgvector RAG retrieval
    db/
      duckdb_client.py         # DuckDB warehouse client
      postgres_client.py       # PostgreSQL metadata client
      postgres.py              # Async PostgreSQL operations
      pgvector.py              # pgvector similarity search
    models/
      schemas.py               # Pydantic request/response models
    validators/
      output_validator.py      # Schema, grounding, confidence, category, integrity checks
  scripts/
    fmt.py                     # Pluralsight-branded color formatter for demo output
    demo_module1.py            # Automated demo runner for module 1
    demo_module2.py            # Automated demo runner for module 2
    demo_module3.py            # Automated demo runner for module 3
    demo_module4.py            # Automated demo runner for module 4
    validate_module1.sh        # Pre-recording validation log for GPT review
    validate_module2.sh        # Pre-recording validation log for GPT review
    validate_module3.sh        # Pre-recording validation log for GPT review
    validate_module4.sh        # Pre-recording validation log for GPT review
  data/
    payloads/                  # Demo curl payloads (source of truth)
    seed/                      # Seed data for DuckDB and PostgreSQL
    reference_docs/            # Reference documents for pgvector
  airflow/dags/
    northwind_llm_enrichment.py      # Dynamic LLM enrichment DAG
    northwind_static_reconciliation.py # Static comparison DAG
  module1/                     # Designing LLM boundaries in data pipelines
    README.md                  # Recording runbook for clip 4 demo
    scripts/
      demo_up.sh               # Start tmux session + server
      demo_down.sh             # Teardown
      capture_demo_output.sh   # Capture output for review
      preflight_check.sh       # Pre-recording health checks
  module2/                     # Architecting agentic data workflows with LangGraph
    README.md                  # Recording runbook for clip 4 demo
    scripts/                   # Same pattern as module 1
  module3/                     # Orchestrating LLM data pipelines with Apache Airflow
    README.md                  # Recording runbook for clip 4 demo
    scripts/                   # Same pattern (uses Docker Compose)
  module4/                     # Validating and guardrailing LLM outputs
    README.md                  # Recording runbook for clip 4 demo
    scripts/                   # Same pattern (uses Docker Compose)
  docs/                        # Compliance artifacts, model cards
```

## Modules

| Module | Title | Duration | Demo clip |
|--------|-------|----------|-----------|
| 1 | Designing LLM boundaries in data pipelines | 15 min | Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector |
| 2 | Architecting agentic data workflows with LangGraph | 15 min | LangGraph agent triage with PostgreSQL and API tools |
| 3 | Orchestrating LLM data pipelines with Apache Airflow | 15 min | Triggering and monitoring an Airflow enrichment pipeline |
| 4 | Validating and guardrailing LLM outputs in data pipelines | 15 min | Rejecting hallucinated and schema-drifted LLM outputs |

## Quick start

### Option A: Local development (modules 1-2)

```bash
# One-time setup
./setup-macos.sh

# Start module 1 demo environment
module1/scripts/demo_up.sh

# Attach to tmux session
tmux attach -t m1-demo
```

### Option B: Full Docker environment (modules 3-4)

```bash
# Start all services
docker compose up -d

# Wait for health checks
curl -s http://localhost:8000/health | python3 -m json.tool
curl -s http://localhost:8080/health

# Start module 3 demo environment
module3/scripts/demo_up.sh
```

## Recording workflow

For each module demo clip:

1. **Preflight**: `moduleN/scripts/preflight_check.sh`
2. **Validate**: `scripts/validate_moduleN.sh` (produces plain-text log for GPT review)
3. **Capture**: `moduleN/scripts/capture_demo_output.sh` (captures formatted output)
4. **Review**: verify every narration claim matches capture output
5. **Record**: open tmux session and follow the README runbook
6. **Cleanup**: `moduleN/scripts/demo_down.sh`

## Validation scripts

Each `scripts/validate_moduleN.sh` produces a plain-text log at `logs/moduleN_validation.txt` that records:

- The exact command for each demo step
- The exact input payload content
- The raw JSON response (unformatted)
- The expected output from the recording runbook
- A comparison checklist

Hand this file to GPT or a reviewer to verify every demo step produces the expected output before recording.

## API endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | /health | Service health check |
| POST | /admin/reset-metrics | Reset counters for clean demo |
| POST | /admin/seed-knowledge-base | Seed reference docs into pgvector |
| GET | /admin/metrics | Current service metrics |
| POST | /enrich/feedback | Classify and summarize customer feedback |
| POST | /enrich/dispute | Summarize a refund dispute |
| POST | /enrich/catalog | Enrich product catalog metadata |
| POST | /agent/triage | Run LangGraph triage workflow |
| GET | /agent/state/{incident_id} | Get agent state for an incident |
| GET | /agent/decisions | List recent agent decisions |
| POST | /pipeline/batch-enrich | Process a feedback batch |
| GET | /pipeline/runs | List recent pipeline runs |
| GET | /pipeline/run/{batch_id} | Get batch run details |
| POST | /pipeline/trigger | Simulate Airflow DAG trigger |
| POST | /validate/output | Validate raw LLM output |
| GET | /validate/rules | Get validation configuration |
| POST | /validate/batch-report | Get batch validation summary |

## Learning objectives

| LO | Description | Modules |
|----|-------------|---------|
| T1 | Design LLM-powered data systems for end-to-end data architectures | 1 |
| 1a | Identify where LLMs fit within data pipelines | 1.1, 1.4 |
| 1b | Define system boundaries between deterministic and AI-driven components | 1.1, 1.2, 1.4 |
| 1c | Select appropriate architectures (prompting, RAG, agents) | 1.3, 2.1 |
| 1d | Design data flows that incorporate LLM outputs | 1.2, 1.4, 4.1, 4.4 |
| T2 | Architect agentic workflows for LLM-driven decision-making | 2 |
| 2a | Design multi-step decision pipelines | 2.1, 2.2, 2.4 |
| 2b | Integrate tools (databases, APIs, pipelines) for LLM actions | 2.1, 2.3, 2.4, 3.3 |
| T3 | Implement orchestration strategies coordinating LLMs with data infrastructure | 3, 4 |
| 3a | Compare static DAGs with dynamic orchestration | 3.2, 3.4 |
| 3b | Integrate LLM logic into orchestration tools | 3.1, 3.3, 3.4 |
| 3c | Trigger and monitor pipeline tasks | 3.1, 3.3, 3.4, 4.3, 4.4 |
| 3d | Apply guardrails and validation for safe system behavior | 2.3, 3.4, 4.1, 4.2, 4.4 |

## Color palette (Pluralsight brand)

| Color | Hex | Terminal use |
|-------|-----|-------------|
| Transform Pink | #FF1675 | Blocked, violations, FAIL |
| Lime Green | #CFFF6E | Allowed, PASS, enabled |
| Limited Green | #40FFBF | Token counts, hash values |
| Blue | #2AECFA | All field labels |
| ADA Green | #29826F | PII types, filtered actions |
| Light Gray | #BFBFBF | Secondary info |
| White (bold) | #FFFFFF | Headings only |
| Inky Blue | #130F25 | Dark backgrounds |
