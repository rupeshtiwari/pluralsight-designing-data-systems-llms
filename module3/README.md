# Module 3 — Clip 4: Demo: Triggering and monitoring an Airflow enrichment pipeline with FastAPI and DuckDB

## Overview
This demo triggers the NorthWind Airflow DAG from a new source batch and shows the complete pipeline lifecycle: queued, running, success, and branch states. It demonstrates both static transform tasks and dynamic validation branching, then verifies accepted records in the trusted output and failed records in quarantine.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 3a | Compare and contrast static DAGs with dynamic orchestration and demonstrate how to choose appropriate approaches |
| 3b | Demonstrate the steps required to integrate LLM logic into various orchestration tools |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step |
|-------------|------|
| Airflow UI shows northwind_llm_enrichment DAG run in success state | Step 1 |
| Airflow graph view shows static transform tasks and dynamic branch task topology | Step 2 |
| Task log shows batch_id, FastAPI request_id, validation result, and output row_id | Step 3 |
| DuckDB CLI shows accepted rows in trusted.feedback_enriched and quarantined rows in quarantine.llm_outputs | Step 4 |

## Pre-recording setup
1. Run `module3/scripts/demo_up.sh` off-camera (starts Docker Compose stack with Airflow, FastAPI, PostgreSQL)
2. Verify Airflow UI is accessible at http://localhost:8080
3. Verify FastAPI is healthy: `curl -s http://localhost:8000/health`
4. Verify both DAGs are visible in Airflow UI (northwind_llm_enrichment and northwind_static_reconciliation)
5. Load the batch payload: ensure data/payloads/batch_feedback.json is current
6. Terminal zoom set for mobile readability

## Demo steps

### Step 1: Trigger the Airflow DAG and show pipeline execution (LO 3b, 3c)
**Goal**: Start the enrichment pipeline and show Airflow tracking its execution state

```bash
curl -s -X POST http://localhost:8000/pipeline/trigger -H "Content-Type: application/json" -d '{"batch_id": "BATCH-20240318-001", "source": "data/payloads/batch_feedback.json"}' | python3 scripts/fmt.py --type raw
```

**Expected output**: Pipeline trigger confirmation showing batch_id, dag_id=northwind_llm_enrichment, status=triggered

**Narration note**: Explain that the trigger initiates the full DAG run. Show the Airflow UI with the DAG transitioning through states.

### Step 2: Show the DAG graph with static and dynamic branches (LO 3a)
**Goal**: Visualize both the deterministic task path and the dynamic validation branch

Open Airflow UI graph view at http://localhost:8080 (show in browser or screenshot).

Show both DAGs side by side:
- northwind_static_reconciliation: linear task chain (no LLM, no branching)
- northwind_llm_enrichment: includes branch after validation (write_trusted vs write_quarantine)

```bash
curl -s http://localhost:8000/pipeline/runs | python3 scripts/fmt.py --type raw
```

**Expected output**: Pipeline run record showing batch_id, accepted_count, rejected_count, and validation_summary

**Narration note**: Contrast the static reconciliation DAG (all deterministic) with the enrichment DAG (has a dynamic branch after LLM validation). The branching is bounded — only two paths, not open-ended.

### Step 3: Examine task logs for traceability (LO 3b, 3c)
**Goal**: Prove that task logs capture the full chain: batch_id to request_id to validation result to output row

```bash
curl -s "http://localhost:8000/pipeline/run/BATCH-20240318-001" | python3 scripts/fmt.py --type batch
```

**Expected output**: Batch result showing:
- batch_id: BATCH-20240318-001
- total: 5 (number of feedback items in batch)
- accepted: 3 (passed all validation)
- rejected: 2 (failed validation)
- details: list with each item's request_id, category, validation_status, and errors if any

**Narration note**: Read the accepted and rejected counts. Point out the request_ids that link each item back to its enrichment call.

### Step 4: Verify trusted output and quarantine tables in DuckDB (LO 3c, 3d)
**Goal**: Prove accepted records reached trusted tables and rejected records went to quarantine with reasons

```bash
duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5"
```

```bash
duckdb data/northwind.duckdb "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5"
```

**Expected output**: 
- Trusted table: 3 rows with validation_status=accepted, categories assigned, confidence above threshold
- Quarantine table: 2 rows with specific validation_errors (e.g., "unknown product_id P-9999", "confidence 0.45 below threshold 0.75")

**Narration note**: Read the validation_errors from quarantine. Explain that rejected records are a successful pipeline outcome — the system caught bad data.

## Callout
Monitor dispositions, not just task success

## Pre-recording validation

Before recording, run the validation script to generate a plain-text log with the exact input and output for every step above:

```bash
scripts/validate_module3.sh
```

This writes `logs/module3_validation.txt` with each command, full payload, raw JSON response, expected output, and a checklist. Paste the log into GPT with:

> Review this validation log. For each VALIDATION CHECKLIST, mark items PASS or FAIL based on the ACTUAL OUTPUT. Give a GO / NO-GO verdict.

Do not record until all checklist items pass.

## Cleanup
Run `module3/scripts/demo_down.sh` after recording (stops Docker Compose stack)

## Key files
- `airflow/dags/northwind_llm_enrichment.py` - Main LLM enrichment DAG
- `airflow/dags/northwind_static_reconciliation.py` - Static comparison DAG
- `app/routers/pipeline.py` - Pipeline batch endpoints
- `data/payloads/batch_feedback.json` - Batch demo payload
