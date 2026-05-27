#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Clip 4 — Post-Demo Verification
#
# Checks that every proof point from the demo holds. Run this after
# module1-demo-run.sh to confirm the recording will show correct output.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; ERRORS=$((ERRORS + 1)); }

API="http://localhost:8000"

echo ""
printf "${BOLD}Module 1 — Demo Verification${NC}\n"
echo "========================================="
echo ""

# 1. Server healthy
if curl -sf "$API/health" >/dev/null 2>&1; then
  pass "Server is healthy"
else
  fail "Server not responding"
fi

# 2. raw.feedback has data
METRICS=$(curl -sf "$API/admin/metrics" 2>/dev/null || echo '{}')
RAW=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duckdb',{}).get('raw_feedback',0))" 2>/dev/null || echo "0")
if [[ "$RAW" -ge 10 ]]; then
  pass "raw.feedback has $RAW rows (expected >= 10)"
else
  fail "raw.feedback has $RAW rows (expected >= 10)"
fi

# 3. Enrichment returns correct values
RESPONSE=$(curl -sf "$API/enrich/feedback" \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json 2>/dev/null || echo '{}')

CATEGORY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")
CONFIDENCE=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('confidence',0))" 2>/dev/null || echo "0")
VAL_STATUS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('validation_status',''))" 2>/dev/null || echo "")
REQ_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('request_id',''))" 2>/dev/null || echo "")
DOCS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('source_doc_ids',[])))" 2>/dev/null || echo "0")

if [[ "$CATEGORY" == "product_quality" ]]; then
  pass "category = product_quality"
else
  fail "category = $CATEGORY (expected product_quality)"
fi

CONF_OK=$(python3 -c "print(int(float('$CONFIDENCE') >= 0.75))" 2>/dev/null || echo "0")
if [[ "$CONF_OK" == "1" ]]; then
  pass "confidence = $CONFIDENCE (>= 0.75)"
else
  fail "confidence = $CONFIDENCE (expected >= 0.75)"
fi

if [[ "$VAL_STATUS" == "accepted" ]]; then
  pass "validation_status = accepted"
else
  fail "validation_status = $VAL_STATUS (expected accepted)"
fi

if [[ "$DOCS" -ge 1 ]]; then
  pass "source_doc_ids has $DOCS references"
else
  fail "source_doc_ids is empty (expected >= 1)"
fi

if [[ -n "$REQ_ID" && "$REQ_ID" != "None" ]]; then
  pass "request_id = $REQ_ID"
else
  fail "request_id is missing"
fi

# 4. llm_decisions has the same request_id
DECISIONS=$(curl -sf "$API/admin/llm-decisions?limit=1" 2>/dev/null || echo '[]')
DEC_ID=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['request_id'] if d else '')" 2>/dev/null || echo "")
DEC_STATUS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['status'] if d else '')" 2>/dev/null || echo "")

if [[ "$DEC_ID" == "$REQ_ID" ]]; then
  pass "llm_decisions request_id matches enrichment response"
else
  fail "llm_decisions request_id = $DEC_ID (expected $REQ_ID)"
fi

if [[ "$DEC_STATUS" == "accepted" ]]; then
  pass "llm_decisions status = accepted"
else
  fail "llm_decisions status = $DEC_STATUS (expected accepted)"
fi

# 5. trusted.feedback_enriched has rows
METRICS2=$(curl -sf "$API/admin/metrics" 2>/dev/null || echo '{}')
TRUSTED=$(echo "$METRICS2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duckdb',{}).get('trusted_enriched',0))" 2>/dev/null || echo "0")
if [[ "$TRUSTED" -ge 1 ]]; then
  pass "trusted.feedback_enriched has $TRUSTED rows"
else
  fail "trusted.feedback_enriched has $TRUSTED rows (expected >= 1)"
fi

# 6. Determinism check — run enrichment again, category should be the same
RESPONSE2=$(curl -sf "$API/enrich/feedback" \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json 2>/dev/null || echo '{}')
CAT2=$(echo "$RESPONSE2" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")
if [[ "$CAT2" == "$CATEGORY" ]]; then
  pass "Deterministic: second call also returns category=$CAT2"
else
  fail "Non-deterministic: first=$CATEGORY, second=$CAT2"
fi

# Summary
echo ""
echo "========================================="
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}${BOLD}All checks passed. Safe to record.${NC}\n"
else
  printf "${RED}${BOLD}$ERRORS check(s) failed. Fix before recording.${NC}\n"
fi
echo "========================================="
echo ""

exit $ERRORS
