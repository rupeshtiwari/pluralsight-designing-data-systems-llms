# Module 1 — Clip 4: Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector (6 minutes)

## Why this matters

**The problem:** Your team wants to use an LLM to classify thousands of customer feedback records, but a wrong classification that silently lands in a trusted analytics table can mislead every dashboard and decision downstream. How do you let an LLM enrich your data without letting it corrupt your warehouse?

**What you will see:** A working boundary where raw feedback flows in, the LLM proposes a classification with a confidence score and cited sources, and the output only reaches the trusted table after four explicit validation gates pass. You will also see what happens when a record fails — it lands in quarantine, never in trusted.

**What you walk away with:** A repeatable pattern for placing an LLM inside an existing pipeline (1a), drawing a clean line between deterministic and AI-driven steps (1b), and designing a data flow where every LLM output is traceable and validated before it becomes trusted data (1d). This is the foundation every later module builds on.

## Overview

This demo runs the NorthWind feedback enrichment flow from DuckDB source records through FastAPI LLM enrichment to the trusted output table — and proves the negative case by sending an ambiguous record through the same pipe and watching it land in quarantine.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1a | Demonstrate identifying where LLMs fit within data pipelines so learners can extend existing systems effectively |
| 1b | Define system boundaries so learners can separate deterministic and AI-driven components |
| 1d | Demonstrate designing data flows that incorporate LLM outputs |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| DuckDB `raw.feedback` has input records ready for enrichment | Step 1 | 1a |
| pgvector reference documents (Postgres + 384-dim embeddings) ground the LLM | Step 2 | 1a, 1b |
| The JSON contract from Clip 2 is the boundary between deterministic and AI-driven code | Step 3 | 1b |
| FastAPI returns structured enrichment with request_id, category, summary, confidence, source_doc_ids | Step 4 | 1a, 1b |
| `llm_decisions` records the four validation gates: schema, grounding, confidence, source ID | Step 5 | 1b, 1d |
| DuckDB `trusted.feedback_enriched` row count grows after validated enrichment | Step 6 | 1d |
| DuckDB `quarantine.llm_outputs` receives a failed record — trusted table stays clean | Step 7 | 1d |

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

**Goal**: Prove source data exists in the deterministic pipeline layer before any LLM processing.

The FastAPI server holds an exclusive lock on the DuckDB file while it runs, so the row counts are read through the `/admin/metrics` endpoint that wraps the same DuckDB query.

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics \
  --title "DuckDB warehouse row counts (before enrichment)" \
  --why "Source data is ready; the trusted and quarantine tables are still empty"
```

**Equivalent direct DuckDB CLI query** (works only when the server is stopped):

```bash
duckdb data/northwind.duckdb \
  "SELECT count(*) AS raw_feedback FROM raw.feedback;"
```

**Expected output**: `raw_feedback: 10`, `trusted_enriched: 0`, `quarantine_outputs: 0`.

**What the learner should notice**: Ten customer feedback records are waiting in the raw landing layer of the warehouse. The trusted analytics table is empty and the quarantine table is empty — no LLM has touched any of this data yet. This is the deterministic source layer the rest of the pipeline depends on. Whatever happens next happens at a boundary we control.

### Step 2: Show the pgvector reference documents (LO 1a, 1b)

**Goal**: Prove the LLM is grounded in approved product and policy documents stored in PostgreSQL with pgvector.

```bash
curl -s "http://localhost:8000/admin/reference-docs?limit=8" | python3 scripts/fmt.py --type refdocs \
  --title "pgvector reference documents" \
  --why "Approved policies the LLM is grounded against, stored in Postgres with vector(384) embeddings"
```

**Expected output**: backend `postgres`, count `8`, `all_embedded: true (all 384-dim)`, then one row per doc with `★ DOC-001 … DOC-008` and its title.

**What the learner should notice**: Eight approved policies — product quality, returns, shipping, merchant guidelines, runbooks, catalog standards — live in PostgreSQL with 384-dimension vector embeddings. When the LLM needs to ground a classification, the service cosine-searches this table. The doc IDs you see here are exactly what the response will cite later as `source_doc_ids`. The LLM cannot cite a document that is not in this approved set, and that constraint is what makes its claims auditable.

### Step 3: Show the JSON contract from Clip 2 (LO 1b)

**Goal**: Show the boundary contract the service is required to emit before we call it for real.

```bash
curl -s http://localhost:8000/admin/json-contract | python3 scripts/fmt.py --type contract \
  --title "FeedbackEnrichResponse — the boundary contract" \
  --why "Deterministic pipeline only reads these fields. Free-form LLM text never crosses this line."
```

**Expected output**: contract `FeedbackEnrichResponse`, response fields `request_id, category, summary, confidence, source_doc_ids, validation_status`, and the four validation gates ★ highlighted.

**What the learner should notice**: This is the contract Clip 2 introduced. Six fields, every one structured. The deterministic pipeline never sees free-form text from the LLM — it only reads from these six slots. The four validation gates on the right are what the service runs against every response before it is allowed to emit `validation_status: accepted`. This is the boundary that lets the rest of the pipeline stay safe no matter what the model says.

### Step 4: Enrich a single feedback record through FastAPI (LO 1a, 1b)

**Goal**: Send a real record through the LLM boundary and read every contract field back.

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json | python3 scripts/fmt.py --type feedback \
  --title "FastAPI enrichment response" \
  --why "The LLM proposal: category, confidence, and cited sources"
```

**Expected output (all 5 outline-named fields are ★-highlighted)**:
- ★ request_id: a UUID
- ★ category: `product_quality`
- ★ summary: describes the defective blender (cracked lid, grinding noise)
- ★ confidence: `0.8` (above the 0.75 threshold)
- ★ source_doc_ids: `["DOC-001", "DOC-002"]`
- ★ validation_status: `accepted`

**What the learner should notice**: A real customer record went through the LLM boundary. Every contract field is filled. The category is `product_quality` because the feedback text mentions cracked lid and grinding noise — that is the LLM proposal. Confidence is 0.8, comfortably above the 0.75 threshold. The cited sources are DOC-001 and DOC-002 from the pgvector knowledge base. And `validation_status: accepted` means the four gates we are about to inspect all passed.

### Step 5: Verify the decision and the four validation gates in llm_decisions (LO 1b, 1d)

**Goal**: Prove the decision entered the Postgres metadata store and walk through each of the four gates the outline names.

```bash
curl -s "http://localhost:8000/admin/llm-decisions?limit=1" | python3 scripts/fmt.py --type decisions \
  --title "Decision record in llm_decisions" \
  --why "Same request_id as Step 4 plus the four validation checks"
```

**Expected output**: A decision record with the same `request_id` from Step 4 and a validation checks block:
- ★ schema ✓ PASS
- ★ grounding ✓ PASS
- ★ confidence ✓ PASS
- ★ source ID ✓ PASS

**Direct psql proof** (in a second terminal):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT request_id, status, validation->'checks' AS checks FROM llm_decisions ORDER BY created_at DESC LIMIT 1;"
```

**What the learner should notice**: The `request_id` matches Step 4 exactly — end-to-end traceability from the enrichment call to the durable Postgres record. Walk the four checks. Schema passed because every required field is present. Grounding passed because every `source_doc_id` is in the approved reference set. Confidence passed because 0.8 is above 0.75. And source ID passed because DOC-001 and DOC-002 actually exist in `reference_docs`. Only when all four gates pass does `validation_status` flip to accepted. Weeks from now you can query this table to explain why any record was accepted, retried, or rejected.

### Step 6: Verify the validated record landed in trusted (LO 1d)

**Goal**: Prove the validated LLM output reached the trusted analytical table.

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics \
  --title "DuckDB warehouse row counts (after Step 4)" \
  --why "The validated output was promoted to the trusted table"
```

**Equivalent direct DuckDB CLI queries** (server stopped):

```bash
duckdb data/northwind.duckdb \
  "SELECT count(*) AS trusted_enriched FROM trusted.feedback_enriched;
   SELECT request_id, category, confidence, validation_status
   FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 1;"
```

**Expected output**: `trusted_enriched: 1` (grew from 0 to 1); `quarantine_outputs: 0`.

**What the learner should notice**: The trusted analytics table grew from zero to one. That single row is the LLM proposal that survived every gate. Downstream dashboards, customer service routing, executive reports — they all read from this table. The pipeline owner can sleep at night knowing nothing reached `trusted.feedback_enriched` without the full validation chain firing first. This is the design contract: LLM outputs are proposals; trusted tables only ever see validated facts.

### Step 7: Show what gets quarantined when validation fails (LO 1d)

**Goal**: Prove the gate works in both directions — bad LLM output lands in quarantine, not in trusted.

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_ambiguous.json | python3 scripts/fmt.py --type feedback \
  --title "FastAPI enrichment response — ambiguous record" \
  --why "Low confidence ⇒ validation fails ⇒ quarantine path"
```

Then show the updated counts:

```bash
curl -s http://localhost:8000/admin/metrics | python3 scripts/fmt.py --type metrics \
  --title "DuckDB warehouse row counts (after the failed record)" \
  --why "Trusted stayed at 1; quarantine grew from 0 to 1"
```

**Expected output**: response shows `★ confidence: 0.5`, `★ validation_status: failed`. Metrics show `trusted_enriched: 1` (unchanged) and `quarantine_outputs: 1` (grew).

**What the learner should notice**: This is the negative case the outline asks for. We sent an ambiguous record — text the LLM cannot confidently classify. The model came back with confidence 0.5, well below the 0.75 threshold, so the confidence gate failed and `validation_status` is `failed`. Look at the counts: `trusted_enriched` is still one — the record never reached the analytics table. Instead it landed in `quarantine.llm_outputs` with the validation errors recorded next to the raw output. In a real pipeline, a human reviews quarantine rows, or they get retried with a stronger prompt, or they get dropped. They never silently pollute downstream analytics. That is the difference between a pipeline that benefits from LLMs and one that gets corrupted by them.

## Best-practice callout

**Trusted tables need validated generated fields.**

LLM outputs are proposals until validation promotes them to trusted data. When validation fails, the record goes to quarantine — never to trusted.

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

- `app/routers/enrichment.py` — Feedback enrichment endpoint with trusted/quarantine routing
- `app/services/llm_stub.py` — Deterministic LLM stub (keyword-based, reproducible)
- `app/validators/output_validator.py` — Schema, grounding, confidence, source-ID checks
- `app/db/pgvector.py` — Reference document retrieval via real pgvector
- `data/payloads/feedback_enrich.json` — Defective blender (accepted path)
- `data/payloads/feedback_ambiguous.json` — Ambiguous text (quarantine path)
- `data/seed/feedback.json` — Seed data (10 records)
- `data/seed/reference_docs.json` — 8 approved reference documents
