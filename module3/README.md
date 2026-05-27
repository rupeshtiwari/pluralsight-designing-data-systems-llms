# Module 3 — Clip 4: Triggering and monitoring an Airflow enrichment pipeline with FastAPI and DuckDB

## Overview

This demo triggers the NorthWind Airflow DAG from a new source batch and shows the complete pipeline lifecycle. It demonstrates both static transform tasks and dynamic validation branching, then verifies accepted records in the trusted output and failed records in quarantine.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 3a | Compare and contrast static DAGs with dynamic orchestration |
| 3b | Demonstrate the steps required to integrate LLM logic into orchestration tools |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| Pipeline trigger returns batch_id and status=triggered | Step 1 | 3b, 3c |
| Pipeline runs show accepted_count and rejected_count | Step 2 | 3a |
| Batch details show per-item request_id, category, validation_status, errors | Step 3 | 3b, 3c |
| DuckDB trusted table has accepted rows; quarantine has rejected rows with reasons | Step 4 | 3c, 3d |

## Prerequisites

1. Server is running: `curl -s http://localhost:8000/health`
2. DuckDB has seed data loaded
3. Knowledge base is seeded

## Demo steps

### Step 1: Trigger the pipeline and show execution (LO 3b, 3c)

**Goal**: Start the enrichment pipeline and show it tracking execution state

```bash
curl -s -X POST http://localhost:8000/pipeline/trigger \
  -H "Content-Type: application/json" \
  -d '{"batch_id": "BATCH-20240318-001", "source": "data/payloads/batch_feedback.json"}' | python3 -m json.tool
```

**Expected output**: Pipeline trigger confirmation showing batch_id, dag_id, status=triggered.

**What the learner should notice**: The trigger creates a pipeline run record with a batch_id that can be traced through all downstream steps.

### Step 2: Show pipeline run results (LO 3a)

**Goal**: Visualize the pipeline run with accepted and rejected counts

```bash
curl -s http://localhost:8000/pipeline/runs | python3 -m json.tool
```

**Expected output**: Pipeline run records showing batch_id, accepted_count, rejected_count, and status.

**What the learner should notice**: The enrichment DAG has a dynamic branch (accepted vs quarantine) unlike a static reconciliation DAG which is purely linear.

### Step 3: Examine batch details for traceability (LO 3b, 3c)

**Goal**: Prove that task logs capture the full chain from batch_id to request_id to validation result

```bash
curl -s "http://localhost:8000/pipeline/run/BATCH-20240318-001" | python3 -m json.tool
```

**Expected output**: Batch result showing total=5, accepted=3, rejected=2, with per-item details including request_id, category, validation_status, and errors.

**What the learner should notice**: Each item has a request_id linking it back to its enrichment call. Rejected items have specific error messages.

### Step 4: Verify trusted output and quarantine tables (LO 3c, 3d)

**Goal**: Prove accepted records reached trusted tables and rejected records went to quarantine with reasons

```bash
curl -s http://localhost:8000/admin/metrics | python3 -m json.tool
```

**Expected output**: trusted_enriched >= 3, quarantine_outputs >= 2.

**What the learner should notice**: Rejected records are a successful pipeline outcome — the system caught bad data. Quarantine rows explain why they were rejected.

## Key takeaway

Monitor dispositions, not just task success.

## Preflight check

```bash
module3/scripts/preflight_check.sh
```

Runs every demo step, captures output, and saves the log to `module3/preflight_log.txt` with LO coverage mapping.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `airflow/dags/northwind_llm_enrichment.py` — Main LLM enrichment DAG
- `airflow/dags/northwind_static_reconciliation.py` — Static comparison DAG
- `app/routers/pipeline.py` — Pipeline batch endpoints
- `data/payloads/batch_feedback.json` — Batch demo payload
