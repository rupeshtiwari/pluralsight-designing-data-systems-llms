# Module 4 — Clip 4: Demo: Rejecting hallucinated and schema-drifted LLM outputs in Airflow (6 minutes)

## Why this matters

**The problem:** LLMs hallucinate. They invent categories that do not exist, return outputs missing required fields, cite source documents they never read, and answer with low confidence on ambiguous input. If any of those outputs flow into your trusted analytical tables, the business decisions downstream are quietly wrong. The question is not whether LLMs will produce bad output — they will — the question is whether your pipeline catches it before it lands in trusted storage.

**What you will see:** A NorthWind batch containing ambiguous feedback, stale reference context, and invalid category values, run through a five-check validation gate after generation. Each check — schema, source_id, category mapping, confidence, disposition — surfaces its own pass or fail. Accepted records are written to `trusted.feedback_enriched`. Rejected records are routed to `quarantine.llm_outputs` with the exact failure reason. The clip closes with the four design contracts the entire course delivered.

**What you walk away with:** A validation gate that turns generated text into trustworthy data (1d), monitoring on `pipeline_runs` that surfaces accepted, rejected, and validation-failure counts so quality problems are observable (3c), and the guardrail mindset that **rejecting bad output is a successful pipeline outcome, not a failure** (3d).

## Overview

This demo seeds a batch of five pre-enriched feedback records — one valid, four engineered to fail one validation check each — through `POST /pipeline/validate-batch`. The validation gate routes them by disposition, writes them to two distinct DuckDB schemas, and records the aggregate in PostgreSQL `pipeline_runs`. A DuckDB CLI moment proves the actual rows landed in the correct schemas, and a closing course-summary slide names the four design contracts learners now own.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 1d | Demonstrate designing data flows that incorporate LLM outputs |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| Five validation checks (schema, source_id, category, confidence, disposition) are enforced after generation | Step 1 | 3d |
| `POST /pipeline/validate-batch` accepts a NorthWind batch with ambiguous feedback, stale context, and invalid category values, returns `batch_id` and per-record results | Step 2 | 3c, 3d |
| FastAPI response shows one valid output and at least one invalid validation reason | Step 3 | 3d |
| `/pipeline/routing-detail/{batch_id}` proves accepted records route to `trusted.feedback_enriched` and rejected records to `quarantine.llm_outputs` | Step 4 | 3c, 3d |
| `pipeline_runs` aggregate in PostgreSQL shows accepted_count, rejected_count, and validation_summary | Step 5 | 3c |
| DuckDB CLI shows accepted rows in `trusted.feedback_enriched` and rejected rows with reasons in `quarantine.llm_outputs` | Step 6 | 1d, 3d |

## Prerequisites

The reset script handles everything. Before the demo:

```bash
./scripts/module4-demo-reset.sh
```

This stops any old FastAPI process, clears the DuckDB warehouse, removes orphan Airflow containers, restarts the stack, seeds the knowledge base, and seeds one validation batch so the demo has baseline data on the first call. When it finishes you should see:

- `[OK]   Airflow webserver is responding (after Ns)` — real Airflow up
- `[OK]   FastAPI server started (PID ...)` — API live on port 8000
- `[OK]   Seeded batch BATCH-VAL-XXXXXXXX — accepted=1, rejected=4` — validation gate routed the engineered records correctly

Then run the preflight to verify every step renders correctly before recording:

```bash
module4/scripts/preflight_check.sh
```

## Demo steps

### Step 1: Show the five validation checks enforced after generation (LO 3d)

**Goal**: Establish what "validation" means in this clip — the five outline-named checks (schema, source_id, category, confidence, disposition) the gate enforces on every generated record.

```bash
curl -s http://localhost:8000/validate/rules \
  | python3 scripts/fmt.py --type validation-rules \
  --title "Validation rules enforced after generation" \
  --why "Schema, source_id, category, confidence, disposition — every record passes each one"
```

**Expected output**:

- ★ schema — required fields: `category`, `summary`, `confidence`, `source_doc_ids`
- ★ source_id — every record needs at least one `source_doc_id`
- ★ category — allowed values list (the six valid NorthWind categories)
- ★ confidence — must be >= the configured threshold (0.75)
- ★ disposition — branch routes accepted → trusted, rejected → quarantine

**What the learner should notice**: The five checks are not framework defaults — they encode this organization's policy about what counts as a usable LLM output. The threshold, the allowed categories, and the required fields are all readable from `/validate/rules`, which means operators can audit the gate without reading source code. That readability is half the point of LO 3d: a guardrail you cannot inspect is a guardrail you cannot trust.

### Step 2: Trigger the bad-data batch and capture the batch id (LO 3c, 3d)

**Goal**: Run the NorthWind batch containing one valid record and four records engineered to fail one specific check each, and capture the `batch_id` so Steps 3, 4, and 5 all pin to this exact run.

```bash
BATCH=$(curl -s -X POST http://localhost:8000/pipeline/validate-batch \
  -H "Content-Type: application/json" \
  -d "{\"items\": $(cat data/payloads/module4_validation_batch.json)}")

echo "$BATCH" | python3 scripts/fmt.py --type validate-batch \
  --title "Validation batch with bad LLM outputs" \
  --why "5 records: 1 valid, 4 engineered to fail one check each"

# Capture the batch id for Steps 4 and 5
BATCH_ID=$(echo "$BATCH" | jq -r '.batch_id')
echo "BATCH_ID=$BATCH_ID"
```

**Expected output**:

- ★ batch_id: `BATCH-VAL-XXXXXXXX` (the id Steps 4/5 will use)
- ★ total: `5`
- ★ accepted_count: `1`
- ★ rejected_count: `4`
- failure breakdown — one entry per check name that fired (schema, source_id, category, confidence)

**What the learner should notice**: The pipeline did not crash on bad data — it classified it. Five records went in, one came out as accepted, four were rejected, and the breakdown tells operators which validation gate caught which failure. That is the orchestration half of LO 3c — a single trigger produces structured, audit-grade output, not a stack trace.

### Step 3: Show one valid output and at least one invalid validation reason (LO 3d)

**Goal**: Drill into the per-record outcomes from Step 2's response so the audience sees both the valid result and the specific reason each invalid record was rejected.

```bash
echo "$BATCH" | python3 scripts/fmt.py --type validate-batch \
  --title "Per-record validation outcomes for $BATCH_ID" \
  --why "One ★ row per record — accepted in lime, rejected in pink with reason"
```

**Expected output**:

- per-record outcomes block — one ★ row per `feedback_id` with:
  - ★ status: `accepted` (lime) for the valid record
  - ★ status: `rejected` (pink) for each of the four bad records
  - reason: the literal text from the validator (e.g. `Confidence 0.55 below threshold 0.75`, `Category 'electronics_repair' not in allowed values: [...]`, `No source documents referenced`, `Missing required fields: summary`)
  - routed_to: `trusted.feedback_enriched` or `quarantine.llm_outputs`

**What the learner should notice**: Each rejection carries the exact reason a human operator needs to fix it — not just `rejected`. That is the difference between a guardrail and a blocker. The valid record proves the gate is not just rejecting everything; the four invalid ones prove it is checking the specific properties the outline names. This single screen is the LO 3d demonstration: ambiguous input (`confidence 0.55`), stale reference context (`source_doc_ids = []`), invalid category (`electronics_repair`), and schema drift (`summary` missing) each get caught with a specific reason.

### Step 4: Show Airflow routing — accepted to trusted, rejected to quarantine (LO 3c, 3d)

**Goal**: Prove the disposition decision routed each accepted record to `trusted.feedback_enriched` and each rejected record to `quarantine.llm_outputs` — the routing contract the Airflow validation task enforces.

```bash
curl -s "http://localhost:8000/pipeline/routing-detail/${BATCH_ID}" \
  | python3 scripts/fmt.py --type routing-detail \
  --title "Airflow routing for $BATCH_ID" \
  --why "Accepted records → trusted; rejected → quarantine with failure breakdown"
```

**Expected output**:

- ★ batch_id: same id as Step 2
- ★ accepted_count: `1`
- ★ rejected_count: `4`
- ★ trusted_table: `trusted.feedback_enriched`
- ★ quarantine_table: `quarantine.llm_outputs`
- why records were routed to quarantine — one ★ row per failed check with its count

**What the learner should notice**: The two table names are literal proof of where the records went, not where they were "supposed to" go. The same `validation_branch` pattern shown in Module 3 is the production routing primitive — accepted means "fits every contract", rejected means "violated at least one", and the gate puts each record in the schema that matches its disposition. The trusted table never sees a record that failed any check. That is the safety property LO 3d is asking the learner to design for.

### Step 5: Show PostgreSQL pipeline_runs — accepted_count, rejected_count, validation_summary (LO 3c)

**Goal**: Show the operational monitoring view — a single `pipeline_runs` row per batch that anyone wiring an alerting dashboard would query.

```bash
curl -s "http://localhost:8000/pipeline/runs?limit=3" \
  | python3 scripts/fmt.py --type pipeline-runs \
  --title "pipeline_runs aggregate (PostgreSQL)" \
  --why "One row per batch — accepted_count, rejected_count, validation_summary"
```

**Expected output**:

- ★ rows returned: `3` (or however many recent batches exist)
- For each row:
  - ★ batch_id
  - ★ status: `completed`
  - ★ accepted
  - ★ rejected
  - ★ validation_summary: `schema=N, source_id=N, category=N, confidence=N` (which checks fired for that batch)

**What the learner should notice**: This is the layer monitoring code consumes. A run that completed without raising an exception is not a healthy run if the `rejected` column climbed — that is exactly the LO 3c lesson. The `validation_summary` column lets you alert per failure mode: an alert on `category=` rising means the LLM is drifting toward outputs your taxonomy does not cover, which is a different problem from `confidence=` rising (the LLM hedging on ambiguous input).

### Step 6: DuckDB CLI proof — trusted + quarantine schemas (LO 1d, 3d)

**Goal**: Final on-camera proof that the routing decision actually landed rows in two distinct DuckDB schemas with the validation reason preserved end-to-end.

```bash
module4/scripts/duckdb_proof.sh
```

**Expected output** (one screen, no scroll):

- ★ trusted.feedback_enriched — accepted sample row (`request_id`, `category`, `confidence`, `validation_status`) and total row count
- ★ quarantine.llm_outputs — rejected sample row (`request_id`, full `validation_errors`) and total row count

**What the learner should notice**: The two table names — `trusted.feedback_enriched` and `quarantine.llm_outputs` — are the literal proof the outline asks for. Same warehouse, two schemas, every row's disposition decided by the validation gate before it landed. The `validation_errors` column in quarantine preserves the exact reason, so a downstream operator can replay the failure without re-running the LLM. That is LO 1d in one screen: a data flow design where the LLM produces text, the validation gate decides which text becomes data, and the trusted table only ever receives text that passed every contract.

## Airflow UI moment (one-screen visual)

Show one short Airflow UI screen so the outline's visual proof line is on camera:

1. Open `http://localhost:8080`, log in `admin / admin`, click `northwind_llm_enrichment`.
2. **Grid view** — the latest run row is green (`success`); the visual equivalent of a successful pipeline outcome.
3. **Graph view** — `validation_branch` fans out to `write_trusted` and `write_quarantine`. The branch the most recent run took is colored success; the sibling is colored skipped. This is the topology the outline calls "downstream accepted and quarantine branches".

## Course summary slide (final moment)

Close the entire course with the four design contracts the learner now owns:

```bash
module4/scripts/course_summary.sh
```

**Expected output**: A one-screen recap, same brand palette as every demo step, with four ★ rows:

- ★ Module 1: LLM placement — where the model sits in the data flow
- ★ Module 2: Boundary contracts — agent tools and approval gates
- ★ Module 3: Orchestration control — trigger, monitor, branch on data
- ★ Module 4: Output validation — reject bad output as a successful outcome

## Best-practice callout

**Rejecting bad output is a successful pipeline outcome.**

A pipeline that ran end to end without rejecting anything is not proof the LLM was perfect; it is proof the gate was not watching. Every accepted record should be one that passed every contract; every rejected record should land in quarantine with a specific reason. Track `accepted_count` and `rejected_count` together. Alert on the *failure breakdown shape*, not on the existence of rejections — a steady stream of low-confidence rejects is the gate doing its job; a sudden spike of category mismatches is the LLM drifting away from the taxonomy. The validation gate is the line between generated text and trustworthy data.

## Preflight check

Before recording, execute the preflight script to verify every step produces the expected output and the LOs are covered:

```bash
module4/scripts/preflight_check.sh
```

The script runs all six demo steps, captures every command and its output, maps each step to its learning objective, and saves the log to `module4/preflight_log.txt`. The final block confirms LO coverage for 1d, 3c, 3d, and prints fix prompts for any failed check.

## Cleanup

```bash
./scripts/module4-demo-reset.sh
```

## Key files

- `app/routers/pipeline.py` — `/pipeline/validate-batch`, `/pipeline/routing-detail/{batch_id}`, `/pipeline/runs`
- `app/routers/validation.py` — `/validate/rules`, `/validate/output`
- `app/validators/output_validator.py` — Five validation checks the gate enforces
- `data/payloads/module4_validation_batch.json` — Five-record batch: one valid, four engineered failures
- `scripts/fmt.py` — `--type validation-rules`, `validate-batch`, `routing-detail`, `pipeline-runs`
- `module4/scripts/duckdb_proof.sh` — DuckDB CLI proof moment (trusted + quarantine schemas)
- `module4/scripts/course_summary.sh` — Closing slide (four design contracts)
- `scripts/module4-demo-reset.sh` — Reset all state and seed one validation batch
