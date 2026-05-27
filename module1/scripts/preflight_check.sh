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

# ── Colors ──────────────────────────────────────────────────────────────────
# Pluralsight 2025 brand colors
PINK='\033[38;2;255;22;117m'     # Transform Pink — FAIL, errors
GREEN='\033[38;2;207;255;110m'   # Lime Green — PASS, success
LGREEN='\033[38;2;64;255;191m'   # Limited Green — values, data
BLUE='\033[38;2;42;236;250m'     # Blue — labels, field names
GRAY='\033[38;2;191;191;191m'    # Light Gray — secondary text
WHITE='\033[1;37m'               # White bold — headings
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0

pass() {
  printf "  ${GREEN}✓ PASS${NC}  %s\n" "$1"
}
fail_check() {
  printf "  ${PINK}✗ FAIL${NC}  %s\n" "$1"
  ERRORS=$((ERRORS + 1))
}
detail() {
  printf "           ${GRAY}%s${NC}\n" "$1"
}
fix() {
  printf "    ${BLUE}→ Fix:${NC} %s\n" "$1"
}
step_header() {
  echo ""
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${WHITE}  STEP %s: %s${NC}\n" "$1" "$2"
  printf "${BLUE}  Learning objective: %s${NC}\n" "$3"
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}
show_command() {
  printf "\n  ${DIM}Command:${NC}\n"
  printf "  ${DIM}\$${NC} %s\n\n" "$1"
}

# ── Log helpers ─────────────────────────────────────────────────────────────
log() { echo "$1" >> "$LOG"; }
log_divider() {
  log ""
  log "================================================================================"
  log "$1"
  log "================================================================================"
  log ""
}

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

# ── Header ──────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 1 Clip 4 — Preflight Check                        ║${NC}\n"
printf "${BOLD}║  Enriching e-commerce feedback with FastAPI and DuckDB     ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"

# ── Server check ────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}Checking server at ${API}...${NC}\n"

if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail_check "Server is not running at $API"
  fix "./scripts/module1-demo-reset.sh"
  detail "The reset script will start a fresh server with seed data."
  echo "Server not running" >> "$LOG"
  echo ""
  printf "${PINK}Cannot continue without a running server. Exiting.${NC}\n\n"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# Seed knowledge base silently
curl -sf -X POST "$API/admin/seed-knowledge-base" >/dev/null 2>&1
log "Knowledge base: seeded"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 (LO 1a)
# ═════════════════════════════════════════════════════════════════════════════
step_header "1/4" "Show DuckDB raw feedback input" "1a — Where LLMs fit in data pipelines"
show_command "curl -s $API/admin/metrics | python3 -m json.tool"

log_divider "STEP 1: Show DuckDB raw feedback input (LO 1a)"
log "COMMAND:"
log "  curl -s $API/admin/metrics | python3 -m json.tool"
log ""

METRICS=$(curl -sf "$API/admin/metrics")
echo "$METRICS" | python3 -m json.tool > "$TMPD/step1.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

RAW_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['raw_feedback'])")
TRUSTED_BEFORE=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")

printf "  ${BLUE}raw.feedback:${NC}            %s\n" "$RAW_COUNT"
printf "  ${BLUE}trusted.feedback_enriched:${NC} %s\n" "$TRUSTED_BEFORE"
echo ""

log "EXTRACTED VALUES:"
log "  raw_feedback:     $RAW_COUNT"
log "  trusted_enriched: $TRUSTED_BEFORE"
log ""
log "LO COVERAGE:"
log "  1a — Source data exists in the deterministic pipeline layer (raw.feedback = $RAW_COUNT)"

# Check: raw.feedback = 10
if [[ "$RAW_COUNT" -eq 10 ]]; then
  pass "raw.feedback = $RAW_COUNT (10 seed records present)"
  log "RESULT: PASS"
else
  fail_check "raw.feedback = $RAW_COUNT (expected 10)"
  fix "./scripts/module1-demo-reset.sh"
  detail "The reset script deletes DuckDB and reloads 10 seed records."
  log "RESULT: FAIL (expected 10)"
fi

# Check: trusted = 0 (clean baseline)
if [[ "$TRUSTED_BEFORE" -eq 0 ]]; then
  pass "trusted.feedback_enriched = $TRUSTED_BEFORE (clean baseline)"
  log "RESULT: PASS (baseline clean)"
else
  fail_check "trusted.feedback_enriched = $TRUSTED_BEFORE (expected 0)"
  fix "./scripts/module1-demo-reset.sh"
  detail "The reset script kills the server, deletes DuckDB, and restarts."
  detail "This clears all enrichment results from prior runs."
  log "RESULT: FAIL (expected 0)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 1a, 1b)
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/4" "Enrich a single feedback record through FastAPI" "1a, 1b — LLM boundary and contract"
show_command 'curl -s http://localhost:8000/enrich/feedback -H "Content-Type: application/json" -d @data/payloads/feedback_enrich.json'

log_divider "STEP 2: Enrich a single feedback record through FastAPI (LO 1a, 1b)"
log "COMMAND:"
log '  curl -s http://localhost:8000/enrich/feedback -H "Content-Type: application/json" -d @data/payloads/feedback_enrich.json'
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

printf "  ${BLUE}request_id:${NC}        %s\n" "$REQUEST_ID"
printf "  ${BLUE}category:${NC}          %s\n" "$CATEGORY"
printf "  ${BLUE}confidence:${NC}        %s\n" "$CONFIDENCE"
printf "  ${BLUE}source_doc_ids:${NC}    %s\n" "$SOURCE_DOCS"
printf "  ${BLUE}validation_status:${NC} %s\n" "$VAL_STATUS"
printf "  ${BLUE}summary:${NC}           %s\n" "$SUMMARY"
echo ""

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

# Check: category = product_quality
if [[ "$CATEGORY" == "product_quality" ]]; then
  pass "category = product_quality"
  detail "The feedback mentions 'cracked lid' and 'grinding noise' → product defect."
  log "RESULT: PASS — category = product_quality"
else
  fail_check "category = $CATEGORY (expected product_quality)"
  fix "Check keyword matching in app/services/llm.py"
  detail "The LLM stub classifies based on keywords. 'cracked' and 'grinding'"
  detail "should map to product_quality. Verify _KEYWORD_MAP in llm.py."
  log "RESULT: FAIL — category = $CATEGORY"
fi

# Check: confidence >= 0.75
CONF_OK=$(python3 -c "print(int(float('$CONFIDENCE') >= 0.75))")
if [[ "$CONF_OK" == "1" ]]; then
  pass "confidence = $CONFIDENCE (meets 0.75 threshold)"
  log "RESULT: PASS — confidence = $CONFIDENCE"
else
  fail_check "confidence = $CONFIDENCE (below 0.75 threshold)"
  fix "Check confidence logic in app/services/llm.py _classify_text()"
  detail "Confidence is 0.75 + (keyword_hits * 0.05). The payload text"
  detail "should match at least 1 keyword to reach the threshold."
  log "RESULT: FAIL — confidence below threshold"
fi

# Check: validation_status = accepted
if [[ "$VAL_STATUS" == "accepted" ]]; then
  pass "validation_status = accepted"
  detail "All validation checks passed: schema, grounding, confidence, category."
  log "RESULT: PASS — accepted"
else
  fail_check "validation_status = $VAL_STATUS (expected accepted)"
  fix "Run: curl -s $API/admin/llm-decisions?limit=1 | python3 -m json.tool"
  detail "Check the 'validation.errors' array in the decision record to see"
  detail "which specific check failed (schema, grounding, confidence, or category)."
  log "RESULT: FAIL — $VAL_STATUS"
fi

# Check: source_doc_ids not empty
if [[ -n "$SOURCE_DOCS" && "$SOURCE_DOCS" != "" ]]; then
  pass "source_doc_ids = [$SOURCE_DOCS]"
  detail "Grounded in reference documents from the knowledge base."
  log "RESULT: PASS — source_doc_ids present"
else
  fail_check "source_doc_ids is empty"
  fix "curl -sf -X POST $API/admin/seed-knowledge-base"
  detail "The knowledge base may not be seeded. Run the seed command above,"
  detail "then re-run this preflight check."
  log "RESULT: FAIL — source_doc_ids empty"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 1b, 1d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/4" "Verify the decision was stored in llm_decisions" "1b, 1d — Traceability and data flow"
show_command "curl -s $API/admin/llm-decisions?limit=1 | python3 -m json.tool"

log_divider "STEP 3: Verify the decision was stored in llm_decisions (LO 1b, 1d)"
log "COMMAND:"
log "  curl -s $API/admin/llm-decisions?limit=1 | python3 -m json.tool"
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

printf "  ${BLUE}request_id:${NC} %s\n" "$DEC_REQ_ID"
printf "  ${BLUE}endpoint:${NC}   %s\n" "$DEC_ENDPOINT"
printf "  ${BLUE}status:${NC}     %s\n" "$DEC_STATUS"
printf "  ${BLUE}tokens:${NC}     %s\n" "$DEC_TOKENS"
echo ""

log "EXTRACTED VALUES:"
log "  request_id: $DEC_REQ_ID"
log "  endpoint:   $DEC_ENDPOINT"
log "  status:     $DEC_STATUS"
log "  tokens:     $DEC_TOKENS"
log ""
log "LO COVERAGE:"
log "  1b — System boundary: every LLM call creates a traceable decision record"
log "  1d — Data flow: request_id links enrichment output to decision store"

# Check: request_id matches Step 2
if [[ "$DEC_REQ_ID" == "$REQUEST_ID" ]]; then
  pass "request_id matches Step 2 → end-to-end traceability confirmed"
  detail "Step 2 request_id: $REQUEST_ID"
  detail "Step 3 request_id: $DEC_REQ_ID"
  log "RESULT: PASS — request_id $DEC_REQ_ID matches Step 2"
else
  fail_check "request_id mismatch"
  detail "Step 2 returned: $REQUEST_ID"
  detail "Step 3 found:    $DEC_REQ_ID"
  fix "./scripts/module1-demo-reset.sh"
  detail "This can happen if a prior enrichment call left stale data."
  detail "Reset clears all in-memory state and starts fresh."
  log "RESULT: FAIL — request_id mismatch"
fi

# Check: status = accepted
if [[ "$DEC_STATUS" == "accepted" ]]; then
  pass "decision status = accepted"
  log "RESULT: PASS — status = accepted"
else
  fail_check "decision status = $DEC_STATUS (expected accepted)"
  fix "Check the validation errors in the full decision JSON above"
  detail "The decision record contains a 'validation.errors' array that"
  detail "lists exactly which checks failed."
  log "RESULT: FAIL — status = $DEC_STATUS"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 1d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/4" "Verify trusted output table received the enriched record" "1d — Validated output reaches trusted table"
show_command "curl -s $API/admin/metrics | python3 -m json.tool"

log_divider "STEP 4: Verify trusted output table received the enriched record (LO 1d)"
log "COMMAND:"
log "  curl -s $API/admin/metrics | python3 -m json.tool"
log ""

METRICS_AFTER=$(curl -sf "$API/admin/metrics")
echo "$METRICS_AFTER" | python3 -m json.tool > "$TMPD/step4.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

TRUSTED_AFTER=$(echo "$METRICS_AFTER" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
DELTA=$((TRUSTED_AFTER - TRUSTED_BEFORE))

printf "  ${BLUE}trusted.enriched before:${NC} %s\n" "$TRUSTED_BEFORE"
printf "  ${BLUE}trusted.enriched after:${NC}  %s\n" "$TRUSTED_AFTER"
printf "  ${BLUE}row count delta:${NC}         ${GREEN}+%s${NC}\n" "$DELTA"
echo ""

log "EXTRACTED VALUES:"
log "  trusted_enriched before: $TRUSTED_BEFORE"
log "  trusted_enriched after:  $TRUSTED_AFTER"
log "  delta:                   +$DELTA"
log ""
log "LO COVERAGE:"
log "  1d — Data flow complete: validated LLM output promoted to trusted table (+$DELTA row)"

# Check: delta > 0
if [[ "$DELTA" -gt 0 ]]; then
  pass "trusted.feedback_enriched grew by +$DELTA row"
  detail "The validated LLM output was promoted from proposal to trusted data."
  log "RESULT: PASS — delta = +$DELTA"
else
  fail_check "trusted.feedback_enriched did not grow (delta = $DELTA)"
  fix "./scripts/module1-demo-reset.sh && module1/scripts/preflight_check.sh"
  detail "If trusted_before was already > 0, a prior run left data behind."
  detail "Reset clears the database and starts from scratch."
  log "RESULT: FAIL — no growth"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 1a | Step 1, Step 2 | raw.feedback=$RAW_COUNT shows source data; enrichment classifies as product_quality |"
log "| 1b | Step 2, Step 3 | Structured JSON contract with validation; traceable decision record |"
log "| 1d | Step 3, Step 4 | request_id links enrichment to decision; trusted table grew by +$DELTA |"
log ""
log "All 3 learning objectives (1a, 1b, 1d) are covered by the 4 demo steps."

echo ""
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}1a${NC}  Steps 1, 2  ${DIM}Source data + LLM classification${NC}\n"
printf "  ${BLUE}1b${NC}  Steps 2, 3  ${DIM}Boundary contract + traceable decision${NC}\n"
printf "  ${BLUE}1d${NC}  Steps 3, 4  ${DIM}Decision traceability + trusted table promotion${NC}\n"

# ═════════════════════════════════════════════════════════════════════════════
# VERDICT
# ═════════════════════════════════════════════════════════════════════════════
echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}  ✓ ALL CHECKS PASSED — Demo is ready${NC}\n"
  log ""
  log "VERDICT: ALL CHECKS PASSED"
else
  printf "${PINK}  ✗ $ERRORS CHECK(S) FAILED — Fix the issues above${NC}\n"
  echo ""
  printf "  ${BLUE}Quick fix:${NC} ./scripts/module1-demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module1/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module1/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
