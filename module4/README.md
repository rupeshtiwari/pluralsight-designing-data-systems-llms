# Module 4 — Clip 4: Rejecting hallucinated and schema-drifted LLM outputs in Airflow

## Overview

This demo runs a NorthWind batch containing ambiguous feedback, stale reference context, and invalid category values through the validation pipeline. It proves that validation checks catch hallucinated categories, missing source references, and low-confidence outputs, routing them to quarantine while accepting valid records into trusted tables.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1d | Demonstrate designing data flows that incorporate LLM outputs |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| Batch processing returns accepted + rejected counts that sum to total | Step 1 | 3c, 3d |
| Validation shows PASS/FAIL for each check with is_valid=false for bad data | Step 2 | 3d |
| Pipeline runs table shows accepted_count, rejected_count, and validation summary | Step 3 | 3c |
| DuckDB trusted table has accepted rows; quarantine has rejected rows with reasons | Step 4 | 1d, 3d |

## Prerequisites

1. Server is running: `curl -s http://localhost:8000/health`
2. DuckDB has seed data loaded
3. Knowledge base is seeded

## Demo steps

### Step 1: Run the validation batch through the pipeline (LO 3c, 3d)

**Goal**: Process a batch with intentionally bad data and show the pipeline correctly branches

```bash
curl -s -X POST http://localhost:8000/pipeline/batch-enrich \
  -H "Content-Type: application/json" \
  -d "{\"items\": $(cat data/payloads/batch_feedback.json)}" | python3 -m json.tool
```

**Expected output**: Batch result showing total=5, accepted=3, rejected=2. Each rejected item shows specific validation_errors.

**What the learner should notice**: The validation layer caught bad data. Some items passed all checks, others failed and went to quarantine.

### Step 2: Examine individual validation failures (LO 3d)

**Goal**: Show the specific validation checks that caught each bad output

```bash
curl -s -X POST http://localhost:8000/validate/output \
  -H "Content-Type: application/json" \
  -d '{"output": {"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}}' | python3 -m json.tool
```

**Expected output**: Validation result showing is_valid=false, category check FAIL (electronics_repair not in allowed list), confidence check PASS, grounding check PASS.

**What the learner should notice**: One FAIL is enough to reject. The system validates structure, grounding, confidence, and category independently.

### Step 3: Verify pipeline run summary (LO 3c)

**Goal**: Show operational monitoring data — accepted, rejected, and validation summary

```bash
curl -s http://localhost:8000/pipeline/runs | python3 -m json.tool
```

**Expected output**: Pipeline run records showing accepted_count and rejected_count for the batch from Step 1.

**What the learner should notice**: Monitoring should report accepted, rejected, and quarantined records — not just task success.

### Step 4: Verify trusted output and quarantine (LO 1d, 3d)

**Goal**: Prove the data flow end state — good data in trusted, bad data in quarantine with reasons

```bash
curl -s http://localhost:8000/admin/metrics | python3 -m json.tool
```

**Expected output**: trusted_enriched shows accepted rows; quarantine_outputs shows rejected rows.

**What the learner should notice**: Rejecting bad output is a successful pipeline outcome. The system protects trusted tables from unvalidated LLM proposals.

## Key takeaway

Rejecting bad output is a successful pipeline outcome.

## Preflight check

```bash
module4/scripts/preflight_check.sh
```

Runs every demo step, captures output, and saves the log to `module4/preflight_log.txt` with LO coverage mapping.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/validators/output_validator.py` — All validation logic
- `app/routers/validation.py` — Validation endpoints
- `app/routers/pipeline.py` — Batch processing and routing
- `data/payloads/batch_validation_test.json` — Test payload with intentional failures
