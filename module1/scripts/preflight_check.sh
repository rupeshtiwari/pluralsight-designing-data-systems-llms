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
warn_check() {
  printf "  ${BLUE}⚠ NOTE${NC}  %s\n" "$1"
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
# highlight: a KEY property the author reads aloud on camera.
# Label in Blue, value in Limited Green, marked with ★ so it stands out.
highlight() {
  printf "  ${PINK}★${NC} ${BLUE}%s${NC} ${LGREEN}%s${NC}\n" "$1" "$2"
}
# field: a supporting value shown for context but not narrated.
field() {
  printf "    ${GRAY}%s${NC} ${GRAY}%s${NC}\n" "$1" "$2"
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

# ── Reset to a clean baseline ────────────────────────────────────────────────
# Always reset first so the preflight is reproducible no matter what ran
# before (a prior demo leaves trusted_enriched > 0, which would fail Step 1).
echo ""
printf "  ${DIM}Resetting to a clean baseline...${NC}\n"
if [[ -x "$PROJECT_ROOT/scripts/module1-demo-reset.sh" ]]; then
  "$PROJECT_ROOT/scripts/module1-demo-reset.sh" >/dev/null 2>&1 || true
fi

# ── Server check ────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}Checking server at ${API}...${NC}\n"

if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail_check "Server is not running at $API"
  fix "module1/scripts/demo-reset.sh"
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
step_header "1/7" "Show DuckDB raw feedback input" "1a — Where LLMs fit in data pipelines"
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

highlight "raw.feedback row count:" "$RAW_COUNT"
field     "trusted.feedback_enriched:" "$TRUSTED_BEFORE  (empty baseline)"
echo ""
printf "  ${GRAY}★ = read this value aloud on camera${NC}\n"
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
  fix "module1/scripts/demo-reset.sh"
  detail "The reset script deletes DuckDB and reloads 10 seed records."
  log "RESULT: FAIL (expected 10)"
fi

# Check: trusted = 0 (clean baseline)
if [[ "$TRUSTED_BEFORE" -eq 0 ]]; then
  pass "trusted.feedback_enriched = $TRUSTED_BEFORE (clean baseline)"
  log "RESULT: PASS (baseline clean)"
else
  fail_check "trusted.feedback_enriched = $TRUSTED_BEFORE (expected 0)"
  fix "module1/scripts/demo-reset.sh"
  detail "The reset script kills the server, deletes DuckDB, and restarts."
  detail "This clears all enrichment results from prior runs."
  log "RESULT: FAIL (expected 0)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 1a, 1b) — pgvector reference documents
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/7" "Show pgvector reference documents" "1a, 1b — Grounded retrieval source"
show_command 'curl -s http://localhost:8000/admin/reference-docs?limit=8 | python3 scripts/fmt.py --type refdocs'

log_divider "STEP 2: Show pgvector reference documents (LO 1a, 1b)"
log "COMMAND:"
log '  curl -s http://localhost:8000/admin/reference-docs?limit=8'
log ""

DOCS_JSON=$(curl -sf "$API/admin/reference-docs?limit=8")
echo "$DOCS_JSON" > "$TMPD/step2.json"
DOCS_COUNT=$(echo "$DOCS_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('count',0))" 2>/dev/null || echo 0)
DOCS_BACKEND=$(echo "$DOCS_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('backend','?'))" 2>/dev/null || echo "?")
ALL_EMBED=$(echo "$DOCS_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);docs=d.get('documents',[]);print('yes' if docs and all(x.get('has_embedding') for x in docs) else 'no')" 2>/dev/null || echo "no")

log "OUTPUT:"
log "  backend: $DOCS_BACKEND"
log "  count: $DOCS_COUNT"
log "  all_embedded: $ALL_EMBED"
log ""

highlight "backend:" "$DOCS_BACKEND"
highlight "count:" "$DOCS_COUNT"
highlight "all_embedded:" "$ALL_EMBED"
echo ""
printf "  ${GRAY}★ = the LLM is grounded against these approved docs in real Postgres${NC}\n"
echo ""

if [[ "$DOCS_COUNT" -eq 8 ]]; then
  pass "8 reference documents seeded"
  log "RESULT: PASS — 8 reference docs present"
else
  fail_check "Expected 8 reference documents, got $DOCS_COUNT"
  fix "module1/scripts/demo-reset.sh"
  log "RESULT: FAIL — count = $DOCS_COUNT"
fi

if [[ "$DOCS_BACKEND" == "postgres" ]]; then
  pass "backend = postgres (real pgvector in use)"
  log "RESULT: PASS — backend postgres"
else
  warn_check "backend = $DOCS_BACKEND (outline requires postgres + pgvector)"
  log "RESULT: WARN — backend $DOCS_BACKEND (start docker compose up -d postgres)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 1b) — JSON contract from Clip 2
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/7" "Show the JSON contract from Clip 2" "1b — Boundary between deterministic and AI"
show_command 'curl -s http://localhost:8000/admin/json-contract | python3 scripts/fmt.py --type contract'

log_divider "STEP 3: Show the JSON contract from Clip 2 (LO 1b)"
log "COMMAND:"
log '  curl -s http://localhost:8000/admin/json-contract'
log ""

CONTRACT_JSON=$(curl -sf "$API/admin/json-contract")
echo "$CONTRACT_JSON" > "$TMPD/step3.json"
RESP_FIELDS=$(echo "$CONTRACT_JSON" | python3 -c "import json,sys;print(','.join(list((json.load(sys.stdin).get('response_schema') or {}).get('properties',{}).keys())))" 2>/dev/null || echo "")
GATE_COUNT=$(echo "$CONTRACT_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('validation_gates',[])))" 2>/dev/null || echo 0)

log "OUTPUT:"
log "  response_fields: $RESP_FIELDS"
log "  validation_gates: $GATE_COUNT"
log ""

highlight "response fields:" "$RESP_FIELDS"
highlight "validation gates:" "$GATE_COUNT"
echo ""
printf "  ${GRAY}★ = the deterministic pipeline only reads these fields; gates run on every response${NC}\n"
echo ""

if [[ "$RESP_FIELDS" == *"request_id"* && "$RESP_FIELDS" == *"source_doc_ids"* && "$RESP_FIELDS" == *"validation_status"* ]]; then
  pass "contract carries every outline-named field"
  log "RESULT: PASS — contract has request_id, source_doc_ids, validation_status"
else
  fail_check "contract missing required fields (got: $RESP_FIELDS)"
  fix "module1/scripts/demo-reset.sh"
  log "RESULT: FAIL — fields = $RESP_FIELDS"
fi

if [[ "$GATE_COUNT" -eq 4 ]]; then
  pass "all four validation gates declared in the contract"
  log "RESULT: PASS — 4 gates"
else
  fail_check "expected 4 validation gates, got $GATE_COUNT"
  log "RESULT: FAIL — gate count = $GATE_COUNT"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 1a, 1b) — enrich one feedback record
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/7" "Enrich a single feedback record through FastAPI" "1a, 1b — LLM boundary and contract"
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

highlight "category:" "$CATEGORY"
highlight "confidence:" "$CONFIDENCE"
highlight "source_doc_ids:" "$SOURCE_DOCS"
highlight "validation_status:" "$VAL_STATUS"
field     "request_id:" "$REQUEST_ID"
field     "summary:" "$SUMMARY"
echo ""
printf "  ${GRAY}★ = read these 4 values aloud: category, confidence, sources, status${NC}\n"
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
step_header "5/7" "Verify the decision was stored in llm_decisions" "1b, 1d — Traceability and data flow"
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

highlight "request_id:" "$DEC_REQ_ID"
highlight "status:" "$DEC_STATUS"
field     "endpoint:" "$DEC_ENDPOINT"
field     "tokens:" "$DEC_TOKENS"
echo ""
printf "  ${GRAY}★ = read aloud: request_id (matches Step 2) and status${NC}\n"
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
  fix "module1/scripts/demo-reset.sh"
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
step_header "6/7" "Verify trusted output table received the enriched record" "1d — Validated output reaches trusted table"
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

field     "trusted.enriched before:" "$TRUSTED_BEFORE"
field     "trusted.enriched after:" "$TRUSTED_AFTER"
highlight "row count delta:" "+$DELTA"
echo ""
printf "  ${GRAY}★ = read aloud: the row count delta (0 → 1)${NC}\n"
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
  fix "module1/scripts/demo-reset.sh && module1/scripts/preflight_check.sh"
  detail "If trusted_before was already > 0, a prior run left data behind."
  detail "Reset clears the database and starts from scratch."
  log "RESULT: FAIL — no growth"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 (LO 1d) — Quarantine path for failed validation
# ═════════════════════════════════════════════════════════════════════════════
step_header "7/7" "Show what gets quarantined when validation fails" "1d — Bad LLM output never reaches trusted"
show_command 'curl -s http://localhost:8000/enrich/feedback -d @data/payloads/feedback_ambiguous.json'

log_divider "STEP 7: Quarantine path for failed validation (LO 1d)"
log "COMMAND:"
log '  curl -s http://localhost:8000/enrich/feedback -d @data/payloads/feedback_ambiguous.json'
log ""

QUARANTINE_BEFORE=$(echo "$METRICS_AFTER" | python3 -c "import json,sys;print(json.load(sys.stdin)['duckdb'].get('quarantine_outputs',0))")
AMBIG_RESP=$(curl -sf -X POST "$API/enrich/feedback" -H "Content-Type: application/json" \
  -d @"$PROJECT_ROOT/data/payloads/feedback_ambiguous.json")
echo "$AMBIG_RESP" > "$TMPD/step7.json"
AMBIG_STATUS=$(echo "$AMBIG_RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('validation_status','?'))" 2>/dev/null || echo "?")
AMBIG_CONF=$(echo "$AMBIG_RESP" | python3 -c "import json,sys;print(json.load(sys.stdin).get('confidence',0))" 2>/dev/null || echo 0)

METRICS_QUAR=$(curl -sf "$API/admin/metrics")
TRUSTED_FINAL=$(echo "$METRICS_QUAR" | python3 -c "import json,sys;print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
QUARANTINE_AFTER=$(echo "$METRICS_QUAR" | python3 -c "import json,sys;print(json.load(sys.stdin)['duckdb'].get('quarantine_outputs',0))")

log "OUTPUT:"
log "  validation_status: $AMBIG_STATUS"
log "  confidence: $AMBIG_CONF"
log "  trusted_enriched (unchanged): $TRUSTED_FINAL"
log "  quarantine_outputs before/after: $QUARANTINE_BEFORE / $QUARANTINE_AFTER"
log ""

highlight "validation_status:" "$AMBIG_STATUS"
highlight "confidence:" "$AMBIG_CONF"
field     "trusted_enriched (unchanged):" "$TRUSTED_FINAL"
highlight "quarantine_outputs delta:" "+$((QUARANTINE_AFTER - QUARANTINE_BEFORE))"
echo ""
printf "  ${GRAY}★ = read aloud: failed validation ⇒ quarantine, not trusted${NC}\n"
echo ""

if [[ "$AMBIG_STATUS" == "failed" ]]; then
  pass "validation_status = failed (low confidence below 0.75 threshold)"
  log "RESULT: PASS — validation rejected the ambiguous record"
else
  fail_check "validation_status = $AMBIG_STATUS (expected failed)"
  log "RESULT: FAIL — expected failed, got $AMBIG_STATUS"
fi

if [[ "$TRUSTED_FINAL" == "$TRUSTED_AFTER" ]]; then
  pass "trusted.feedback_enriched did NOT grow — the gate held"
  log "RESULT: PASS — trusted table unchanged"
else
  fail_check "trusted.feedback_enriched grew unexpectedly (was $TRUSTED_AFTER, now $TRUSTED_FINAL)"
  log "RESULT: FAIL — trusted should not have grown"
fi

if [[ "$QUARANTINE_AFTER" -gt "$QUARANTINE_BEFORE" ]]; then
  pass "quarantine.llm_outputs grew by +$((QUARANTINE_AFTER - QUARANTINE_BEFORE)) row"
  log "RESULT: PASS — quarantine received the failed record"
else
  fail_check "quarantine.llm_outputs did not grow (was $QUARANTINE_BEFORE, now $QUARANTINE_AFTER)"
  log "RESULT: FAIL — failed record was not quarantined"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 1a | Steps 1, 2, 4 | raw.feedback=$RAW_COUNT + pgvector docs + LLM classification |"
log "| 1b | Steps 2, 3, 4, 5 | pgvector grounding + JSON contract + structured response + four gates |"
log "| 1d | Steps 5, 6, 7 | Decision traceability + trusted table promotion + quarantine on failure |"
log ""
log "All 3 learning objectives (1a, 1b, 1d) are covered by the 7 demo steps."

echo ""
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}1a${NC}  Steps 1, 2, 4     ${DIM}Source data + grounding source + LLM classification${NC}\n"
printf "  ${BLUE}1b${NC}  Steps 2, 3, 4, 5  ${DIM}Grounding + JSON contract + structured response + four gates${NC}\n"
printf "  ${BLUE}1d${NC}  Steps 5, 6, 7     ${DIM}Traceability + trusted table promotion + quarantine on failure${NC}\n"

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
  printf "  ${BLUE}Quick fix:${NC} module1/scripts/demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module1/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
  log ""
  log "HOW TO FIX:"
  log "  1. Reset the environment:"
  log "     module1/scripts/demo-reset.sh"
  log ""
  log "  2. Rerun the preflight check:"
  log "     module1/scripts/preflight_check.sh"
  log ""
  log "  3. If reset does not fix it, check:"
  log "     - Is the server running? curl -s http://localhost:8000/health"
  log "     - Are seed files present? ls data/seed/"
  log "     - Are payloads present? ls data/payloads/"
  log "     - Run full setup: ./environment-setup/install-macos-requirements.sh"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module1/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
