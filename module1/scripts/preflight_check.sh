#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module1/preflight_log.txt.
#
# Use the log to verify that demo steps align with the learning objectives.
#
# Usage:
#   module1/scripts/preflight_check.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="$PROJECT_ROOT/module1/preflight_log.txt"
API="http://localhost:8000"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; ERRORS=$((ERRORS + 1)); }
info() { printf "${YELLOW}[....]${NC} %s\n" "$1"; }

# ── Start log ───────────────────────────────────────────────────────────────
cat > "$LOG" <<HEADER
================================================================================
MODULE 1 — CLIP 4 PREFLIGHT LOG
================================================================================
Demo:    Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API

Learning objectives:
  1a  Demonstrate identifying where LLMs fit within data pipelines
  1b  Define system boundaries between deterministic and AI-driven components
  1d  Demonstrate designing data flows that incorporate LLM outputs

HEADER

log() { echo "$1" >> "$LOG"; }
log_divider() {
  log ""
  log "================================================================================"
  log "$1"
  log "================================================================================"
  log ""
}

echo ""
printf "${BOLD}Module 1 Clip 4 — Preflight Check${NC}\n"
echo "========================================="
echo ""

# ── Server check ────────────────────────────────────────────────────────────
info "Checking server health..."
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail "Server not running at $API. Run: ./scripts/module1-demo-reset.sh"
  echo "Server not running" >> "$LOG"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# Seed knowledge base
curl -sf -X POST "$API/admin/seed-knowledge-base" >/dev/null 2>&1
log "Knowledge base: seeded"

# ── STEP 1 (LO 1a) ─────────────────────────────────────────────────────────
log_divider "STEP 1: Show DuckDB raw feedback input (LO 1a)"

CMD1='curl -s http://localhost:8000/admin/metrics | python3 -m json.tool'
log "COMMAND:"
log "  $CMD1"
log ""

METRICS=$(curl -sf "$API/admin/metrics")
echo "$METRICS" | python3 -m json.tool > "$TMPD/step1.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

RAW_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['raw_feedback'])")
TRUSTED_BEFORE=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")

log "EXTRACTED VALUES:"
log "  raw_feedback:     $RAW_COUNT"
log "  trusted_enriched: $TRUSTED_BEFORE"
log ""

log "LO COVERAGE:"
log "  1a — Source data exists in the deterministic pipeline layer (raw.feedback = $RAW_COUNT)"
log ""

if [[ "$RAW_COUNT" -eq 10 ]]; then
  pass "Step 1: raw.feedback = $RAW_COUNT"
  log "RESULT: PASS"
else
  fail "Step 1: raw.feedback = $RAW_COUNT (expected 10)"
  log "RESULT: FAIL (expected 10)"
fi

if [[ "$TRUSTED_BEFORE" -eq 0 ]]; then
  pass "Step 1: trusted.enriched = $TRUSTED_BEFORE (clean baseline)"
  log "RESULT: PASS (baseline clean)"
else
  fail "Step 1: trusted.enriched = $TRUSTED_BEFORE (expected 0 — run module1-demo-reset.sh)"
  log "RESULT: FAIL (expected 0)"
fi

# ── STEP 2 (LO 1a, 1b) ─────────────────────────────────────────────────────
log_divider "STEP 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)"

CMD2='curl -s http://localhost:8000/enrich/feedback -H "Content-Type: application/json" -d @data/payloads/feedback_enrich.json | python3 -m json.tool'
log "COMMAND:"
log "  $CMD2"
log ""

log "INPUT PAYLOAD (data/payloads/feedback_enrich.json):"
cat "$PROJECT_ROOT/data/payloads/feedback_enrich.json" >> "$LOG"
log ""

RESPONSE=$(curl -sf "$API/enrich/feedback" \
  -H "Content-Type: application/json" \
  -d @"$PROJECT_ROOT/data/payloads/feedback_enrich.json")
echo "$RESPONSE" | python3 -m json.tool > "$TMPD/step2.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

REQUEST_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['request_id'])")
CATEGORY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['category'])")
CONFIDENCE=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['confidence'])")
SOURCE_DOCS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(', '.join(json.load(sys.stdin)['source_doc_ids']))")
VAL_STATUS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['validation_status'])")
SUMMARY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary'])")

log "EXTRACTED VALUES:"
log "  request_id:        $REQUEST_ID"
log "  category:          $CATEGORY"
log "  confidence:        $CONFIDENCE"
log "  source_doc_ids:    $SOURCE_DOCS"
log "  validation_status: $VAL_STATUS"
log "  summary:           $SUMMARY"
log ""

log "LO COVERAGE:"
log "  1a — LLM enrichment identifies where AI fits: classification of feedback text"
log "  1b — Boundary contract enforced: structured JSON output with validation status"
log ""

if [[ "$CATEGORY" == "product_quality" ]]; then
  pass "Step 2: category = product_quality"
  log "RESULT: PASS — category = product_quality"
else
  fail "Step 2: category = $CATEGORY (expected product_quality)"
  log "RESULT: FAIL — category = $CATEGORY"
fi

CONF_OK=$(python3 -c "print(int(float('$CONFIDENCE') >= 0.75))")
if [[ "$CONF_OK" == "1" ]]; then
  pass "Step 2: confidence = $CONFIDENCE (>= 0.75)"
  log "RESULT: PASS — confidence = $CONFIDENCE"
else
  fail "Step 2: confidence = $CONFIDENCE (< 0.75)"
  log "RESULT: FAIL — confidence below threshold"
fi

if [[ "$VAL_STATUS" == "accepted" ]]; then
  pass "Step 2: validation_status = accepted"
  log "RESULT: PASS — accepted"
else
  fail "Step 2: validation_status = $VAL_STATUS (expected accepted)"
  log "RESULT: FAIL — $VAL_STATUS"
fi

# ── STEP 3 (LO 1b, 1d) ─────────────────────────────────────────────────────
log_divider "STEP 3: Verify the decision was stored in llm_decisions (LO 1b, 1d)"

CMD3='curl -s http://localhost:8000/admin/llm-decisions?limit=1 | python3 -m json.tool'
log "COMMAND:"
log "  $CMD3"
log ""

DECISIONS=$(curl -sf "$API/admin/llm-decisions?limit=1")
echo "$DECISIONS" | python3 -m json.tool > "$TMPD/step3.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step3.json" >> "$LOG"
log ""

DEC_REQ_ID=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['request_id'] if d else 'MISSING')")
DEC_STATUS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['status'] if d else 'MISSING')")
DEC_ENDPOINT=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['endpoint'] if d else 'MISSING')")
DEC_TOKENS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"prompt={d[0].get('prompt_tokens',0)} completion={d[0].get('completion_tokens',0)} total={d[0].get('total_tokens',0)}\") if d else print('MISSING')")

log "EXTRACTED VALUES:"
log "  request_id: $DEC_REQ_ID"
log "  endpoint:   $DEC_ENDPOINT"
log "  status:     $DEC_STATUS"
log "  tokens:     $DEC_TOKENS"
log ""

log "LO COVERAGE:"
log "  1b — System boundary: every LLM call creates a traceable decision record"
log "  1d — Data flow: request_id links enrichment output to decision store"
log ""

if [[ "$DEC_REQ_ID" == "$REQUEST_ID" ]]; then
  pass "Step 3: request_id matches Step 2"
  log "RESULT: PASS — request_id $DEC_REQ_ID matches Step 2"
else
  fail "Step 3: request_id = $DEC_REQ_ID (expected $REQUEST_ID)"
  log "RESULT: FAIL — request_id mismatch"
fi

if [[ "$DEC_STATUS" == "accepted" ]]; then
  pass "Step 3: status = accepted"
  log "RESULT: PASS — status = accepted"
else
  fail "Step 3: status = $DEC_STATUS (expected accepted)"
  log "RESULT: FAIL — status = $DEC_STATUS"
fi

# ── STEP 4 (LO 1d) ─────────────────────────────────────────────────────────
log_divider "STEP 4: Verify trusted output table received the enriched record (LO 1d)"

CMD4='curl -s http://localhost:8000/admin/metrics | python3 -m json.tool'
log "COMMAND:"
log "  $CMD4"
log ""

METRICS_AFTER=$(curl -sf "$API/admin/metrics")
echo "$METRICS_AFTER" | python3 -m json.tool > "$TMPD/step4.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

TRUSTED_AFTER=$(echo "$METRICS_AFTER" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
DELTA=$((TRUSTED_AFTER - TRUSTED_BEFORE))

log "EXTRACTED VALUES:"
log "  trusted_enriched before: $TRUSTED_BEFORE"
log "  trusted_enriched after:  $TRUSTED_AFTER"
log "  delta:                   +$DELTA"
log ""

log "LO COVERAGE:"
log "  1d — Data flow complete: validated LLM output promoted to trusted table (+$DELTA row)"
log ""

if [[ "$DELTA" -gt 0 ]]; then
  pass "Step 4: trusted.enriched grew by +$DELTA"
  log "RESULT: PASS — delta = +$DELTA"
else
  fail "Step 4: trusted.enriched did not grow (delta = $DELTA)"
  log "RESULT: FAIL — no growth"
fi

# ── LO COVERAGE SUMMARY ────────────────────────────────────────────────────
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 1a | Step 1, Step 2 | raw.feedback=$RAW_COUNT shows source data; enrichment classifies as product_quality |"
log "| 1b | Step 2, Step 3 | Structured JSON contract with validation; traceable decision record |"
log "| 1d | Step 3, Step 4 | request_id links enrichment to decision; trusted table grew by +$DELTA |"

log ""
log "All 3 learning objectives (1a, 1b, 1d) are covered by the 4 demo steps."

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}${BOLD}All preflight checks passed.${NC}\n"
  log ""
  log "VERDICT: ALL CHECKS PASSED"
else
  printf "${RED}${BOLD}$ERRORS check(s) failed.${NC}\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
fi
echo "========================================="
echo ""
echo "Log saved to: module1/preflight_log.txt"
echo ""

exit $ERRORS
