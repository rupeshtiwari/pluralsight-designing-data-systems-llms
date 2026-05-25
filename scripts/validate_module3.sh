#!/usr/bin/env bash
set -euo pipefail
#
# Module 3 — Pre-Recording Validation Log
#
# Runs every demo step from the Module 3 recording runbook, captures the
# exact input payload and raw JSON output, and writes a structured plain-text
# log for GPT / reviewer validation before recording.
#
# Usage:
#   scripts/validate_module3.sh
#
# Output:
#   logs/module3_validation.txt

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="http://localhost:8000"
LOG="$REPO_ROOT/logs/module3_validation.txt"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

mkdir -p "$REPO_ROOT/logs"

divider() {
    printf '%0.s=' {1..72} >> "$LOG"
    echo "" >> "$LOG"
}

section() {
    echo "" >> "$LOG"
    divider
    echo "$1" >> "$LOG"
    divider
}

# ── Header ──────────────────────────────────────────────────────────────────
cat > "$LOG" <<HEADER
MODULE 3 VALIDATION LOG
=======================
Module:  Orchestrating LLM data pipelines with Apache Airflow
Clip:    Clip 4 — Demo: Triggering and monitoring an Airflow enrichment pipeline with FastAPI and DuckDB
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API
LOs:     3a, 3b, 3c, 3d

This file contains the exact input and output for every demo step.
Compare each output against the "Expected output" section to validate
that the demo will produce the correct on-screen proof before recording.

HEADER

# ── Preflight ───────────────────────────────────────────────────────────────
section "PREFLIGHT"

echo "Server health:" >> "$LOG"
curl -sf "$API/health" 2>&1 | python3 -m json.tool >> "$LOG" 2>&1 || echo "FAIL: server not running" >> "$LOG"

echo "" >> "$LOG"
echo "Resetting metrics..." >> "$LOG"
curl -sf -X POST "$API/admin/reset-metrics" > /dev/null 2>&1 && echo "OK" >> "$LOG" || echo "WARN: reset-metrics failed" >> "$LOG"

echo "Seeding knowledge base..." >> "$LOG"
curl -sf -X POST "$API/admin/seed-knowledge-base" > /dev/null 2>&1 && echo "OK" >> "$LOG" || echo "WARN: seed failed" >> "$LOG"

# ── Step 1 ──────────────────────────────────────────────────────────────────
section "STEP 1: Trigger the Airflow DAG and show pipeline execution (LO 3b, 3c)"

TRIGGER_PAYLOAD='{"batch_id": "BATCH-20240318-001", "source": "data/payloads/batch_feedback.json"}'

echo "COMMAND:" >> "$LOG"
echo '  curl -s -X POST http://localhost:8000/pipeline/trigger \' >> "$LOG"
echo '    -H "Content-Type: application/json" \' >> "$LOG"
echo "    -d '$TRIGGER_PAYLOAD'" >> "$LOG"

echo "" >> "$LOG"
echo "INPUT PAYLOAD:" >> "$LOG"
echo "$TRIGGER_PAYLOAD" | python3 -m json.tool >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s -X POST "$API/pipeline/trigger" \
    -H "Content-Type: application/json" \
    -d "$TRIGGER_PAYLOAD" \
    > "$TMPD/step1.json" 2>&1
python3 -m json.tool < "$TMPD/step1.json" >> "$LOG" 2>&1

BATCH_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_id','MISSING'))" < "$TMPD/step1.json" 2>/dev/null || echo "PARSE_ERROR")
TRIGGER_STATUS=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','MISSING'))" < "$TMPD/step1.json" 2>/dev/null || echo "PARSE_ERROR")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  batch_id: $BATCH_ID" >> "$LOG"
echo "  status:   $TRIGGER_STATUS" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  batch_id: a valid UUID or BATCH-20240318-001" >> "$LOG"
echo "  dag_id:   northwind_enrich_dag (or similar)" >> "$LOG"
echo "  status:   triggered" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Response returns HTTP 200" >> "$LOG"
echo "  [ ] batch_id is present and valid" >> "$LOG"
echo "  [ ] status = triggered" >> "$LOG"
echo "  [ ] dag_id references the enrichment DAG" >> "$LOG"

# Now run the actual batch enrichment to populate data for Steps 2-4
echo "" >> "$LOG"
echo "--- Running batch enrichment to populate data for subsequent steps ---" >> "$LOG"
curl -s -X POST "$API/pipeline/batch-enrich" \
    -H "Content-Type: application/json" \
    -d "{\"items\": $(cat "$REPO_ROOT/data/payloads/batch_feedback.json")}" \
    > "$TMPD/batch_result.json" 2>&1

REAL_BATCH_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_id','UNKNOWN'))" < "$TMPD/batch_result.json" 2>/dev/null || echo "UNKNOWN")
echo "Batch enrichment batch_id: $REAL_BATCH_ID" >> "$LOG"

# ── Step 2 ──────────────────────────────────────────────────────────────────
section "STEP 2: Show the DAG graph with static and dynamic branches (LO 3a)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s http://localhost:8000/pipeline/runs' >> "$LOG"

echo "" >> "$LOG"
echo "NOTE: The Airflow UI graph view is visual and shown in the browser." >> "$LOG"
echo "This step captures the pipeline runs data that accompanies the UI." >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (pipeline runs):" >> "$LOG"
curl -s "$API/pipeline/runs" > "$TMPD/step2.json" 2>&1
python3 -m json.tool < "$TMPD/step2.json" >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Pipeline run records showing:" >> "$LOG"
echo "    batch_id, accepted_count, rejected_count, validation_summary" >> "$LOG"
echo "  At least one run should be present from the batch enrichment above." >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] At least one pipeline run record exists" >> "$LOG"
echo "  [ ] Run record has batch_id, status, accepted, rejected fields" >> "$LOG"
echo "  [ ] Narration will contrast static reconciliation DAG (no branching) vs enrichment DAG (dynamic branch)" >> "$LOG"

# ── Step 3 ──────────────────────────────────────────────────────────────────
section "STEP 3: Examine task logs for traceability (LO 3b, 3c)"

echo "COMMAND:" >> "$LOG"
echo "  curl -s http://localhost:8000/pipeline/run/$REAL_BATCH_ID" >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (batch details):" >> "$LOG"
curl -s "$API/pipeline/run/$REAL_BATCH_ID" > "$TMPD/step3.json" 2>&1
python3 -m json.tool < "$TMPD/step3.json" >> "$LOG" 2>&1

# Extract counts
TOTAL=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_result',d).get('total', d.get('total','?')))" < "$TMPD/step3.json" 2>/dev/null || echo "?")
ACCEPTED=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_result',d).get('accepted', d.get('accepted','?')))" < "$TMPD/step3.json" 2>/dev/null || echo "?")
REJECTED=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_result',d).get('rejected', d.get('rejected','?')))" < "$TMPD/step3.json" 2>/dev/null || echo "?")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  total:    $TOTAL" >> "$LOG"
echo "  accepted: $ACCEPTED" >> "$LOG"
echo "  rejected: $REJECTED" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  batch_id: matches the enrichment run" >> "$LOG"
echo "  total:    5 (batch_feedback.json has 5 items)" >> "$LOG"
echo "  accepted: 3 (2 clearly classifiable + 1 positive)" >> "$LOG"
echo "  rejected: 2 (1 invalid product_id P-9999 + 1 ambiguous/stale)" >> "$LOG"
echo "  details:  list with each item's request_id, category, validation_status, errors" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] total = 5" >> "$LOG"
echo "  [ ] accepted + rejected = 5 (all items accounted for)" >> "$LOG"
echo "  [ ] accepted >= 2 (at least the clearly classifiable items)" >> "$LOG"
echo "  [ ] rejected >= 1 (at least the invalid product_id P-9999 item)" >> "$LOG"
echo "  [ ] Each detail has request_id, category, validation_status" >> "$LOG"

# ── Step 4 ──────────────────────────────────────────────────────────────────
section "STEP 4: Verify trusted output and quarantine tables in DuckDB (LO 3c, 3d)"

echo "COMMAND 1 (trusted):" >> "$LOG"
echo '  duckdb data/northwind.duckdb \' >> "$LOG"
echo '    "SELECT request_id, category, confidence, validation_status' >> "$LOG"
echo '     FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5"' >> "$LOG"
echo "" >> "$LOG"
echo "COMMAND 2 (quarantine):" >> "$LOG"
echo '  duckdb data/northwind.duckdb \' >> "$LOG"
echo '    "SELECT request_id, validation_errors' >> "$LOG"
echo '     FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5"' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT:" >> "$LOG"
if command -v duckdb &>/dev/null; then
    echo "--- trusted.feedback_enriched ---" >> "$LOG"
    (cd "$REPO_ROOT" && duckdb data/northwind.duckdb \
        "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5" 2>&1) >> "$LOG"
    echo "" >> "$LOG"
    echo "--- quarantine.llm_outputs ---" >> "$LOG"
    (cd "$REPO_ROOT" && duckdb data/northwind.duckdb \
        "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5" 2>&1) >> "$LOG"
else
    echo "  [duckdb CLI not available]" >> "$LOG"
fi

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Trusted table: rows with validation_status=accepted, categories assigned, confidence >= 0.75" >> "$LOG"
echo "  Quarantine table: rows with specific validation_errors, e.g.:" >> "$LOG"
echo "    - 'unknown product_id P-9999' (referential integrity)" >> "$LOG"
echo "    - 'confidence below threshold' (low confidence)" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] trusted.feedback_enriched has accepted rows with valid categories" >> "$LOG"
echo "  [ ] quarantine.llm_outputs has rejected rows with specific error messages" >> "$LOG"
echo "  [ ] Error messages are human-readable (not raw objects)" >> "$LOG"
echo "  [ ] Trusted rows have confidence >= 0.75" >> "$LOG"
echo "  [ ] Quarantine rows explain WHY they were rejected" >> "$LOG"

# ── Summary ─────────────────────────────────────────────────────────────────
section "SUMMARY"

echo "Module 3, Clip 4 validation complete." >> "$LOG"
echo "" >> "$LOG"
echo "Proof points to verify:" >> "$LOG"
echo "  1. Pipeline trigger returns status=triggered with a batch_id" >> "$LOG"
echo "  2. Pipeline runs show accepted_count and rejected_count" >> "$LOG"
echo "  3. Batch details show per-item request_id, category, validation_status, errors" >> "$LOG"
echo "  4. DuckDB trusted table has accepted rows; quarantine has rejected rows with reasons" >> "$LOG"
echo "" >> "$LOG"
echo "Additional visual proof (not captured in this log):" >> "$LOG"
echo "  - Airflow UI shows northwind_llm_enrichment DAG in success state" >> "$LOG"
echo "  - Airflow graph view shows static tasks and dynamic branch topology" >> "$LOG"
echo "  - Compare with northwind_static_reconciliation DAG (linear, no branching)" >> "$LOG"
echo "" >> "$LOG"
echo "If any checklist item fails, fix the issue before recording." >> "$LOG"

echo ""
echo "Validation log written to: $LOG"
echo "Review the file or hand it to GPT for automated verification."
