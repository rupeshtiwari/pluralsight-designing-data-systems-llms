#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 4 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module4/preflight_log.txt.
#
# Use the log to verify that demo steps align with the learning objectives.
#
# Usage:
#   module4/scripts/preflight_check.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="$PROJECT_ROOT/module4/preflight_log.txt"
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
MODULE 4 — CLIP 4 PREFLIGHT LOG
================================================================================
Demo:    Rejecting hallucinated and schema-drifted LLM outputs in Airflow
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API

Learning objectives:
  1d  Demonstrate designing data flows that incorporate LLM outputs
  3c  Trigger and monitor pipeline tasks that automate operations
  3d  Apply guardrails and validation so learners can ensure safe and reliable system behavior

HEADER

# ── Header ──────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 4 Clip 4 — Preflight Check                        ║${NC}\n"
printf "${BOLD}║  Rejecting hallucinated and schema-drifted LLM outputs    ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"

# ── Reset to a clean baseline ────────────────────────────────────────────────
# Always reset first so the preflight is reproducible no matter what ran before.
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
  fix "module4/scripts/demo-reset.sh"
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
# STEP 1 (LO 3c, 3d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "1/4" "Run the validation batch through the pipeline" "3c, 3d — Batch processing with validation routing"

BATCH_CMD="curl -s -X POST $API/pipeline/batch-enrich -H \"Content-Type: application/json\" -d '{\"items\": $(cat data/payloads/batch_feedback.json)}'"
show_command "$BATCH_CMD"

log_divider "STEP 1: Run the validation batch through the pipeline (LO 3c, 3d)"
log "COMMAND:"
log "  $BATCH_CMD"
log ""
log "INPUT PAYLOAD (data/payloads/batch_feedback.json):"
cat "$PROJECT_ROOT/data/payloads/batch_feedback.json" >> "$LOG"
log ""

BATCH_PAYLOAD=$(python3 -c "
import json
items = json.load(open('$PROJECT_ROOT/data/payloads/batch_feedback.json'))
print(json.dumps({'items': items}))
")

BATCH_RESPONSE=$(curl -sf -X POST "$API/pipeline/batch-enrich" \
  -H "Content-Type: application/json" \
  -d "$BATCH_PAYLOAD")
echo "$BATCH_RESPONSE" | python3 -m json.tool > "$TMPD/step1.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

BATCH_ID=$(echo "$BATCH_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['batch_id'])")
TOTAL=$(echo "$BATCH_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['total'])")
ACCEPTED=$(echo "$BATCH_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['accepted'])")
REJECTED=$(echo "$BATCH_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['rejected'])")
QUARANTINED=$(echo "$BATCH_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['quarantined'])")

highlight "total:" "$TOTAL"
highlight "accepted:" "$ACCEPTED"
highlight "rejected:" "$REJECTED"
field     "batch_id:" "$BATCH_ID"
field     "quarantined:" "$QUARANTINED"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  batch_id:     $BATCH_ID"
log "  total:        $TOTAL"
log "  accepted:     $ACCEPTED"
log "  rejected:     $REJECTED"
log "  quarantined:  $QUARANTINED"
log ""
log "LO COVERAGE:"
log "  3c — Batch pipeline executed: total=$TOTAL, accepted=$ACCEPTED, rejected=$REJECTED"
log "  3d — Validation routing: rejected items quarantined, accepted items promoted"

# Check: total = 5
if [[ "$TOTAL" -eq 5 ]]; then
  pass "total = $TOTAL (all 5 batch items processed)"
  log "RESULT: PASS — total = $TOTAL"
else
  fail_check "total = $TOTAL (expected 5)"
  fix "Verify data/payloads/batch_feedback.json has 5 items"
  detail "The batch payload should contain exactly 5 feedback records."
  log "RESULT: FAIL — total = $TOTAL (expected 5)"
fi

# Check: accepted >= 2
if [[ "$ACCEPTED" -ge 2 ]]; then
  pass "accepted = $ACCEPTED (at least 2 items passed validation)"
  log "RESULT: PASS — accepted = $ACCEPTED"
else
  fail_check "accepted = $ACCEPTED (expected >= 2)"
  fix "curl -sf -X POST $API/admin/seed-knowledge-base"
  detail "The knowledge base may not be seeded. Without reference docs,"
  detail "grounding checks will fail and reduce accepted count."
  log "RESULT: FAIL — accepted = $ACCEPTED (expected >= 2)"
fi

# Check: rejected >= 1
if [[ "$REJECTED" -ge 1 ]]; then
  pass "rejected = $REJECTED (at least 1 item caught by validation)"
  detail "Validation correctly rejected items with bad data."
  log "RESULT: PASS — rejected = $REJECTED"
else
  fail_check "rejected = $REJECTED (expected >= 1)"
  fix "Check app/validators/output_validator.py validation rules"
  detail "At least one batch item should fail validation (e.g., low confidence,"
  detail "hallucinated category, or missing source docs)."
  log "RESULT: FAIL — rejected = $REJECTED (expected >= 1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 3d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/4" "Examine individual validation failures" "3d — Guardrails catch hallucinated categories"

VALIDATE_CMD='curl -s -X POST http://localhost:8000/validate/output -H "Content-Type: application/json" -d '"'"'{"output": {"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}}'"'"''
show_command "$VALIDATE_CMD"

log_divider "STEP 2: Examine individual validation failures (LO 3d)"
log "COMMAND:"
log "  $VALIDATE_CMD"
log ""
log "INPUT PAYLOAD:"
log '  {"output": {"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}}'
log ""

VALIDATE_RESPONSE=$(curl -sf -X POST "$API/validate/output" \
  -H "Content-Type: application/json" \
  -d '{"output": {"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}}')
echo "$VALIDATE_RESPONSE" | python3 -m json.tool > "$TMPD/step2.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

IS_VALID=$(echo "$VALIDATE_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['is_valid'])")
CHECKS=$(echo "$VALIDATE_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('checks', []):
    print(f\"{c['check']}: {c['result']}\")
")
VAL_ERRORS=$(echo "$VALIDATE_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
errs = data.get('errors', [])
print('; '.join(errs) if errs else 'none')
")
CATEGORY_CHECK=$(echo "$VALIDATE_RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for c in data.get('checks', []):
    if 'category' in c.get('check', '').lower():
        print(c['result'])
        break
else:
    print('NOT_FOUND')
")

highlight "is_valid:" "$IS_VALID"
highlight "category check:" "$CATEGORY_CHECK"
field     "checks:" ""
while IFS= read -r line; do
  printf "    ${GRAY}%s${NC}\n" "$line"
done <<< "$CHECKS"
field     "errors:" "$VAL_ERRORS"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  is_valid: $IS_VALID"
log "  checks:"
while IFS= read -r line; do
  log "    $line"
done <<< "$CHECKS"
log "  errors: $VAL_ERRORS"
log ""
log "LO COVERAGE:"
log "  3d — Guardrails rejected hallucinated category 'electronics_repair'"

# Check: is_valid = False
if [[ "$IS_VALID" == "False" || "$IS_VALID" == "false" ]]; then
  pass "is_valid = $IS_VALID (hallucinated category correctly rejected)"
  log "RESULT: PASS — is_valid = $IS_VALID"
else
  fail_check "is_valid = $IS_VALID (expected false)"
  fix "Check VALIDATION_RULES['allowed_categories'] in app/validators/output_validator.py"
  detail "The category 'electronics_repair' should not be in the allowed list."
  detail "The validator should reject it and return is_valid=false."
  log "RESULT: FAIL — is_valid = $IS_VALID (expected false)"
fi

# Check: category check = FAIL
if [[ "$CATEGORY_CHECK" == "FAIL" ]]; then
  pass "category check = FAIL (electronics_repair not in allowed list)"
  detail "One FAIL is enough to reject. The system validates structure,"
  detail "grounding, confidence, and category independently."
  log "RESULT: PASS — category check = FAIL"
else
  fail_check "category check = $CATEGORY_CHECK (expected FAIL)"
  fix "Verify allowed_categories in app/validators/output_validator.py"
  detail "The category validation check should return FAIL for any category"
  detail "not in the allowed list."
  log "RESULT: FAIL — category check = $CATEGORY_CHECK (expected FAIL)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 3c)
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/4" "Verify pipeline run summary" "3c — Operational monitoring of batch runs"
show_command "curl -s $API/pipeline/runs | python3 -m json.tool"

log_divider "STEP 3: Verify pipeline run summary (LO 3c)"
log "COMMAND:"
log "  curl -s $API/pipeline/runs | python3 -m json.tool"
log ""

RUNS_RESPONSE=$(curl -sf "$API/pipeline/runs")
echo "$RUNS_RESPONSE" | python3 -m json.tool > "$TMPD/step3.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step3.json" >> "$LOG"
log ""

RUN_COUNT=$(echo "$RUNS_RESPONSE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
RUN_ACCEPTED=$(echo "$RUNS_RESPONSE" | python3 -c "
import json, sys
runs = json.load(sys.stdin)
for r in runs:
    if r.get('accepted', 0) > 0 or r.get('rejected', 0) > 0:
        print(r.get('accepted', 0))
        break
else:
    print(0)
")
RUN_REJECTED=$(echo "$RUNS_RESPONSE" | python3 -c "
import json, sys
runs = json.load(sys.stdin)
for r in runs:
    if r.get('accepted', 0) > 0 or r.get('rejected', 0) > 0:
        print(r.get('rejected', 0))
        break
else:
    print(0)
")
RUN_STATUS=$(echo "$RUNS_RESPONSE" | python3 -c "
import json, sys
runs = json.load(sys.stdin)
for r in runs:
    if r.get('accepted', 0) > 0 or r.get('rejected', 0) > 0:
        print(r.get('status', 'unknown'))
        break
else:
    print('no qualifying run')
")

highlight "accepted_count:" "$RUN_ACCEPTED"
highlight "rejected_count:" "$RUN_REJECTED"
field     "pipeline runs found:" "$RUN_COUNT"
field     "latest run status:" "$RUN_STATUS"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  pipeline_runs_found: $RUN_COUNT"
log "  latest_run_status:   $RUN_STATUS"
log "  accepted_count:      $RUN_ACCEPTED"
log "  rejected_count:      $RUN_REJECTED"
log ""
log "LO COVERAGE:"
log "  3c — Pipeline monitoring shows accepted=$RUN_ACCEPTED, rejected=$RUN_REJECTED per run"

# Check: at least one run exists
if [[ "$RUN_COUNT" -ge 1 ]]; then
  pass "pipeline/runs returned $RUN_COUNT run(s)"
  log "RESULT: PASS — $RUN_COUNT run(s) found"
else
  fail_check "pipeline/runs returned 0 runs (expected >= 1)"
  fix "Re-run Step 1 to create a pipeline run record"
  detail "The batch-enrich call in Step 1 should have created a pipeline run."
  log "RESULT: FAIL — no runs found"
fi

# Check: run has accepted count
if [[ "$RUN_ACCEPTED" -ge 1 ]]; then
  pass "run has accepted_count = $RUN_ACCEPTED"
  log "RESULT: PASS — accepted_count = $RUN_ACCEPTED"
else
  fail_check "run has accepted_count = $RUN_ACCEPTED (expected >= 1)"
  fix "module4/scripts/demo-reset.sh && module4/scripts/preflight_check.sh"
  detail "The batch run should have at least one accepted item."
  log "RESULT: FAIL — accepted_count = $RUN_ACCEPTED"
fi

# Check: run has rejected count
if [[ "$RUN_REJECTED" -ge 1 ]]; then
  pass "run has rejected_count = $RUN_REJECTED"
  detail "Monitoring correctly reports both accepted and rejected counts."
  log "RESULT: PASS — rejected_count = $RUN_REJECTED"
else
  fail_check "run has rejected_count = $RUN_REJECTED (expected >= 1)"
  fix "Check validation rules in app/validators/output_validator.py"
  detail "The batch should contain items that fail validation."
  log "RESULT: FAIL — rejected_count = $RUN_REJECTED"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 1d, 3d)
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/4" "Verify trusted output and quarantine" "1d, 3d — Data flow end state with validation routing"
show_command "curl -s $API/admin/metrics | python3 -m json.tool"

log_divider "STEP 4: Verify trusted output and quarantine (LO 1d, 3d)"
log "COMMAND:"
log "  curl -s $API/admin/metrics | python3 -m json.tool"
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
log "  1d — Data flow complete: accepted rows in trusted ($TRUSTED), rejected in quarantine ($QUARANTINE)"
log "  3d — Guardrails enforced: bad outputs routed to quarantine, not trusted tables"

# Check: trusted >= 1
if [[ "$TRUSTED" -ge 1 ]]; then
  pass "trusted_enriched = $TRUSTED (validated outputs promoted to trusted table)"
  detail "Good data passed all validation checks and reached the trusted layer."
  log "RESULT: PASS — trusted_enriched = $TRUSTED"
else
  fail_check "trusted_enriched = $TRUSTED (expected >= 1)"
  fix "module4/scripts/demo-reset.sh && module4/scripts/preflight_check.sh"
  detail "At least one batch item should pass validation and be promoted"
  detail "to the trusted.feedback_enriched table."
  log "RESULT: FAIL — trusted_enriched = $TRUSTED (expected >= 1)"
fi

# Check: quarantine >= 1
if [[ "$QUARANTINE" -ge 1 ]]; then
  pass "quarantine_outputs = $QUARANTINE (rejected outputs quarantined with reasons)"
  detail "Rejecting bad output is a successful pipeline outcome."
  log "RESULT: PASS — quarantine_outputs = $QUARANTINE"
else
  fail_check "quarantine_outputs = $QUARANTINE (expected >= 1)"
  fix "Check validation logic in app/validators/output_validator.py"
  detail "At least one batch item should fail validation and be routed"
  detail "to the quarantine.llm_outputs table with rejection reasons."
  log "RESULT: FAIL — quarantine_outputs = $QUARANTINE (expected >= 1)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 1d | Step 4 | trusted=$TRUSTED rows promoted, quarantine=$QUARANTINE rows rejected — data flow routes by validation |"
log "| 3c | Step 1, Step 3 | Batch total=$TOTAL, accepted=$ACCEPTED, rejected=$REJECTED; pipeline run monitoring works |"
log "| 3d | Step 1, Step 2, Step 4 | Validation catches hallucinated category; rejected items quarantined with reasons |"
log ""
log "All 3 learning objectives (1d, 3c, 3d) are covered by the 4 demo steps."

echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}1d${NC}  Step 4      ${DIM}Data flow: trusted=$TRUSTED promoted, quarantine=$QUARANTINE rejected${NC}\n"
printf "  ${BLUE}3c${NC}  Steps 1, 3  ${DIM}Batch processing + pipeline run monitoring${NC}\n"
printf "  ${BLUE}3d${NC}  Steps 1, 2, 4  ${DIM}Validation guardrails catch hallucinated outputs${NC}\n"

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
  printf "  ${BLUE}Quick fix:${NC} module4/scripts/demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module4/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
  log ""
  log "HOW TO FIX:"
  log "  1. Reset the environment:"
  log "     module4/scripts/demo-reset.sh"
  log ""
  log "  2. Rerun the preflight check:"
  log "     module4/scripts/preflight_check.sh"
  log ""
  log "  3. If reset does not fix it, check:"
  log "     - Is the server running? curl -s http://localhost:8000/health"
  log "     - Are seed files present? ls data/seed/"
  log "     - Are payloads present? ls data/payloads/"
  log "     - Run full setup: ./environment-setup/install-macos-requirements.sh"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module4/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
