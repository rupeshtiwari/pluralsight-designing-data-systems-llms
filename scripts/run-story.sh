#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Quick demo validation: run the first few commands to prove the system works.
# No tmux required. Suitable for students to verify their setup.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; }
hdr()  { printf "\n${BOLD}── %s${NC}\n" "$1"; }
ERRORS=0

echo ""
echo "========================================="
echo " NorthWind Markets — Demo Validation"
echo "========================================="

# ── 1. Health check ──────────────────────────────────────────────────────────
hdr "1. API health check"

echo '$ curl -s http://localhost:8000/health | python3 -m json.tool'
HEALTH=$(curl -sf http://localhost:8000/health 2>&1) || true

if [[ -n "$HEALTH" ]]; then
  echo "$HEALTH" | python3 -m json.tool 2>/dev/null || echo "$HEALTH"
  ok "FastAPI is healthy"
else
  fail "FastAPI not responding. Run: ./scripts/demo-up.sh"
  ERRORS=$((ERRORS + 1))
fi

# ── 2. DuckDB raw data ──────────────────────────────────────────────────────
hdr "2. DuckDB raw feedback count"

DB="$PROJECT_ROOT/data/northwind.duckdb"

if command -v duckdb >/dev/null 2>&1 && [[ -f "$DB" ]]; then
  echo '$ duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback"'
  RESULT=$(duckdb "$DB" "SELECT count(*) as row_count FROM raw.feedback" 2>&1)
  echo "$RESULT"

  COUNT=$(echo "$RESULT" | grep -oE '[0-9]+' | head -1)
  if [[ -n "$COUNT" && "$COUNT" -gt 0 ]]; then
    ok "raw.feedback has $COUNT rows"
  else
    fail "raw.feedback is empty. Run: python scripts/seed-data.py"
    ERRORS=$((ERRORS + 1))
  fi
else
  if ! command -v duckdb >/dev/null 2>&1; then
    fail "duckdb CLI not found. Install from https://duckdb.org/docs/installation/"
    ERRORS=$((ERRORS + 1))
  else
    fail "Database file not found at $DB. Run: python scripts/seed-data.py"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── 3. Feedback enrichment ───────────────────────────────────────────────────
hdr "3. Feedback enrichment"

echo '$ curl -s http://localhost:8000/enrich/feedback -H "Content-Type: application/json" -d @data/payloads/feedback_enrich.json'
ENRICH=$(curl -sf http://localhost:8000/enrich/feedback \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json 2>&1) || true

if [[ -n "$ENRICH" ]]; then
  echo "$ENRICH" | python3 -m json.tool 2>/dev/null || echo "$ENRICH"

  CATEGORY=$(echo "$ENRICH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('category',''))" 2>/dev/null || echo "")
  STATUS=$(echo "$ENRICH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('validation_status',''))" 2>/dev/null || echo "")

  if [[ "$STATUS" == "accepted" ]]; then
    ok "Enrichment returned category=$CATEGORY, validation_status=$STATUS"
  else
    fail "Enrichment returned unexpected status: $STATUS"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "Enrichment endpoint failed"
  ERRORS=$((ERRORS + 1))
fi

# ── 4. Agent triage ──────────────────────────────────────────────────────────
hdr "4. Agent triage"

echo '$ curl -s http://localhost:8000/agent/triage -H "Content-Type: application/json" -d @data/payloads/anomaly_triage.json'
TRIAGE=$(curl -sf http://localhost:8000/agent/triage \
  -H "Content-Type: application/json" \
  -d @data/payloads/anomaly_triage.json 2>&1) || true

if [[ -n "$TRIAGE" ]]; then
  echo "$TRIAGE" | python3 -m json.tool 2>/dev/null || echo "$TRIAGE"

  SEVERITY=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('severity',''))" 2>/dev/null || echo "")
  REVIEW=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('review_required',''))" 2>/dev/null || echo "")

  if [[ "$SEVERITY" == "high" && "$REVIEW" == "True" ]]; then
    ok "Triage returned severity=$SEVERITY, review_required=$REVIEW"
  else
    fail "Triage returned unexpected: severity=$SEVERITY, review_required=$REVIEW"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "Triage endpoint failed"
  ERRORS=$((ERRORS + 1))
fi

# ── 5. Batch pipeline ───────────────────────────────────────────────────────
hdr "5. Batch pipeline (accepted + rejected)"

echo '$ curl -s -X POST http://localhost:8000/pipeline/batch-enrich -H "Content-Type: application/json" -d ...'
BATCH=$(curl -sf -X POST http://localhost:8000/pipeline/batch-enrich \
  -H "Content-Type: application/json" \
  -d "{\"items\": $(cat data/payloads/batch_feedback.json)}" 2>&1) || true

if [[ -n "$BATCH" ]]; then
  ACCEPTED=$(echo "$BATCH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('accepted',0))" 2>/dev/null || echo "0")
  REJECTED=$(echo "$BATCH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('rejected',0))" 2>/dev/null || echo "0")
  TOTAL=$(echo "$BATCH" | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "0")

  echo "  total=$TOTAL  accepted=$ACCEPTED  rejected=$REJECTED"

  if [[ "$ACCEPTED" -gt 0 && "$REJECTED" -gt 0 ]]; then
    ok "Batch pipeline: $ACCEPTED accepted, $REJECTED rejected out of $TOTAL"
  else
    fail "Expected both accepted and rejected items"
    ERRORS=$((ERRORS + 1))
  fi
else
  fail "Batch enrichment endpoint failed"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}${BOLD}All 5 checks passed. Demo is ready!${NC}\n"
else
  printf "${RED}${BOLD}$ERRORS check(s) failed. Fix the issues above.${NC}\n"
fi
echo "========================================="
echo ""

exit $ERRORS
