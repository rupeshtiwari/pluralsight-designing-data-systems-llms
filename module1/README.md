# Module 1 — Clip 4: Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector

## Overview
This demo runs the NorthWind feedback enrichment flow from DuckDB source records through FastAPI LLM enrichment to the trusted output table. It proves that LLM outputs enter trusted tables only after schema, grounding, confidence, and source ID validation passes.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1a | Demonstrate identifying where LLMs fit within data pipelines so learners can extend existing systems effectively |
| 1b | Define system boundaries so learners can separate deterministic and AI-driven components |
| 1d | Demonstrate designing data flows that incorporate LLM outputs |

## What this demo proves

| Proof point | Step |
|-------------|------|
| DuckDB raw.feedback has input records ready for enrichment | Step 1 |
| FastAPI returns structured enrichment with request_id, category, summary, confidence, and source_doc_ids | Step 2 |
| PostgreSQL llm_decisions table records the validation outcome | Step 3 |
| DuckDB trusted.feedback_enriched row count increases after validated enrichment | Step 4 |

## Pre-recording setup
1. Run `module1/scripts/demo_up.sh` off-camera
2. Verify server is healthy: `curl -s http://localhost:8000/health | python3 -m json.tool`
3. Verify DuckDB has seed data loaded
4. Verify PostgreSQL has reference docs seeded
5. Terminal zoom set for mobile readability

## Demo steps

### Step 1: Show DuckDB raw feedback input (LO 1a)
**Goal**: Prove source data exists in the deterministic pipeline layer before any LLM processing

```bash
duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback"
```

**Expected output**: Row count showing the batch of feedback records ready for enrichment (10 rows from seed data)

**Narration note**: Reference the row count value on screen

### Step 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)
**Goal**: Show the LLM enrichment boundary — deterministic input goes in, structured validated output comes back

```bash
curl -s http://localhost:8000/enrich/feedback -H "Content-Type: application/json" -d @data/payloads/feedback_enrich.json | python3 scripts/fmt.py --type feedback
```

**Expected output**: Formatted response showing:
- request_id (UUID)
- category: product_quality
- summary: one-sentence summary of the defective blender feedback
- confidence: value above 0.75 threshold
- source_doc_ids: ["DOC-001", "DOC-007"] (product quality and feedback classification docs)
- validation_status: accepted

**Narration note**: Read the category, confidence value, and source doc IDs from screen. Explain that the JSON contract from Clip 2 is what we see emitted here.

### Step 3: Verify the decision was recorded in PostgreSQL (LO 1b, 1d)
**Goal**: Prove the LLM decision entered the metadata store with full traceability

```bash
curl -s http://localhost:8000/agent/decisions | python3 scripts/fmt.py --type audit
```

Or use direct psql if preferred:
```bash
docker exec northwind-postgres psql -U northwind -c "SELECT request_id, endpoint, category, confidence, validation_status, decision FROM llm_decisions ORDER BY created_at DESC LIMIT 3"
```

**Expected output**: Table showing the request_id from Step 2, endpoint=/enrich/feedback, validation_status=accepted

**Narration note**: Point out the request_id matches Step 2, proving traceability from enrichment call to decision record

### Step 4: Verify trusted output table received the enriched record (LO 1d)
**Goal**: Prove that validated LLM output reached the trusted analytical table

```bash
duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM trusted.feedback_enriched"
```

Then show the enriched record:
```bash
duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3"
```

**Expected output**: Row count delta showing new records in trusted table, plus the enriched record details matching Step 2

**Narration note**: Reference the row count increase and the matching request_id

## Callout
LLM outputs are proposals until validation promotes them to trusted data

## Pre-recording validation

Before recording, run the validation script to generate a plain-text log with the exact input and output for every step above:

```bash
scripts/validate_module1.sh
```

This writes `logs/module1_validation.txt` with each command, full payload, raw JSON response, expected output, and a checklist. Paste the log into GPT with:

> Review this validation log. For each VALIDATION CHECKLIST, mark items PASS or FAIL based on the ACTUAL OUTPUT. Give a GO / NO-GO verdict.

Do not record until all checklist items pass.

## Cleanup
Run `module1/scripts/demo_down.sh` after recording
