#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Clip 4 — Post-Demo Verification
#
# READ-ONLY checks against the current server state. Does NOT call any
# enrichment endpoints — it only reads what module1-demo-run.sh produced.
# Safe to run multiple times without creating duplicate rows.
#
# Run after module1-demo-run.sh to confirm the recording shows correct output.
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
printf "${BOLD}Module 1 — Demo Verification (read-only)${NC}\n"
echo "========================================="
echo ""

# 1. Server healthy
if curl -sf "$API/health" >/dev/null 2>&1; then
  pass "Server is healthy"
else
  fail "Server not responding"
fi

# 2. raw.feedback has seed data
METRICS=$(curl -sf "$API/admin/metrics" 2>/dev/null || echo '{}')
RAW=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duckdb',{}).get('raw_feedback',0))" 2>/dev/null || echo "0")
if [[ "$RAW" -eq 10 ]]; then
  pass "raw.feedback has $RAW rows (seed data intact)"
else
  fail "raw.feedback has $RAW rows (expected 10)"
fi

# 3. trusted.feedback_enriched has exactly 1 row (from the demo run)
TRUSTED=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duckdb',{}).get('trusted_enriched',0))" 2>/dev/null || echo "0")
if [[ "$TRUSTED" -eq 1 ]]; then
  pass "trusted.feedback_enriched has $TRUSTED row (exactly 1 from demo)"
else
  fail "trusted.feedback_enriched has $TRUSTED rows (expected exactly 1)"
fi

# 4. llm_decisions has exactly 1 record
DECISIONS=$(curl -sf "$API/admin/llm-decisions?limit=10" 2>/dev/null || echo '[]')
DEC_COUNT=$(echo "$DECISIONS" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
if [[ "$DEC_COUNT" -eq 1 ]]; then
  pass "llm_decisions has $DEC_COUNT record (exactly 1 from demo)"
else
  fail "llm_decisions has $DEC_COUNT records (expected exactly 1)"
fi

# 5. The decision record has correct values
DEC_CATEGORY=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('llm_output',{}).get('category','') if d else '')" 2>/dev/null || echo "")
DEC_STATUS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('status','') if d else '')" 2>/dev/null || echo "")
DEC_ENDPOINT=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0].get('endpoint','') if d else '')" 2>/dev/null || echo "")

if [[ "$DEC_CATEGORY" == "product_quality" ]]; then
  pass "Decision category = product_quality"
else
  fail "Decision category = $DEC_CATEGORY (expected product_quality)"
fi

if [[ "$DEC_STATUS" == "accepted" ]]; then
  pass "Decision status = accepted"
else
  fail "Decision status = $DEC_STATUS (expected accepted)"
fi

if [[ "$DEC_ENDPOINT" == "feedback" ]]; then
  pass "Decision endpoint = feedback"
else
  fail "Decision endpoint = $DEC_ENDPOINT (expected feedback)"
fi

# 6. No quarantine rows (the demo payload should always pass validation)
QUARANTINE=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duckdb',{}).get('quarantine_outputs',0))" 2>/dev/null || echo "0")
if [[ "$QUARANTINE" -eq 0 ]]; then
  pass "quarantine.llm_outputs has 0 rows (no rejections)"
else
  fail "quarantine.llm_outputs has $QUARANTINE rows (expected 0)"
fi

# Summary
echo ""
echo "========================================="
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}${BOLD}All checks passed. Safe to record.${NC}\n"
else
  printf "${RED}${BOLD}$ERRORS check(s) failed. Run module1-demo-reset.sh and try again.${NC}\n"
fi
echo "========================================="
echo ""

exit $ERRORS
