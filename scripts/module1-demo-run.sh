#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Clip 4 — Demo Run
#
# Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector
#
# Proves four things on screen:
#   1. DuckDB raw.feedback has input rows before enrichment
#   2. FastAPI returns request_id, category, summary, confidence, source_doc_ids
#   3. llm_decisions table records the same request_id and validation status
#   4. trusted.feedback_enriched row count increases after enrichment
#
# Run module1-demo-reset.sh first to start from a clean baseline.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

BLUE='\033[38;2;42;236;250m'
GREEN='\033[38;2;207;255;110m'
PINK='\033[38;2;255;22;117m'
LGREEN='\033[38;2;64;255;191m'
WHITE='\033[1;37m'
GRAY='\033[38;2;191;191;191m'
BOLD='\033[1m'
NC='\033[0m'

hdr() {
  echo ""
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${WHITE}  STEP %s: %s${NC}\n" "$1" "$2"
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

label() { printf "${BLUE}%s${NC}" "$1"; }

API="http://localhost:8000"

# Verify server
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  printf "${PINK}Server not running. Run: ./scripts/module1-demo-reset.sh${NC}\n"
  exit 1
fi

echo ""
printf "${WHITE}Module 1 Clip 4 — Enriching e-commerce feedback${NC}\n"
printf "${WHITE}with FastAPI, DuckDB, and pgvector${NC}\n"
echo ""

# ── STEP 1: DuckDB raw feedback count ────────────────────────────────────────
hdr "1/4" "DuckDB raw.feedback input batch"

printf "${GRAY}$ curl -s $API/admin/metrics${NC}\n"
echo ""

METRICS=$(curl -sf "$API/admin/metrics")
RAW_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['raw_feedback'])")
TRUSTED_BEFORE=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")

printf "  $(label 'raw.feedback row count:')   ${LGREEN}${RAW_COUNT}${NC}\n"
printf "  $(label 'trusted.enriched before:')   ${LGREEN}${TRUSTED_BEFORE}${NC}\n"
echo ""
printf "  ${GREEN}▸ ${RAW_COUNT} feedback records ready for enrichment${NC}\n"

sleep 2

# ── STEP 2: Enrich a single feedback record ──────────────────────────────────
hdr "2/4" "Enrich feedback via FastAPI"

printf "${GRAY}$ curl -s $API/enrich/feedback -H 'Content-Type: application/json' \\\\${NC}\n"
printf "${GRAY}    -d @data/payloads/feedback_enrich.json${NC}\n"
echo ""

RESPONSE=$(curl -sf "$API/enrich/feedback" \
  -H "Content-Type: application/json" \
  -d @data/payloads/feedback_enrich.json)

REQUEST_ID=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['request_id'])")
CATEGORY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['category'])")
SUMMARY=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary'])")
CONFIDENCE=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['confidence'])")
SOURCE_DOCS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(', '.join(json.load(sys.stdin)['source_doc_ids']))")
VAL_STATUS=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['validation_status'])")

printf "  $(label 'request_id:')        ${LGREEN}${REQUEST_ID}${NC}\n"
printf "  $(label 'category:')           ${GREEN}${CATEGORY}${NC}\n"
printf "  $(label 'summary:')            ${NC}${SUMMARY}${NC}\n"
printf "  $(label 'confidence:')          ${LGREEN}${CONFIDENCE}${NC}\n"
printf "  $(label 'source_doc_ids:')     ${LGREEN}${SOURCE_DOCS}${NC}\n"
printf "  $(label 'validation_status:')  ${GREEN}${VAL_STATUS}${NC}\n"

echo ""
printf "  ${GREEN}▸ LLM classified as ${CATEGORY} with confidence ${CONFIDENCE}${NC}\n"
printf "  ${GREEN}▸ Grounded in reference docs: ${SOURCE_DOCS}${NC}\n"
printf "  ${GREEN}▸ Validation status: ${VAL_STATUS}${NC}\n"

sleep 2

# ── STEP 3: Verify decision in llm_decisions ─────────────────────────────────
hdr "3/4" "Verify decision in llm_decisions"

printf "${GRAY}$ curl -s $API/admin/llm-decisions?limit=1${NC}\n"
echo ""

DECISIONS=$(curl -sf "$API/admin/llm-decisions?limit=1")

DEC_REQ_ID=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['request_id'] if d else 'none')")
DEC_ENDPOINT=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['endpoint'] if d else 'none')")
DEC_STATUS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['status'] if d else 'none')")
DEC_TOKENS=$(echo "$DECISIONS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f\"prompt={d[0].get('prompt_tokens',0)}  completion={d[0].get('completion_tokens',0)}  total={d[0].get('total_tokens',0)}\") if d else print('none')")

printf "  $(label 'request_id:')        ${LGREEN}${DEC_REQ_ID}${NC}\n"
printf "  $(label 'endpoint:')           ${NC}${DEC_ENDPOINT}${NC}\n"
printf "  $(label 'status:')             ${GREEN}${DEC_STATUS}${NC}\n"
printf "  $(label 'tokens:')             ${LGREEN}${DEC_TOKENS}${NC}\n"

echo ""
if [[ "$DEC_REQ_ID" == "$REQUEST_ID" ]]; then
  printf "  ${GREEN}▸ request_id matches Step 2 — full traceability confirmed${NC}\n"
else
  printf "  ${PINK}▸ request_id mismatch: expected ${REQUEST_ID}${NC}\n"
fi

sleep 2

# ── STEP 4: Verify trusted output row count delta ───────────────────────────
hdr "4/4" "DuckDB trusted.feedback_enriched row count"

printf "${GRAY}$ curl -s $API/admin/metrics${NC}\n"
echo ""

METRICS_AFTER=$(curl -sf "$API/admin/metrics")
TRUSTED_AFTER=$(echo "$METRICS_AFTER" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
DELTA=$((TRUSTED_AFTER - TRUSTED_BEFORE))

printf "  $(label 'trusted.enriched before:')  ${LGREEN}${TRUSTED_BEFORE}${NC}\n"
printf "  $(label 'trusted.enriched after:')   ${LGREEN}${TRUSTED_AFTER}${NC}\n"
printf "  $(label 'row count delta:')           ${GREEN}+${DELTA}${NC}\n"

echo ""
if [[ "$DELTA" -gt 0 ]]; then
  printf "  ${GREEN}▸ Validated LLM output promoted to trusted table (+${DELTA} row)${NC}\n"
else
  printf "  ${PINK}▸ No new rows in trusted table${NC}\n"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${WHITE}  DEMO COMPLETE${NC}\n"
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${GREEN}✓${NC} raw.feedback has ${RAW_COUNT} input records\n"
printf "  ${GREEN}✓${NC} FastAPI returned category=${CATEGORY}, confidence=${CONFIDENCE}\n"
printf "  ${GREEN}✓${NC} llm_decisions recorded request_id with status=${DEC_STATUS}\n"
printf "  ${GREEN}✓${NC} trusted.feedback_enriched grew by +${DELTA} row\n"
echo ""
printf "  ${BOLD}Callout: LLM outputs are proposals until validation promotes them to trusted data${NC}\n"
echo ""
