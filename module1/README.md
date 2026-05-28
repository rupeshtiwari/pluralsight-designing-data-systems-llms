# Module 1 — Clip 4: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector

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
| FastAPI returns structured enrichment with request_id, category, summary, confidence, and source_doc_ids | Step 2 | 1a, 1b |
| llm_decisions table records the same request_id and validation status | Step 3 | 1b, 1d |
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

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics
```

**Expected output**: `raw_feedback: 10`, `trusted_enriched: 0` (the key counts are marked with ★)

**What the learner should notice**: 10 feedback records are in the raw table. The trusted enrichment table is empty — no LLM has touched this data yet.

### Step 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)

**Goal**: Show the LLM enrichment boundary — deterministic input goes in, structured validated output comes back

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json | python3 scripts/fmt.py --type feedback
```

**Expected output**:
- request_id: a UUID
- category: product_quality
- summary: describes the defective blender (cracked lid, grinding noise)
- confidence: 0.8 (above the 0.75 threshold)
- source_doc_ids: ["DOC-001", "DOC-002"]
- validation_status: accepted

**What the learner should notice**: The service classified the feedback, grounded its answer in reference documents, and the validation status is accepted because all checks passed.

### Step 3: Verify the decision was stored in llm_decisions (LO 1b, 1d)

**Goal**: Prove the LLM decision entered the metadata store with full traceability

```bash
curl -s http://localhost:8000/admin/llm-decisions?limit=1 | python3 scripts/fmt.py --type decisions
```

**Expected output**: A decision record showing the same request_id from Step 2, endpoint=feedback, status=accepted, and token counts (prompt=18, completion=46, total=64)

**What the learner should notice**: The request_id matches Step 2, proving end-to-end traceability from enrichment call to decision record. Every LLM call creates a traceable record.

### Step 4: Verify trusted output table received the enriched record (LO 1d)

**Goal**: Prove that validated LLM output reached the trusted analytical table

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics
```

**Expected output**: `raw_feedback: 10`, `trusted_enriched: 1` (the count grew from 0 to 1)

**What the learner should notice**: The trusted table grew from 0 to 1. The validated LLM output was promoted from a proposal to a trusted data product. If validation had failed, the record would have gone to quarantine instead.

## Key takeaway

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
