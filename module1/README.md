# Module 1 — Clip 4: Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector (6 minutes)

## Why this matters

**The problem:** Your team wants to use an LLM to classify thousands of customer feedback records, but a wrong classification that silently lands in a trusted analytics table can mislead every dashboard and decision downstream. How do you let an LLM enrich your data without letting it corrupt your warehouse?

**What you will see:** Seven distinct moments in the enrichment pipeline — actual source records, a real similarity search, the boundary contract, the LLM's proposal, the durable audit, the promoted trusted row, and the quarantined failure. Each step shows a different surface of the system, so by the end you can point to where every guarantee lives.

**What you walk away with:** A repeatable pattern for placing an LLM inside an existing pipeline (1a), drawing a clean line between deterministic and AI-driven steps (1b), and designing a data flow where every LLM output is traceable and validated before it becomes trusted data (1d).

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1a | Demonstrate identifying where LLMs fit within data pipelines so learners can extend existing systems effectively |
| 1b | Define system boundaries so learners can separate deterministic and AI-driven components |
| 1d | Demonstrate designing data flows that incorporate LLM outputs |

## What this demo proves — and each step is unique

| Step | Endpoint | What it teaches (nothing repeats) | LO |
|------|----------|-----------------------------------|----|
| 1 | `/admin/raw-feedback` | Source data has real structure — actual customer text, not just a row count | 1a |
| 2 | `/admin/retrieve` | pgvector is a live retrieval mechanism — top-3 matches with cosine ranking, not just stored docs | 1a, 1b |
| 3 | `/admin/json-contract` | The LLM is constrained by a contract before it can speak — Pydantic schema + four named gates | 1b |
| 4 | `/enrich/feedback` | The LLM produces one classified proposal with cited sources | 1a, 1b |
| 5 | `/admin/llm-decisions` | Every decision is durably recorded with a check-by-check audit | 1b, 1d |
| 6 | `/admin/trusted-rows` | The promoted row's actual content lives in `trusted.feedback_enriched` | 1d |
| 7 | `/admin/quarantine-rows` | The failed row, the gate that rejected it, and the LLM proposal sit in `quarantine.llm_outputs` for human review | 1d |

## Prerequisites

1. Server running: `curl -s http://localhost:8000/health | python3 -m json.tool`
2. Knowledge base seeded (8 reference docs)
3. Postgres reachable (for the `backend: postgres` proof in Step 2 and Step 5)

To start from a clean state:
```bash
./scripts/module1-demo-reset.sh
```

## Demo steps

### Step 1: Show three actual records from the raw landing zone (LO 1a)

**Goal**: Make the source data concrete — three real customer feedback rows the LLM is about to classify.

```bash
curl -s "http://localhost:8000/admin/raw-feedback?limit=3" | python3 scripts/fmt.py --type raw-rows \
  --title "raw.feedback — three sample records" \
  --why "The deterministic source layer the LLM is about to classify"
```

**Expected output**: three rows with `★ id`, customer, product, and the full feedback text. No counts, no metrics — actual records.

**What the learner should notice**: This is what the deterministic pipeline already owns. Three real customer messages — a defective blender, a late delivery, a praise note about customer service. The job is to add an LLM-generated category to each one without ever letting a bad classification reach a trusted table. Everything that follows is the boundary that makes that safe. None of these rows have been touched by an LLM yet.

### Step 2: Show pgvector retrieving grounding sources (LO 1a, 1b)

**Goal**: Prove pgvector is a live retrieval mechanism — not just a table of docs but a similarity search that ranks results.

```bash
curl -s "http://localhost:8000/admin/retrieve?q=cracked+lid+blender&top_k=3" | python3 scripts/fmt.py --type retrieve \
  --title "pgvector similarity search" \
  --why "Top-3 grounding sources for the LLM, ranked by cosine distance"
```

**Expected output**: backend `postgres`, query `"cracked lid blender"`, top_k `3`, then three ★ ranked rows showing `DOC-00X` plus doc_type and title.

**What the learner should notice**: The query string is hashed into a 384-dimension vector and compared against eight pre-embedded reference documents in Postgres. The top-3 results come back ordered by cosine distance — product quality first, then return policy, then shipping. This is exactly how the enrichment service picks its source citations. The LLM cannot invent a doc ID; it can only cite the ones pgvector ranks high enough to surface. That is the grounding contract.

### Step 3: Show the JSON contract the LLM must emit (LO 1b)

**Goal**: Show the boundary contract from Clip 2 — schema fields plus the four named validation gates.

```bash
curl -s http://localhost:8000/admin/json-contract | python3 scripts/fmt.py --type contract \
  --title "FeedbackEnrichResponse — the boundary contract" \
  --why "Deterministic pipeline only reads these fields; four gates run on every response"
```

**Expected output**: contract `FeedbackEnrichResponse`, response fields `request_id, category, summary, confidence, source_doc_ids, validation_status`, then the four ★ validation gates (schema, grounding, confidence, source ID).

**What the learner should notice**: This is the contract Clip 2 introduced. Six structured fields — no free-form prose ever crosses this line. And below them, the four gates the service runs on every response. Schema, grounding, confidence, and source ID. We're going to see each gate fire in the next two steps. The model can say anything inside this contract; it cannot violate the shape.

### Step 4: Run a real feedback record through the LLM boundary (LO 1a, 1b)

**Goal**: Trigger the LLM proposal and read every contract field back.

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json | python3 scripts/fmt.py --type feedback \
  --title "FastAPI enrichment response" \
  --why "The LLM proposal: category, confidence, and cited sources"
```

**Expected output (all 5 outline-named fields are ★)**:
- ★ request_id — a UUID
- ★ category — `product_quality`
- ★ summary — describes the blender (cracked lid, grinding noise)
- ★ confidence — `0.8` (above 0.75)
- ★ source_doc_ids — `["DOC-001", "DOC-002"]`
- ★ validation_status — `accepted`

**What the learner should notice**: Step 1's first record just went through the boundary. The category is `product_quality` because the feedback mentions a cracked lid and grinding noise. Confidence is 0.8. The cited sources are DOC-001 and DOC-002 — the same documents pgvector ranked first in Step 2. The pipeline never sees free-form model text — it only reads these six structured fields, and `validation_status: accepted` is the LLM's claim that the four gates we just defined all passed. Next step proves it.

### Step 5: Audit the four validation gates in llm_decisions (LO 1b, 1d)

**Goal**: Open the durable Postgres audit record and walk through each named gate.

```bash
curl -s "http://localhost:8000/admin/llm-decisions?limit=1" | python3 scripts/fmt.py --type decisions \
  --title "Decision record in llm_decisions" \
  --why "Same request_id as Step 4 plus the four named validation checks"
```

**Direct psql proof** (works while server is up):

```bash
docker exec northwind-postgres psql -U northwind -d northwind -c \
  "SELECT request_id, status, validation->'checks' AS checks FROM llm_decisions ORDER BY created_at DESC LIMIT 1;"
```

**Expected output**: decision record with the same `request_id` from Step 4 and a validation checks block:
- ★ schema ✓ PASS
- ★ grounding ✓ PASS
- ★ confidence ✓ PASS
- ★ source ID ✓ PASS

**What the learner should notice**: This is a row in real Postgres, not a log line. The `request_id` matches Step 4 exactly — that is end-to-end traceability. Walk the four gates. Schema passed because every required field was present. Grounding passed because every cited doc ID is in pgvector. Confidence passed because 0.8 is above 0.75. Source ID passed because the cited docs actually exist. Only when all four passed did the service flip `validation_status` to `accepted`. Six months from now you can query this table to answer "why did record X get accepted" without re-running the model.

### Step 6: Show the actual promoted row in the trusted table (LO 1d)

**Goal**: Look at the trusted row itself — not a row count, the row's content.

```bash
curl -s "http://localhost:8000/admin/trusted-rows?limit=1" | python3 scripts/fmt.py --type trusted-rows \
  --title "trusted.feedback_enriched — the promoted row" \
  --why "Validated LLM output is now part of the trusted data product"
```

**Equivalent direct DuckDB CLI** (server stopped):

```bash
duckdb data/northwind.duckdb \
  "SELECT request_id, category, confidence, source_doc_ids, validation_status \
   FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 1;"
```

**Expected output**: one ★ row with `request_id` (matches Step 4), `category=product_quality`, `confidence=0.8`, `source_doc_ids=["DOC-001", "DOC-002"]`, `validation_status=accepted`.

**What the learner should notice**: The trusted analytics table now has a real row. Same `request_id` as Steps 4 and 5 — the chain is complete. The row carries the category, the confidence, the cited sources, and the validation status. Downstream dashboards, customer service routing, executive reports — they all read from this table and they all get a record that the gates approved. The pipeline owner can defend this row in front of any auditor: every field came from a contract, every check is recorded next door in Postgres.

### Step 7: Show a failed row and the gate that rejected it (LO 1d)

**Goal**: Prove the gate works in both directions — bad LLM output goes to quarantine with the failing gate visible.

```bash
# First, send an ambiguous record that the LLM cannot classify confidently
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_ambiguous.json > /dev/null

# Then inspect the quarantine table
curl -s "http://localhost:8000/admin/quarantine-rows?limit=1" | python3 scripts/fmt.py --type quarantine-rows \
  --title "quarantine.llm_outputs — the failed row" \
  --why "Failed validation lands here with the specific gate that failed"
```

**Equivalent direct DuckDB CLI** (server stopped):

```bash
duckdb data/northwind.duckdb \
  "SELECT request_id, input_text, raw_output, validation_errors \
   FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 1;"
```

**Expected output**: one quarantine row showing the input text, the LLM's proposal (`category=general_praise`, `confidence=0.55`), and the per-gate result with `✗ confidence: Confidence 0.55 below threshold 0.75` clearly marked.

**What the learner should notice**: This is the negative case the outline calls for. We sent an ambiguous record — text the LLM has no strong keywords for. The model came back with a default category and confidence 0.55, below our 0.75 threshold. So the confidence gate failed, and you can see exactly which gate failed in the `validation_errors` column. The trusted table did not grow. Instead the row sits in `quarantine.llm_outputs` with the input, the raw model proposal, and the specific reason — ready for a human to review, retry with a stronger prompt, or drop. The pipeline owner sleeps at night because failures are visible, debuggable, and isolated from the trusted data product.

## Best-practice callout

**Trusted tables need validated generated fields.**

LLM outputs are proposals until validation promotes them to trusted data. When validation fails, the record goes to quarantine — never to trusted.

## Preflight check

```bash
module1/scripts/preflight_check.sh
```

Runs every step above, captures each command and its output, maps each step to its LO, and writes the log to `module1/preflight_log.txt` so you can confirm alignment with the outline before recording.

## Cleanup

```bash
./scripts/module1-demo-reset.sh
```

## Key files

- `app/routers/enrichment.py` — `/enrich/feedback` with trusted/quarantine routing
- `app/db/duckdb_client.py` — `fetch_all_feedback`, `fetch_trusted_rows`, `fetch_quarantine_rows`
- `app/db/pgvector.py` — pgvector retrieval used in Steps 2 and 4
- `app/validators/output_validator.py` — the four gates: schema, grounding, confidence, source ID
- `app/services/llm_stub.py` — deterministic LLM stub
- `data/payloads/feedback_enrich.json` — defective blender (accepted path)
- `data/payloads/feedback_ambiguous.json` — ambiguous text (quarantine path)
- `data/seed/feedback.json` — 10 raw feedback records
- `data/seed/reference_docs.json` — 8 approved reference documents
