# Module 1 — Clip 4: Recording runbook

## Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector

**Duration:** 6 minutes
**Learning objectives:** 1a, 1b, 1d
**Code status:** FROZEN — do not modify app code, scripts, data, or Docker files during recording

---

## Terminal setup

- Font size: 18pt minimum (test readability at 50% browser zoom on a laptop screen)
- Terminal width: 120 columns minimum
- Background: dark (Inky Blue #130F25 or default dark terminal theme)
- Truecolor support required (iTerm2, Windows Terminal, GNOME Terminal, macOS Terminal)
- Hide all browser tabs, bookmarks bar, and desktop icons
- Cursor: park it at the end of the prompt line when not typing

---

## Before you hit record

Run the reset script off-camera. This stops any running server, deletes the DuckDB database, and starts a fresh server with seed data.

```bash
./scripts/module1-demo-reset.sh
```

Wait for this exact output before proceeding:

```
Baseline state:
  raw.feedback:              10 rows
  trusted.feedback_enriched: 0 rows

[OK]   Baseline verified.
```

If the baseline is wrong, run reset again. Do not proceed until both numbers are correct.

---

## For retakes

Run the same reset command. It is idempotent — kills the server, deletes the database, restarts fresh. Every reset produces identical baseline state.

```bash
./scripts/module1-demo-reset.sh
```

---

## Command sequence

### Step 1 of 4: DuckDB raw feedback input

**What this proves:** Source data exists in the deterministic pipeline layer before any LLM processing

**Command:**

```bash
curl -s http://localhost:8000/admin/metrics | python3 -m json.tool
```

**What to look for on screen:**

```
"raw_feedback": 10
"trusted_enriched": 0
```

**Narration pause:** After the output appears, say:

> We have 10 customer feedback records in our raw DuckDB table, and the trusted enrichment table is empty. No LLM has touched this data yet. This is the deterministic layer — ingestion, normalization, and storage happen here with no AI involvement.

**Proof point:** DuckDB raw.feedback has input rows before enrichment

---

### Step 2 of 4: Enrich a single feedback record

**What this proves:** The LLM enrichment boundary — deterministic input goes in, structured validated output comes back

**Command:**

```bash
curl -s http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json | python3 -m json.tool
```

**What to look for on screen:**

```json
{
    "request_id": "<UUID>",
    "category": "product_quality",
    "summary": "Customer reports: The blender arrived with a cracked lid and the motor makes a grinding noise",
    "confidence": 0.8,
    "source_doc_ids": ["DOC-001", "DOC-002"],
    "validation_status": "accepted"
}
```

**Narration pause:** After the JSON appears, read the values from screen:

> The service classified this feedback as product quality with 80 percent confidence. It grounded its answer in two reference documents — DOC-001, our product quality standards, and DOC-002, the return and refund guidelines. The validation status is accepted, meaning this output passed schema, grounding, confidence, and category checks. Notice the request ID at the top — we will trace this exact ID into the decisions table next.

**Key values to read aloud:** category, confidence, source_doc_ids, validation_status

**Proof point:** FastAPI returns request_id, category, summary, confidence, source_doc_ids

---

### Step 3 of 4: Verify the decision in llm_decisions

**What this proves:** The LLM decision entered the metadata store with full traceability

**Command:**

```bash
curl -s http://localhost:8000/admin/llm-decisions?limit=1 | python3 -m json.tool
```

**What to look for on screen:**

```json
[{
    "request_id": "<same UUID from Step 2>",
    "endpoint": "feedback",
    "status": "accepted",
    "prompt_tokens": 18,
    "completion_tokens": 46,
    "total_tokens": 64,
    ...
}]
```

**Narration pause:** After the output appears:

> Here is the decision record in our metadata store. The request ID matches exactly — this is the same enrichment call we just made. The endpoint is feedback, the status is accepted, and we can see the token breakdown: 18 prompt tokens, 46 completion tokens, 64 total. Every LLM call in this system creates a traceable decision record. If this output had failed validation, the status would show failed and the record would explain why.

**Key values to read aloud:** request_id (confirm it matches Step 2), status, token counts

**Proof point:** llm_decisions table records the same request_id and validation status

---

### Step 4 of 4: Verify the trusted output table

**What this proves:** Validated LLM output reached the trusted analytical table

**Command:**

```bash
curl -s http://localhost:8000/admin/metrics | python3 -m json.tool
```

**What to look for on screen:**

```
"raw_feedback": 10
"trusted_enriched": 1
```

**Narration pause:** After the output appears:

> The trusted enrichment table now has one row. It started at zero before we ran the enrichment. That single row is the feedback we just classified — it passed all four validation checks, so the system promoted it from an LLM proposal to a trusted data product. If the confidence had been below our 75 percent threshold, or if the category had been outside our allowed list, that record would have gone to quarantine instead of here.

**Key values to read aloud:** trusted_enriched count (was 0, now 1)

**Proof point:** DuckDB trusted.feedback_enriched row count increased by 1

---

## Callout slide

Show for 8 seconds during the Step 4 narration:

> LLM outputs are proposals until validation promotes them to trusted data

---

## Summary checklist (confirm before exporting)

After recording, scrub through the video and verify each proof point is visible:

| # | Proof point | Visible on screen |
|---|-------------|-------------------|
| 1 | raw.feedback = 10, trusted_enriched = 0 | Step 1 metrics output |
| 2 | category = product_quality, confidence = 0.8, accepted | Step 2 JSON response |
| 3 | Same request_id in llm_decisions, status = accepted | Step 3 JSON response |
| 4 | trusted_enriched changed from 0 to 1 | Step 4 metrics output |

If any proof point is not clearly visible, reset and re-record that step.

---

## Deterministic output reference

These values are produced by the deterministic LLM stub. They are the same on every run after a reset.

| Field | Exact value |
|-------|-------------|
| category | `product_quality` |
| summary | `Customer reports: The blender arrived with a cracked lid and the motor makes a grinding noise` |
| confidence | `0.8` |
| source_doc_ids | `["DOC-001", "DOC-002"]` |
| validation_status | `accepted` |
| prompt_tokens | `18` |
| completion_tokens | `46` |
| total_tokens | `64` |
| raw.feedback count | `10` |
| trusted_enriched before | `0` |
| trusted_enriched after | `1` |

---

## Warning

Do not modify any of the following during recording:

- `app/` source code
- `scripts/` demo scripts
- `data/payloads/` payload files
- `data/seed/` seed data
- `docker-compose.yml`
- `requirements.txt`

If something breaks, run `./scripts/module1-demo-reset.sh` and start over. Do not edit code to fix it on camera.
