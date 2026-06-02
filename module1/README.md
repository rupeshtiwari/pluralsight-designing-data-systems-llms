# Module 1 — Clip 4: Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector (6 minutes)

## Why this matters

**The problem:** Your team wants to use an LLM to classify thousands of customer feedback records, but a wrong classification that silently lands in a trusted analytics table can mislead every dashboard and decision downstream. How do you let an LLM enrich your data without letting it corrupt your warehouse?

**What you will see:** A working boundary where raw feedback flows in, the LLM proposes a classification with a confidence score and cited sources, and the output only reaches the trusted table after it passes validation. Nothing the model says is treated as fact until it earns that status.

**What you walk away with:** A repeatable pattern for placing an LLM inside an existing pipeline (1a), drawing a clean line between deterministic and AI-driven steps (1b), and designing a data flow where every LLM output is traceable and validated before it becomes trusted data (1d). This is the foundation every later module builds on.

## Overview

This demo runs the NorthWind feedback enrichment flow from DuckDB source records through FastAPI LLM enrichment to the trusted output table. It proves that LLM outputs enter trusted tables only after schema, grounding, confidence, and source ID validation passes.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1a | Demonstrate identifying where LLMs fit within data pipelines so learners can extend existing systems effectively |
| 1b | Define system boundaries so learners can separate deterministic and AI-driven components |
| 1d | Demonstrate designing data flows that incorporate LLM outputs |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| DuckDB raw.feedback has input records ready for enrichment | Step 1 | 1a |
| pgvector reference documents (Postgres + 384-dim embeddings) ground the LLM | Step 1b | 1a, 1b |
| FastAPI returns structured enrichment with request_id, category, summary, confidence, and source_doc_ids | Step 2 | 1a, 1b |
| llm_decisions table records the same request_id and validation status (schema, grounding, confidence, source ID checks) | Step 3 | 1b, 1d |
| DuckDB trusted.feedback_enriched row count increases after validated enrichment | Step 4 | 1d |

## Prerequisites

1. Server is running: `curl -s http://localhost:8000/health | python3 -m json.tool`
2. DuckDB has seed data loaded (10 feedback records)
3. Knowledge base is seeded (8 reference documents)

To start from a clean state:
```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Show DuckDB raw feedback input (LO 1a)

**Goal**: Prove source data exists in the deterministic pipeline layer before any LLM processing

The FastAPI server holds an exclusive lock on the DuckDB file while it runs, so the row counts are read through the `/admin/metrics` endpoint that wraps the same DuckDB query.

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics \
  --title "DuckDB warehouse row counts (before enrichment)" \
  --why "Source data is ready; the trusted table is still empty"
```

**Equivalent direct DuckDB CLI query** (works only when the server is stopped, e.g. before `module1-demo-reset.sh` brings it up):

```bash
duckdb data/northwind.duckdb \
  "SELECT count(*) AS raw_feedback FROM raw.feedback;"
```

**Expected output**: `raw_feedback: 10`, `trusted_enriched: 0` (the key counts are marked with ★)

**What the learner should notice**: 10 feedback records are in the raw table. The trusted enrichment table is empty — no LLM has touched this data yet.

### Step 1b: Show the pgvector reference documents (LO 1a, 1b)

**Goal**: Prove the LLM is grounded in approved product and policy documents stored in PostgreSQL with pgvector

```bash
curl -s "http://localhost:8000/admin/reference-docs?limit=8" | python3 scripts/fmt.py --type refdocs \
  --title "pgvector reference documents" \
  --why "Approved policies the LLM is grounded against, stored in Postgres with vector(384) embeddings"
```

**Expected output**: 8 documents with doc_id (DOC-001 through DOC-008), title, doc_type, and `has_embedding: true` when Postgres is running.

**Direct psql proof** (when Postgres container is up):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT doc_id, doc_type, embedding IS NOT NULL AS has_embedding FROM reference_docs ORDER BY doc_id;"
```

**What the learner should notice**: Each reference document carries a 384-dimension vector embedding in pgvector. These are the documents the LLM cites in `source_doc_ids`.

### Step 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)

**Goal**: Show the LLM enrichment boundary — deterministic input goes in, structured validated output comes back

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json | python3 scripts/fmt.py --type feedback \
  --title "FastAPI enrichment response" \
  --why "The LLM proposal: category, confidence, and cited sources"
```

**Expected output (all 5 fields the outline names are ★-highlighted)**:
- ★ request_id: a UUID
- ★ category: product_quality
- ★ summary: describes the defective blender (cracked lid, grinding noise)
- ★ confidence: 0.8 (above the 0.75 threshold)
- ★ source_doc_ids: ["DOC-001", "DOC-002"]
- ★ validation_status: accepted

**What the learner should notice**: The service emitted the JSON contract from Clip 2. The validation_status is accepted because every check passed — Step 3 shows the per-check breakdown.

### Step 3: Verify the decision was stored in llm_decisions (LO 1b, 1d)

**Goal**: Prove the LLM decision entered the metadata store with full traceability

```bash
curl -s http://localhost:8000/admin/llm-decisions?limit=1 | python3 scripts/fmt.py --type decisions \
  --title "Decision record in llm_decisions" \
  --why "Same request_id as Step 2 proves end-to-end traceability"
```

**Expected output**: A decision record showing the same request_id from Step 2, status=accepted, and a **validation checks block** proving the four required checks passed:

- ★ schema       ✓ PASS
- ★ grounding    ✓ PASS
- ★ confidence   ✓ PASS
- ★ source ID    ✓ PASS

**Direct psql proof** (when Postgres container is up):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT request_id, endpoint, status, total_tokens FROM llm_decisions ORDER BY created_at DESC LIMIT 1;"
```

**What the learner should notice**: The request_id matches Step 2, proving end-to-end traceability from enrichment call to decision record. The row lives in real Postgres — every LLM call creates a durable, queryable record.

### Step 4: Verify trusted output table received the enriched record (LO 1d)

**Goal**: Prove that validated LLM output reached the trusted analytical table

The FastAPI server holds the DuckDB lock during the demo, so the trusted-table row count is read through the same `/admin/metrics` endpoint as Step 1. The count growing from 0 to 1 is the proof that validation promoted the LLM output.

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics \
  --title "DuckDB warehouse row counts (after enrichment)" \
  --why "The validated output was promoted to the trusted table"
```

**Equivalent direct DuckDB CLI queries** (work only when the server is stopped):

```bash
duckdb data/northwind.duckdb \
  "SELECT count(*) AS trusted_enriched FROM trusted.feedback_enriched;"

duckdb data/northwind.duckdb \
  "SELECT request_id, category, confidence, validation_status \
   FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3;"
```

**Expected output**: `raw_feedback: 10`, `trusted_enriched: 1` (the count grew from 0 to 1)

**What the learner should notice**: The trusted table grew from 0 to 1. The validated LLM output was promoted from a proposal to a trusted data product. If validation had failed, the record would have gone to quarantine instead.

## Best-practice callout

**Trusted tables need validated generated fields.**

LLM outputs are proposals until validation promotes them to trusted data.

## Preflight check

Before running the demo, execute the preflight script to verify all steps produce correct output:

```bash
module1/scripts/preflight_check.sh
```

This runs every demo step, captures commands and output, maps each step to its learning objective, and saves the log to `module1/preflight_log.txt`. Use this log to verify that demo steps align with the learning objectives.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/routers/enrichment.py` — Feedback enrichment endpoint
- `app/services/llm.py` — Deterministic LLM stub
- `app/validators/output_validator.py` — Validation logic
- `app/db/pgvector.py` — Reference document retrieval
- `data/payloads/feedback_enrich.json` — Demo payload
- `data/seed/feedback.json` — Seed data (10 records)
