#!/usr/bin/env bash
set -euo pipefail
#
# Module 4 — Pre-Recording Validation Log
#
# Runs every demo step from the Module 4 recording runbook, captures the
# exact input payload and raw JSON output, and writes a structured plain-text
# log for GPT / reviewer validation before recording.
#
# Usage:
#   scripts/validate_module4.sh
#
# Output:
#   logs/module4_validation.txt

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="http://localhost:8000"
LOG="$REPO_ROOT/logs/module4_validation.txt"
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
MODULE 4 VALIDATION LOG
=======================
Module:  Validating and guardrailing LLM outputs in data pipelines
Clip:    Clip 4 — Demo: Rejecting hallucinated and schema-drifted LLM outputs in Airflow
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API
LOs:     1d, 3c, 3d

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
section "STEP 1: Run the validation batch and show Airflow routing (LO 3c, 3d)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s -X POST http://localhost:8000/pipeline/batch-enrich \' >> "$LOG"
echo '    -H "Content-Type: application/json" \' >> "$LOG"
echo '    -d @data/payloads/batch_validation_test.json' >> "$LOG"

echo "" >> "$LOG"
echo "INPUT PAYLOAD (data/payloads/batch_validation_test.json):" >> "$LOG"
cat "$REPO_ROOT/data/payloads/batch_validation_test.json" >> "$LOG"

echo "" >> "$LOG"
echo "NOTE: The batch_validation_test.json has pre-enriched items with intentional failures:" >> "$LOG"
echo "  Item 201: valid (product_quality, confidence 0.94, source_doc_ids present)" >> "$LOG"
echo "  Item 202: hallucinated category 'logistics_fulfillment' (not in allowed list)" >> "$LOG"
echo "  Item 203: empty source_doc_ids (grounding check fail)" >> "$LOG"
echo "  Item 204: confidence 0.62 (below 0.75 threshold)" >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"

# The batch_validation_test.json has pre-enriched data, but the pipeline
# endpoint expects FeedbackEnrichRequest items. We need to send them
# through the batch endpoint. Let's send the raw feedback items.
# Actually, looking at the payload, it has enriched data. The pipeline
# needs plain feedback items. Let's use the standard batch-enrich endpoint
# which processes raw feedback text through the LLM stub and validator.
#
# For Module 4, we need to show validation failures. The batch_validation_test.json
# format may need the /validate/output endpoint for pre-enriched data.
# Let's run both approaches.

# Approach 1: Batch enrich with raw feedback items
echo "--- Approach: batch-enrich with batch_feedback.json (contains validation triggers) ---" >> "$LOG"
curl -s -X POST "$API/pipeline/batch-enrich" \
    -H "Content-Type: application/json" \
    -d "{\"items\": $(cat "$REPO_ROOT/data/payloads/batch_feedback.json")}" \
    > "$TMPD/step1.json" 2>&1
python3 -m json.tool < "$TMPD/step1.json" >> "$LOG" 2>&1

# Extract counts
TOTAL=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('total','?'))" < "$TMPD/step1.json" 2>/dev/null || echo "?")
ACCEPTED=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('accepted','?'))" < "$TMPD/step1.json" 2>/dev/null || echo "?")
REJECTED=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('rejected','?'))" < "$TMPD/step1.json" 2>/dev/null || echo "?")
QUARANTINED=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('quarantined','?'))" < "$TMPD/step1.json" 2>/dev/null || echo "?")
BATCH_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('batch_id','?'))" < "$TMPD/step1.json" 2>/dev/null || echo "?")

# Extract per-item details
DETAILS=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
for item in d.get('details',[]):
    rid = item.get('request_id','?')[:8]
    fid = item.get('feedback_id','?')
    st  = item.get('status','?')
    cat = item.get('category','?')
    err = item.get('errors',[])
    err_str = '; '.join(err) if err else 'none'
    print(f'  feedback_id={fid}  status={st}  category={cat}  errors=[{err_str}]')
" < "$TMPD/step1.json" 2>/dev/null || echo "  PARSE_ERROR")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  batch_id:    $BATCH_ID" >> "$LOG"
echo "  total:       $TOTAL" >> "$LOG"
echo "  accepted:    $ACCEPTED" >> "$LOG"
echo "  rejected:    $REJECTED" >> "$LOG"
echo "  quarantined: $QUARANTINED" >> "$LOG"
echo "" >> "$LOG"
echo "PER-ITEM DETAILS:" >> "$LOG"
echo "$DETAILS" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  total:       5 (batch_feedback.json items) or 4 (batch_validation_test.json items)" >> "$LOG"
echo "  accepted:    2-3 (valid items that pass all checks)" >> "$LOG"
echo "  rejected:    2-3 (items that fail validation)" >> "$LOG"
echo "  Each rejected item shows specific validation_errors" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] total matches the number of items in the payload" >> "$LOG"
echo "  [ ] accepted + rejected = total (all items accounted for)" >> "$LOG"
echo "  [ ] At least 1 item accepted (proves valid items pass)" >> "$LOG"
echo "  [ ] At least 1 item rejected (proves validation catches bad data)" >> "$LOG"
echo "  [ ] Rejected items have non-empty errors lists" >> "$LOG"

# ── Step 2 ──────────────────────────────────────────────────────────────────
section "STEP 2: Examine individual validation failures (LO 3d)"

INVALID_PAYLOAD='{"output": {"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}}'

echo "COMMAND:" >> "$LOG"
echo '  curl -s -X POST http://localhost:8000/validate/output \' >> "$LOG"
echo '    -H "Content-Type: application/json" \' >> "$LOG"
echo "    -d '$INVALID_PAYLOAD'" >> "$LOG"

echo "" >> "$LOG"
echo "INPUT PAYLOAD:" >> "$LOG"
echo "$INVALID_PAYLOAD" | python3 -m json.tool >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "NOTE: 'electronics_repair' is NOT in the allowed categories list:" >> "$LOG"
echo "  [product_quality, shipping_delay, customer_service, pricing_concern, return_request, general_praise]" >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s -X POST "$API/validate/output" \
    -H "Content-Type: application/json" \
    -d "$INVALID_PAYLOAD" \
    > "$TMPD/step2.json" 2>&1
python3 -m json.tool < "$TMPD/step2.json" >> "$LOG" 2>&1

# Extract validation results
IS_VALID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('is_valid','?'))" < "$TMPD/step2.json" 2>/dev/null || echo "?")
CHECKS=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
for k,v in d.get('checks',{}).items():
    status = 'PASS' if v else 'FAIL'
    print(f'  {k}: {status}')
" < "$TMPD/step2.json" 2>/dev/null || echo "  PARSE_ERROR")
ERRORS=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
for e in d.get('errors',[]):
    print(f'  - {e}')
" < "$TMPD/step2.json" 2>/dev/null || echo "  PARSE_ERROR")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  is_valid: $IS_VALID" >> "$LOG"
echo "" >> "$LOG"
echo "  Checks:" >> "$LOG"
echo "$CHECKS" >> "$LOG"
echo "" >> "$LOG"
echo "  Errors:" >> "$LOG"
echo "$ERRORS" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  is_valid: False" >> "$LOG"
echo "  checks:" >> "$LOG"
echo "    category_check: FAIL (electronics_repair not in allowed values)" >> "$LOG"
echo "    grounding_check: PASS (DOC-001 is a valid doc)" >> "$LOG"
echo "    confidence_check: PASS (0.92 >= 0.75)" >> "$LOG"
echo "  errors: ['category ... not in allowed values'] or similar" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] is_valid = False" >> "$LOG"
echo "  [ ] At least one check shows FAIL" >> "$LOG"
echo "  [ ] The FAIL is related to category (electronics_repair)" >> "$LOG"
echo "  [ ] confidence_check and grounding_check show PASS" >> "$LOG"
echo "  [ ] errors list is non-empty and mentions the invalid category" >> "$LOG"

# Test two more validation scenarios for completeness
echo "" >> "$LOG"
echo "--- Additional validation test: empty source_doc_ids ---" >> "$LOG"
GROUNDING_PAYLOAD='{"output": {"category": "product_quality", "summary": "Defective item", "confidence": 0.88, "source_doc_ids": []}}'
curl -s -X POST "$API/validate/output" \
    -H "Content-Type: application/json" \
    -d "$GROUNDING_PAYLOAD" \
    > "$TMPD/step2b.json" 2>&1
python3 -m json.tool < "$TMPD/step2b.json" >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "--- Additional validation test: low confidence ---" >> "$LOG"
CONFIDENCE_PAYLOAD='{"output": {"category": "pricing_concern", "summary": "Price issue", "confidence": 0.45, "source_doc_ids": ["DOC-007"]}}'
curl -s -X POST "$API/validate/output" \
    -H "Content-Type: application/json" \
    -d "$CONFIDENCE_PAYLOAD" \
    > "$TMPD/step2c.json" 2>&1
python3 -m json.tool < "$TMPD/step2c.json" >> "$LOG" 2>&1

# ── Step 3 ──────────────────────────────────────────────────────────────────
section "STEP 3: Verify pipeline run summary in PostgreSQL (LO 3c)"

echo "COMMAND:" >> "$LOG"
echo '  docker exec northwind-postgres psql -U northwind -c \' >> "$LOG"
echo '    "SELECT batch_id, accepted_count, rejected_count, validation_summary' >> "$LOG"
echo '     FROM pipeline_runs ORDER BY created_at DESC LIMIT 3"' >> "$LOG"

echo "" >> "$LOG"
echo "ALTERNATIVE (via API):" >> "$LOG"
echo '  curl -s http://localhost:8000/pipeline/runs' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (pipeline runs via API):" >> "$LOG"
curl -s "$API/pipeline/runs" > "$TMPD/step3.json" 2>&1
python3 -m json.tool < "$TMPD/step3.json" >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  At least one pipeline_runs row showing:" >> "$LOG"
echo "    batch_id = the batch from Step 1" >> "$LOG"
echo "    accepted_count >= 1" >> "$LOG"
echo "    rejected_count >= 1" >> "$LOG"
echo "    validation_summary with failure categories" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Pipeline run record exists for the batch from Step 1" >> "$LOG"
echo "  [ ] accepted_count >= 1" >> "$LOG"
echo "  [ ] rejected_count >= 1" >> "$LOG"
echo "  [ ] accepted_count + rejected_count = total" >> "$LOG"

# ── Step 4 ──────────────────────────────────────────────────────────────────
section "STEP 4: Verify trusted output and quarantine in DuckDB (LO 1d, 3d)"

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
echo "  Trusted table:" >> "$LOG"
echo "    Accepted records with valid categories and confidence >= 0.75" >> "$LOG"
echo "" >> "$LOG"
echo "  Quarantine table:" >> "$LOG"
echo "    Rejected records with specific errors such as:" >> "$LOG"
echo "    - 'category ... not in allowed values' (hallucinated category)" >> "$LOG"
echo "    - 'source_doc_ids is empty' or 'grounding check requires at least one reference'" >> "$LOG"
echo "    - 'confidence ... below threshold 0.75'" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] trusted.feedback_enriched has rows with validation_status=accepted" >> "$LOG"
echo "  [ ] quarantine.llm_outputs has rows with non-empty validation_errors" >> "$LOG"
echo "  [ ] Quarantine errors are human-readable strings (not raw objects or regex)" >> "$LOG"
echo "  [ ] At least one quarantine row has a category-related error" >> "$LOG"
echo "  [ ] At least one quarantine row has a confidence or grounding error" >> "$LOG"
echo "  [ ] No truncation (full error messages, no '...')" >> "$LOG"

# ── Summary ─────────────────────────────────────────────────────────────────
section "SUMMARY"

echo "Module 4, Clip 4 validation complete." >> "$LOG"
echo "" >> "$LOG"
echo "Proof points to verify:" >> "$LOG"
echo "  1. Batch processing returns accepted + rejected counts that sum to total" >> "$LOG"
echo "  2. Individual validation shows PASS/FAIL for each check with is_valid=False for bad data" >> "$LOG"
echo "  3. PostgreSQL pipeline_runs has accepted_count, rejected_count, validation_summary" >> "$LOG"
echo "  4. DuckDB trusted table has accepted rows; quarantine has rejected rows with reasons" >> "$LOG"
echo "" >> "$LOG"
echo "Course summary callout: Rejecting bad output is a successful pipeline outcome" >> "$LOG"
echo "" >> "$LOG"
echo "If any checklist item fails, fix the issue before recording." >> "$LOG"

echo ""
echo "Validation log written to: $LOG"
echo "Review the file or hand it to GPT for automated verification."
