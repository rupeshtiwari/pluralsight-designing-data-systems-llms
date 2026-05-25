#!/usr/bin/env bash
set -euo pipefail
#
# Module 1 — Pre-Recording Validation Log
#
# Runs every demo step from the Module 1 recording runbook, captures the
# exact input payload and raw JSON output, and writes a structured plain-text
# log that you can hand to GPT (or a reviewer) to verify every claim in the
# runbook before you start recording.
#
# Usage:
#   scripts/validate_module1.sh
#
# Output:
#   logs/module1_validation.txt

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="http://localhost:8000"
LOG="$REPO_ROOT/logs/module1_validation.txt"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

mkdir -p "$REPO_ROOT/logs"

# ── Helper ──────────────────────────────────────────────────────────────────
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
MODULE 1 VALIDATION LOG
=======================
Module:  Designing LLM boundaries in data pipelines
Clip:    Clip 4 — Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API
LOs:     1a, 1b, 1d

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
section "STEP 1: Show DuckDB raw feedback input (LO 1a)"

echo "COMMAND:" >> "$LOG"
echo '  duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback"' >> "$LOG"
echo "" >> "$LOG"

echo "ACTUAL OUTPUT:" >> "$LOG"
if command -v duckdb &>/dev/null; then
    (cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback" 2>&1) >> "$LOG"
else
    echo "  [duckdb CLI not available — run inside Docker or install duckdb]" >> "$LOG"
fi

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Row count = 10 (seed data has 10 feedback records)" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Row count is 10" >> "$LOG"
echo "  [ ] Table raw.feedback exists and is queryable" >> "$LOG"

# ── Step 2 ──────────────────────────────────────────────────────────────────
section "STEP 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s http://localhost:8000/enrich/feedback \' >> "$LOG"
echo '    -H "Content-Type: application/json" \' >> "$LOG"
echo '    -d @data/payloads/feedback_enrich.json' >> "$LOG"

echo "" >> "$LOG"
echo "INPUT PAYLOAD (data/payloads/feedback_enrich.json):" >> "$LOG"
cat "$REPO_ROOT/data/payloads/feedback_enrich.json" >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s "$API/enrich/feedback" \
    -H "Content-Type: application/json" \
    -d @"$REPO_ROOT/data/payloads/feedback_enrich.json" \
    > "$TMPD/step2.json" 2>&1
python3 -m json.tool < "$TMPD/step2.json" >> "$LOG" 2>&1

# Extract key fields for checklist
REQ_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('request_id','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
CATEGORY=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('category','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
CONFIDENCE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('confidence','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
SOURCE_DOCS=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('source_doc_ids','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
VAL_STATUS=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('validation_status','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  request_id:        a valid UUID" >> "$LOG"
echo "  category:          product_quality" >> "$LOG"
echo "  summary:           one-sentence summary mentioning cracked lid / grinding noise" >> "$LOG"
echo "  confidence:        >= 0.75" >> "$LOG"
echo "  source_doc_ids:    should include DOC-001 (product quality) and/or DOC-007 (feedback taxonomy)" >> "$LOG"
echo "  validation_status: accepted" >> "$LOG"

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  request_id:        $REQ_ID" >> "$LOG"
echo "  category:          $CATEGORY" >> "$LOG"
echo "  confidence:        $CONFIDENCE" >> "$LOG"
echo "  source_doc_ids:    $SOURCE_DOCS" >> "$LOG"
echo "  validation_status: $VAL_STATUS" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] request_id is a valid UUID (not empty, not MISSING)" >> "$LOG"
echo "  [ ] category = product_quality (feedback mentions cracked lid and grinding noise)" >> "$LOG"
echo "  [ ] confidence >= 0.75" >> "$LOG"
echo "  [ ] source_doc_ids contains at least one of DOC-001, DOC-007" >> "$LOG"
echo "  [ ] validation_status = accepted" >> "$LOG"
echo "  [ ] summary references the defective blender feedback" >> "$LOG"

# ── Step 3 ──────────────────────────────────────────────────────────────────
section "STEP 3: Verify the decision was recorded in PostgreSQL (LO 1b, 1d)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s http://localhost:8000/agent/decisions' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s "$API/agent/decisions" > "$TMPD/step3.json" 2>&1
python3 -m json.tool < "$TMPD/step3.json" >> "$LOG" 2>&1

echo "" >> "$LOG"
echo "CROSS-REFERENCE:" >> "$LOG"
echo "  request_id from Step 2: $REQ_ID" >> "$LOG"
if grep -q "$REQ_ID" "$TMPD/step3.json" 2>/dev/null; then
    echo "  FOUND in decisions output: YES" >> "$LOG"
else
    echo "  FOUND in decisions output: NO (may be stored in llm_decisions, not agent_decisions)" >> "$LOG"
fi

echo "" >> "$LOG"
echo "ALTERNATIVE COMMAND (direct psql):" >> "$LOG"
echo '  docker exec northwind-postgres psql -U northwind -c \' >> "$LOG"
echo '    "SELECT request_id, endpoint, category, confidence, validation_status, decision' >> "$LOG"
echo '     FROM llm_decisions ORDER BY created_at DESC LIMIT 3"' >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  A decision record showing:" >> "$LOG"
echo "    request_id = $REQ_ID (same as Step 2)" >> "$LOG"
echo "    endpoint = feedback" >> "$LOG"
echo "    validation_status = accepted" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Decision record exists for request_id $REQ_ID" >> "$LOG"
echo "  [ ] endpoint = feedback" >> "$LOG"
echo "  [ ] validation_status = accepted" >> "$LOG"
echo "  [ ] request_id matches Step 2 (proves traceability)" >> "$LOG"

# ── Step 4 ──────────────────────────────────────────────────────────────────
section "STEP 4: Verify trusted output table received the enriched record (LO 1d)"

echo "COMMAND 1 (row count):" >> "$LOG"
echo '  duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM trusted.feedback_enriched"' >> "$LOG"
echo "" >> "$LOG"
echo "COMMAND 2 (details):" >> "$LOG"
echo '  duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status' >> "$LOG"
echo '    FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3"' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT:" >> "$LOG"
if command -v duckdb &>/dev/null; then
    echo "Row count:" >> "$LOG"
    (cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM trusted.feedback_enriched" 2>&1) >> "$LOG"
    echo "" >> "$LOG"
    echo "Recent records:" >> "$LOG"
    (cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3" 2>&1) >> "$LOG"
else
    echo "  [duckdb CLI not available]" >> "$LOG"
fi

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Row count >= 1 (at least the record from Step 2)" >> "$LOG"
echo "  Most recent record has:" >> "$LOG"
echo "    request_id = $REQ_ID" >> "$LOG"
echo "    category = product_quality" >> "$LOG"
echo "    confidence >= 0.75" >> "$LOG"
echo "    validation_status = accepted" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] trusted.feedback_enriched has >= 1 row" >> "$LOG"
echo "  [ ] Most recent request_id matches Step 2: $REQ_ID" >> "$LOG"
echo "  [ ] category = product_quality" >> "$LOG"
echo "  [ ] confidence >= 0.75" >> "$LOG"
echo "  [ ] validation_status = accepted" >> "$LOG"

# ── Summary ─────────────────────────────────────────────────────────────────
section "SUMMARY"

echo "Module 1, Clip 4 validation complete." >> "$LOG"
echo "" >> "$LOG"
echo "Proof points to verify:" >> "$LOG"
echo "  1. DuckDB raw.feedback has 10 input records" >> "$LOG"
echo "  2. FastAPI returns category=product_quality, confidence>=0.75, validation_status=accepted" >> "$LOG"
echo "  3. PostgreSQL llm_decisions has a matching request_id with accepted status" >> "$LOG"
echo "  4. DuckDB trusted.feedback_enriched has the enriched record" >> "$LOG"
echo "" >> "$LOG"
echo "If any checklist item fails, fix the issue before recording." >> "$LOG"

echo ""
echo "Validation log written to: $LOG"
echo "Review the file or hand it to GPT for automated verification."
