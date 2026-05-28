#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 3 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module3/preflight_log.txt.
#
# Use the log to verify that demo steps align with the learning objectives.
#
# Usage:
#   module3/scripts/preflight_check.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="$PROJECT_ROOT/module3/preflight_log.txt"
API="http://localhost:8000"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# ── Colors ──────────────────────────────────────────────────────────────────
# Pluralsight 2025 brand colors
PINK='\033[38;2;255;22;117m'     # Transform Pink
GREEN='\033[38;2;207;255;110m'   # Lime Green

LGREEN='\033[38;2;64;255;191m'   # Limited Green
GRAY='\033[38;2;191;191;191m'    # Light Gray
WHITE='\033[1;37m'               # White bold
BLUE='\033[38;2;42;236;250m'
BOLD='\033[1m'
DIM='\033[2m'
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
MODULE 3 — CLIP 4 PREFLIGHT LOG
================================================================================
Demo:    Triggering and monitoring an Airflow enrichment pipeline with FastAPI and DuckDB
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API

Learning objectives:
  3a  Compare and contrast static DAGs with dynamic orchestration
  3b  Demonstrate the steps required to integrate LLM logic into orchestration tools
  3c  Trigger and monitor pipeline tasks that automate operations
  3d  Apply guardrails and validation so learners can ensure safe and reliable system behavior

HEADER

# ── Header ──────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 3 Clip 4 — Preflight Check                        ║${NC}\n"
printf "${BOLD}║  Airflow enrichment pipeline with FastAPI and DuckDB       ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"

# ── Server check ────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}Checking server at ${API}...${NC}\n"

if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail_check "Server is not running at $API"
  fix "module3/scripts/demo-reset.sh"
  detail "The reset script will start a fresh server with seed data."
  echo "Server not running" >> "$LOG"
  echo ""
  printf "${PINK}${BOLD}Cannot continue without a running server. Exiting.${NC}\n\n"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# Seed knowledge base silently
curl -sf -X POST "$API/admin/seed-knowledge-base" >/dev/null 2>&1
log "Knowledge base: seeded"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 (LO 3b, 3c)
# ═════════════════════════════════════════════════════════════════════════════
TRIGGER_CMD='curl -s -X POST http://localhost:8000/pipeline/trigger -H "Content-Type: application/json" -d '"'"'{"batch_id":"BATCH-20240318-001","source":"data/payloads/batch_feedback.json"}'"'"' | python3 -m json.tool'

step_header "1/4" "Trigger the pipeline" "3b, 3c — Integrating LLM logic into orchestration; trigger and monitor"
show_command "$TRIGGER_CMD"

log_divider "STEP 1: Trigger the pipeline (LO 3b, 3c)"
log "COMMAND:"
log "  $TRIGGER_CMD"
log ""

TRIGGER_RESP=$(curl -sf -X POST "$API/pipeline/trigger" \
  -H "Content-Type: application/json" \
  -d '{"batch_id":"BATCH-20240318-001","source":"data/payloads/batch_feedback.json"}')
echo "$TRIGGER_RESP" | python3 -m json.tool > "$TMPD/step1.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

TRIGGER_STATUS=$(echo "$TRIGGER_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','MISSING'))")
TRIGGER_BATCH=$(echo "$TRIGGER_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('batch_id','MISSING'))")
TRIGGER_DAG=$(echo "$TRIGGER_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin).get('dag_id','MISSING'))")

highlight "status:" "$TRIGGER_STATUS"
highlight "batch_id:" "$TRIGGER_BATCH"
field     "dag_id:" "$TRIGGER_DAG"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  batch_id: $TRIGGER_BATCH"
log "  dag_id:   $TRIGGER_DAG"
log "  status:   $TRIGGER_STATUS"
log ""
log "LO COVERAGE:"
log "  3b — Pipeline trigger returns batch_id and dag_id, showing LLM integration into orchestration"
log "  3c — Trigger creates a pipeline run record that can be monitored"

# Check: status = triggered
if [[ "$TRIGGER_STATUS" == "triggered" ]]; then
  pass "status = triggered"
  detail "Pipeline trigger returned the expected status."
  log "RESULT: PASS — status = triggered"
else
  fail_check "status = $TRIGGER_STATUS (expected triggered)"
  fix "Check app/routers/pipeline.py trigger_dag() return value"
  detail "The trigger endpoint should return status=triggered."
  log "RESULT: FAIL — status = $TRIGGER_STATUS"
fi

# Check: batch_id present
if [[ -n "$TRIGGER_BATCH" && "$TRIGGER_BATCH" != "MISSING" ]]; then
  pass "batch_id = $TRIGGER_BATCH (tracking ID assigned)"
  log "RESULT: PASS — batch_id present"
else
  fail_check "batch_id is missing from trigger response"
  fix "Check app/routers/pipeline.py trigger_dag() return value"
  log "RESULT: FAIL — batch_id missing"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 3a)
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/4" "Show pipeline run results" "3a — Compare static DAGs with dynamic orchestration"
show_command "curl -s http://localhost:8000/pipeline/runs | python3 -m json.tool"

log_divider "STEP 2: Show pipeline run results (LO 3a)"
log "COMMAND:"
log "  curl -s http://localhost:8000/pipeline/runs | python3 -m json.tool"
log ""

RUNS_RESP=$(curl -sf "$API/pipeline/runs")
echo "$RUNS_RESP" | python3 -m json.tool > "$TMPD/step2.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

RUN_COUNT=$(echo "$RUNS_RESP" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")

highlight "pipeline runs returned:" "$RUN_COUNT"
echo ""
printf "  ${GRAY}★ = read this value aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  pipeline_run_count: $RUN_COUNT"
log ""
log "LO COVERAGE:"
log "  3a — Pipeline runs list shows run records with status fields, contrasting dynamic"
log "       enrichment DAG (with accepted/rejected branching) vs. static reconciliation DAG"

# Check: at least one run
if [[ "$RUN_COUNT" -ge 1 ]]; then
  pass "pipeline/runs returned $RUN_COUNT run(s)"
  detail "At least one pipeline run is present (from Step 1 trigger)."
  log "RESULT: PASS — $RUN_COUNT run(s) found"
else
  fail_check "pipeline/runs returned 0 runs (expected at least 1)"
  fix "Rerun Step 1: curl -s -X POST $API/pipeline/trigger ..."
  detail "The trigger in Step 1 should have created a pipeline run record."
  log "RESULT: FAIL — no runs found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 3b, 3c) — batch-enrich then examine batch details
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/4" "Examine batch details for traceability" "3b, 3c — LLM integration and task monitoring"

# First, run batch-enrich to populate data
ENRICH_CMD='curl -s -X POST http://localhost:8000/pipeline/batch-enrich -H "Content-Type: application/json" -d "{\"items\": $(cat data/payloads/batch_feedback.json)}"'

printf "\n  ${DIM}Populating batch data via batch-enrich...${NC}\n"
show_command "$ENRICH_CMD"

log_divider "STEP 3: Examine batch details for traceability (LO 3b, 3c)"
log "SETUP COMMAND (populate batch data):"
log "  $ENRICH_CMD"
log ""

PAYLOAD_ITEMS=$(cat "$PROJECT_ROOT/data/payloads/batch_feedback.json")
ENRICH_RESP=$(curl -sf -X POST "$API/pipeline/batch-enrich" \
  -H "Content-Type: application/json" \
  -d "{\"items\": $PAYLOAD_ITEMS}")
echo "$ENRICH_RESP" | python3 -m json.tool > "$TMPD/step3_enrich.json" 2>&1

log "BATCH-ENRICH OUTPUT:"
cat "$TMPD/step3_enrich.json" >> "$LOG"
log ""

BATCH_ID=$(echo "$ENRICH_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['batch_id'])")

# Now query the batch details
DETAIL_CMD="curl -s http://localhost:8000/pipeline/run/$BATCH_ID | python3 -m json.tool"

show_command "$DETAIL_CMD"

log "QUERY COMMAND:"
log "  $DETAIL_CMD"
log ""

BATCH_RESP=$(curl -sf "$API/pipeline/run/$BATCH_ID")
echo "$BATCH_RESP" | python3 -m json.tool > "$TMPD/step3_detail.json" 2>&1

log "BATCH DETAIL OUTPUT:"
cat "$TMPD/step3_detail.json" >> "$LOG"
log ""

BATCH_TOTAL=$(echo "$ENRICH_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
BATCH_ACCEPTED=$(echo "$ENRICH_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['accepted'])")
BATCH_REJECTED=$(echo "$ENRICH_RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['rejected'])")

highlight "total:" "$BATCH_TOTAL"
highlight "accepted:" "$BATCH_ACCEPTED"
highlight "rejected:" "$BATCH_REJECTED"
field     "batch_id:" "$BATCH_ID"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  batch_id:  $BATCH_ID"
log "  total:     $BATCH_TOTAL"
log "  accepted:  $BATCH_ACCEPTED"
log "  rejected:  $BATCH_REJECTED"
log ""
log "LO COVERAGE:"
log "  3b — Batch enrichment shows LLM logic integrated into an orchestrated pipeline"
log "  3c — Per-item details (request_id, category, validation_status) enable task monitoring"

# Check: total = 5
if [[ "$BATCH_TOTAL" -eq 5 ]]; then
  pass "total = $BATCH_TOTAL (all 5 batch items processed)"
  log "RESULT: PASS — total = $BATCH_TOTAL"
else
  fail_check "total = $BATCH_TOTAL (expected 5)"
  fix "Check data/payloads/batch_feedback.json has 5 items"
  detail "The batch_feedback.json payload should contain exactly 5 feedback items."
  log "RESULT: FAIL — total = $BATCH_TOTAL"
fi

# Check: accepted = 3
if [[ "$BATCH_ACCEPTED" -eq 3 ]]; then
  pass "accepted = $BATCH_ACCEPTED (3 items passed validation)"
  log "RESULT: PASS — accepted = $BATCH_ACCEPTED"
else
  fail_check "accepted = $BATCH_ACCEPTED (expected 3)"
  fix "Check app/services/llm.py keyword classification and app/validators/output_validator.py"
  detail "Three of the five feedback items should pass all validation checks."
  detail "Verify that the LLM stub classifies correctly and that the validator"
  detail "thresholds have not changed."
  log "RESULT: FAIL — accepted = $BATCH_ACCEPTED"
fi

# Check: rejected = 2
if [[ "$BATCH_REJECTED" -eq 2 ]]; then
  pass "rejected = $BATCH_REJECTED (2 items sent to quarantine)"
  detail "Rejected items have specific error messages explaining why they failed."
  log "RESULT: PASS — rejected = $BATCH_REJECTED"
else
  fail_check "rejected = $BATCH_REJECTED (expected 2)"
  fix "Check app/validators/output_validator.py validation rules"
  detail "Two of the five feedback items should fail validation and be quarantined."
  log "RESULT: FAIL — rejected = $BATCH_REJECTED"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 3c, 3d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/4" "Verify trusted output and quarantine tables" "3c, 3d — Monitoring pipeline tasks; guardrails and validation"
show_command "curl -s http://localhost:8000/admin/metrics | python3 -m json.tool"

log_divider "STEP 4: Verify trusted output and quarantine tables (LO 3c, 3d)"
log "COMMAND:"
log "  curl -s http://localhost:8000/admin/metrics | python3 -m json.tool"
log ""

METRICS=$(curl -sf "$API/admin/metrics")
echo "$METRICS" | python3 -m json.tool > "$TMPD/step4.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

TRUSTED=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
QUARANTINE=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['quarantine_outputs'])")

highlight "trusted_enriched:" "$TRUSTED"
highlight "quarantine_outputs:" "$QUARANTINE"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  trusted_enriched:   $TRUSTED"
log "  quarantine_outputs: $QUARANTINE"
log ""
log "LO COVERAGE:"
log "  3c — Trusted table confirms accepted records completed the pipeline successfully"
log "  3d — Quarantine table proves guardrails caught invalid outputs with rejection reasons"

# Check: trusted >= 3
if [[ "$TRUSTED" -ge 3 ]]; then
  pass "trusted_enriched = $TRUSTED (>= 3 accepted records in trusted table)"
  detail "Accepted records from the batch enrichment reached the trusted output."
  log "RESULT: PASS — trusted_enriched = $TRUSTED"
else
  fail_check "trusted_enriched = $TRUSTED (expected >= 3)"
  fix "module3/scripts/demo-reset.sh && module3/scripts/preflight_check.sh"
  detail "The batch enrichment in Step 3 should have promoted at least 3 accepted"
  detail "records to the trusted table. Reset and rerun from scratch."
  log "RESULT: FAIL — trusted_enriched = $TRUSTED"
fi

# Check: quarantine >= 2
if [[ "$QUARANTINE" -ge 2 ]]; then
  pass "quarantine_outputs = $QUARANTINE (>= 2 rejected records in quarantine)"
  detail "Rejected records were caught by validation guardrails with specific reasons."
  log "RESULT: PASS — quarantine_outputs = $QUARANTINE"
else
  fail_check "quarantine_outputs = $QUARANTINE (expected >= 2)"
  fix "module3/scripts/demo-reset.sh && module3/scripts/preflight_check.sh"
  detail "The batch enrichment in Step 3 should have quarantined at least 2 records"
  detail "that failed validation. Reset and rerun from scratch."
  log "RESULT: FAIL — quarantine_outputs = $QUARANTINE"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 3a | Step 2 | Pipeline runs show dynamic branching (accepted/rejected) vs. static linear DAG |"
log "| 3b | Step 1, Step 3 | Trigger returns batch_id and dag_id; batch details show per-item LLM results |"
log "| 3c | Step 1, Step 3, Step 4 | Trigger creates trackable run; per-item traceability; trusted table confirmation |"
log "| 3d | Step 4 | Quarantine table has >= $QUARANTINE rejected records with validation error reasons |"
log ""
log "All 4 learning objectives (3a, 3b, 3c, 3d) are covered by the 4 demo steps."

echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}3a${NC}  Step 2      ${DIM}Dynamic branching vs. static linear DAG${NC}\n"
printf "  ${BLUE}3b${NC}  Steps 1, 3  ${DIM}Pipeline trigger + per-item LLM results${NC}\n"
printf "  ${BLUE}3c${NC}  Steps 1, 3, 4  ${DIM}Trigger, traceability, trusted output${NC}\n"
printf "  ${BLUE}3d${NC}  Step 4      ${DIM}Quarantine guardrails with rejection reasons${NC}\n"

# ═════════════════════════════════════════════════════════════════════════════
# VERDICT
# ═════════════════════════════════════════════════════════════════════════════
echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}${BOLD}  ✓ ALL CHECKS PASSED — Demo is ready${NC}\n"
  log ""
  log "VERDICT: ALL CHECKS PASSED"
else
  printf "${PINK}${BOLD}  ✗ $ERRORS CHECK(S) FAILED — Fix the issues above${NC}\n"
  echo ""
  printf "  ${BLUE}Quick fix:${NC} module3/scripts/demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module3/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
  log ""
  log "HOW TO FIX:"
  log "  1. Reset the environment:"
  log "     module3/scripts/demo-reset.sh"
  log ""
  log "  2. Rerun the preflight check:"
  log "     module3/scripts/preflight_check.sh"
  log ""
  log "  3. If reset does not fix it, check:"
  log "     - Is the server running? curl -s http://localhost:8000/health"
  log "     - Are seed files present? ls data/seed/"
  log "     - Are payloads present? ls data/payloads/"
  log "     - Run full setup: ./environment-setup/install-macos-requirements.sh"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module3/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
