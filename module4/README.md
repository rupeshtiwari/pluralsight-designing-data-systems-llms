# Module 4 — Clip 4: Demo: Rejecting hallucinated and schema-drifted LLM outputs in Airflow

## Overview
This demo runs a NorthWind batch containing ambiguous feedback, stale reference context, and invalid category values through the validation pipeline. It proves that validation checks catch hallucinated categories, missing source references, and low-confidence outputs, routing them to quarantine while accepting valid records into trusted tables. Closes with the course summary.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1d | Demonstrate designing data flows that incorporate LLM outputs |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step |
|-------------|------|
| Airflow UI shows validation task success with downstream accepted and quarantine branches | Step 1 |
| FastAPI response shows one valid output and at least one invalid validation reason | Step 2 |
| PostgreSQL pipeline_runs table shows accepted count, rejected count, and validation summary | Step 3 |
| DuckDB CLI shows trusted.feedback_enriched accepted rows and quarantine.llm_outputs rejected rows with reasons | Step 4 |

## Pre-recording setup
1. Run `module4/scripts/demo_up.sh` off-camera
2. Verify all services healthy
3. Reset metrics and clear previous test data
4. Ensure data/payloads/batch_validation_test.json is current
5. Terminal zoom set for mobile readability

## Demo steps

### Step 1: Run the validation batch and show Airflow routing (LO 3c, 3d)
**Goal**: Process a batch with intentionally bad data and show the pipeline correctly branches

```bash
curl -s -X POST http://localhost:8000/pipeline/batch-enrich -H "Content-Type: application/json" -d @data/payloads/batch_validation_test.json | python3 scripts/fmt.py --type batch
```

**Expected output**: Batch result showing:
- total: 4
- accepted: 1 (the valid item)
- rejected: 3 (hallucinated category, missing sources, low confidence)
- Each rejected item shows specific validation_errors

**Narration note**: Read the total, accepted, and rejected counts. This is the proof that the validation layer works.

### Step 2: Examine individual validation failures (LO 3d)
**Goal**: Show the specific validation checks that caught each bad output

```bash
curl -s -X POST http://localhost:8000/validate/output -H "Content-Type: application/json" -d '{"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}' | python3 scripts/fmt.py --type validation
```

**Expected output**: Validation result showing:
- schema_check: FAIL (electronics_repair not in allowed categories)
- grounding_check: PASS
- confidence_check: PASS
- referential_integrity_check: PASS (if product context provided)
- is_valid: false
- errors: ["category 'electronics_repair' not in allowed values"]

**Narration note**: Read the PASS and FAIL for each check. Explain that one FAIL is enough to reject.

### Step 3: Verify pipeline run summary in PostgreSQL (LO 3c)
**Goal**: Show operational monitoring data — accepted, rejected, and validation summary

```bash
docker exec northwind-postgres psql -U northwind -c "SELECT batch_id, accepted_count, rejected_count, validation_summary FROM pipeline_runs ORDER BY created_at DESC LIMIT 3"
```

**Expected output**: Pipeline run row showing the batch from Step 1 with accepted_count=1, rejected_count=3, and validation_summary JSON with failure categories

**Narration note**: Read the accepted and rejected counts. Point out the validation_summary shows which types of failures occurred.

### Step 4: Verify trusted output and quarantine in DuckDB (LO 1d, 3d)
**Goal**: Prove the data flow end state — good data in trusted, bad data in quarantine with reasons

```bash
duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5"
```

```bash
duckdb data/northwind.duckdb "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5"
```

**Expected output**:
- Trusted: the 1 accepted record with valid category and confidence above threshold
- Quarantine: 3 rejected records with specific errors:
  - "category 'electronics_repair' not in allowed values"
  - "source_doc_ids is empty, grounding check requires at least one reference"
  - "confidence 0.45 below threshold 0.75"

**Narration note**: Read each validation error from the quarantine table. Close with: rejecting bad output is a successful pipeline outcome.

## Callout
Rejecting bad output is a successful pipeline outcome

## Pre-recording validation

Before recording, run the validation script to generate a plain-text log with the exact input and output for every step above:

```bash
scripts/validate_module4.sh
```

This writes `logs/module4_validation.txt` with each command, full payload, raw JSON response, expected output, and a checklist. Paste the log into GPT with:

> Review this validation log. For each VALIDATION CHECKLIST, mark items PASS or FAIL based on the ACTUAL OUTPUT. Give a GO / NO-GO verdict.

Do not record until all checklist items pass.

## Cleanup
Run `module4/scripts/demo_down.sh` after recording

## Key files
- `app/validators/output_validator.py` - All validation logic
- `app/routers/validation.py` - Validation endpoints
- `app/routers/pipeline.py` - Batch processing and routing
- `data/payloads/batch_validation_test.json` - Test payload with intentional failures
