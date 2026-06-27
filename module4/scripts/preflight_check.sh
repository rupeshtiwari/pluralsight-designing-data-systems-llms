#!/usr/bin/env bash
set -u
# Module 4 — Clip 4 preflight: runs every demo step in the order it will be
# recorded and verifies each one produces the output the README expects.
# Logs to module4/preflight_log.txt.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="module4/preflight_log.txt"
exec > >(tee "$LOG") 2>&1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[38;2;42;236;250m'
BOLD='\033[1m'
NC='\033[0m'
API="http://localhost:8000"

pass()   { printf "  ${GREEN}✓ PASS${NC}  %s\n" "$1"; }
warnit() { printf "  ${YELLOW}! WARN${NC}  %s\n" "$1"; }
failit() { printf "  ${RED}✗ FAIL${NC}  %s\n" "$1"; printf "         ${YELLOW}fix:${NC} %s\n" "$2"; ALL_PASS=0; }
section() {
  printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "  ${BOLD}%s${NC}\n" "$1"
  printf "  ${YELLOW}%s${NC}\n" "$2"
  printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

ALL_PASS=1

printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║${NC}  ${BOLD}Module 4 Clip 4 — Preflight Check${NC}                          ${BLUE}║${NC}\n"
printf "${BLUE}║${NC}  ${BOLD}Rejecting hallucinated and schema-drifted LLM outputs${NC}      ${BLUE}║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
printf "\n"

printf "  Checking server at $API...\n"
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  failit "FastAPI not reachable on port 8000" "./scripts/module4-demo-reset.sh"
  echo "Aborting — server must be up."
  exit 1
fi
pass "Server is healthy"

# ── Clean-slate precondition (auto-reset) ───────────────────────────────────
# Preflight must run on an empty warehouse so the assertions about row counts
# (1 trusted, 4 quarantine, 1 pipeline_runs row) reflect THIS run only. If
# pipeline_runs is non-empty (a previous demo or preflight is still seeded),
# auto-run the reset script so preflight can proceed without manual cleanup.
PRECHECK_RUNS=$(curl -sf "$API/pipeline/runs?limit=10" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get('runs',[])))" 2>/dev/null || echo "0")
if [[ "$PRECHECK_RUNS" -gt 0 ]]; then
  printf "\n  ${YELLOW}! NOTE${NC}  pipeline_runs already has %s row(s) — auto-resetting for a clean slate...\n" "$PRECHECK_RUNS"
  if "$PROJECT_ROOT/scripts/module4-demo-reset.sh" >/dev/null 2>&1; then
    sleep 2
    PRECHECK_RUNS=$(curl -sf "$API/pipeline/runs?limit=10" \
      | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get('runs',[])))" 2>/dev/null || echo "0")
    if [[ "$PRECHECK_RUNS" -gt 0 ]]; then
      failit "Auto-reset ran but pipeline_runs still has $PRECHECK_RUNS row(s)" \
             "Inspect logs/server.log + run ./scripts/module4-demo-reset.sh manually"
      exit 1
    fi
    pass "Auto-reset complete: pipeline_runs is empty"
  else
    failit "Auto-reset failed" "./scripts/module4-demo-reset.sh   then re-run this script"
    exit 1
  fi
else
  pass "Clean slate confirmed: pipeline_runs is empty"
fi

# ── STEP 1/7 ────────────────────────────────────────────────────────────────
section "STEP 1/7: Batch input risk preview" "LO 3d — surfaces ambiguous, stale, invalid, schema-drift"

printf "\n  Command:\n  \$ module4/scripts/batch_input_risk.sh\n\n"
RISK=$(module4/scripts/batch_input_risk.sh 2>&1 || true)
echo "$RISK" | sed 's/^/  /'

if echo "$RISK" | grep -q "ambiguous feedback"; then pass "outline phrase 'ambiguous feedback' surfaced"; else failit "'ambiguous feedback' missing" "Edit module4_validation_batch.json record 302 _intent.input_risk"; fi
if echo "$RISK" | grep -q "stale or missing reference context"; then pass "outline phrase 'stale or missing reference context' surfaced"; else failit "'stale or missing reference context' missing" "Edit module4_validation_batch.json record 304 _intent.input_risk"; fi
if echo "$RISK" | grep -q "invalid category value"; then pass "outline phrase 'invalid category value' surfaced"; else failit "'invalid category value' missing" "Edit module4_validation_batch.json record 303 _intent.input_risk"; fi

# ── STEP 2/7 ────────────────────────────────────────────────────────────────
section "STEP 2/7: Show the five validation checks" "LO 3d — schema, source_id, category, confidence, disposition"

printf "\n  Command:\n  \$ curl -s $API/validate/rules | python3 scripts/fmt.py --type validation-rules\n\n"
RULES_JSON=$(curl -sf "$API/validate/rules")
echo "$RULES_JSON" | python3 scripts/fmt.py --type validation-rules \
  --title "Validation rules enforced after generation" \
  --why "Schema, source_id, category, confidence, disposition" 2>&1 | sed 's/^/  /'

if [[ -z "$RULES_JSON" ]]; then
  failit "/validate/rules returned empty" "Check app/routers/validation.py is mounted"
else
  CT=$(echo "$RULES_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('confidence_threshold',''))")
  CATS=$(echo "$RULES_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('allowed_categories',[])))")
  if [[ -n "$CT" ]]; then pass "confidence_threshold present: $CT"; else failit "confidence_threshold missing" "Verify VALIDATION_RULES in app/validators/output_validator.py"; fi
  if [[ "$CATS" -ge 3 ]]; then pass "allowed_categories list populated: $CATS values"; else failit "allowed_categories too small" "Add categories in app/config.py ALLOWED_CATEGORIES"; fi
fi

# ── STEP 3/7 ────────────────────────────────────────────────────────────────
section "STEP 3/7: Trigger bad-data batch via /pipeline/validate-batch" "LO 3c, 3d — one valid + four engineered failures"

printf "\n  Command:\n  \$ curl -s -X POST $API/pipeline/validate-batch -d @data/payloads/module4_validation_batch.json\n\n"
BATCH=$(curl -sf -X POST "$API/pipeline/validate-batch" \
  -H "Content-Type: application/json" \
  -d "{\"items\": $(cat data/payloads/module4_validation_batch.json)}")

if [[ -z "$BATCH" ]]; then
  failit "/pipeline/validate-batch returned empty" "Verify endpoint is registered in app/routers/pipeline.py"
  BATCH_ID=""
else
  BATCH_ID=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('batch_id',''))")
  ACC=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('accepted_count',0))")
  REJ=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('rejected_count',0))")
  TOT=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('total',0))")

  echo "$BATCH" | python3 scripts/fmt.py --type validate-batch-summary \
    --title "Validation batch with bad LLM outputs" \
    --why "5 records: 1 valid, 4 engineered to fail one check each" 2>&1 | sed 's/^/  /'

  if [[ -n "$BATCH_ID" ]]; then pass "batch_id assigned: $BATCH_ID"; else failit "batch_id missing" "Endpoint must return batch_id at top level"; fi
  if [[ "$TOT" == "5" ]]; then pass "total = 5 (matches payload)"; else failit "total != 5 (got $TOT)" "Check module4_validation_batch.json has 5 items"; fi
  if [[ "$ACC" -ge 1 ]]; then pass "accepted_count >= 1 (got $ACC)"; else failit "accepted_count = 0" "Verify first record passes every check"; fi
  if [[ "$REJ" -ge 1 ]]; then pass "rejected_count >= 1 (got $REJ)"; else failit "rejected_count = 0" "Verify other records trigger engineered failures"; fi
fi

# ── STEP 4/7 ────────────────────────────────────────────────────────────────
section "STEP 4/7: Confirm valid and invalid outcomes" "LO 3d — one valid + reasoned rejections + best-practice callout"

if [[ -z "$BATCH" ]]; then
  failit "skipped — Step 3 produced no batch payload" "Make Step 3 pass first"
else
  echo "$BATCH" | python3 scripts/fmt.py --type validate-batch-details \
    --title "Per-record validation outcomes for $BATCH_ID" \
    --why "One ★ row per record + best-practice callout" 2>&1 | sed 's/^/  /'

  REASONS=$(echo "$BATCH" | python3 -c "import json,sys;d=json.load(sys.stdin);[print(r.get('reason','')) for r in d.get('details',[]) if r.get('validation_status')=='rejected']")
  REASON_COUNT=$(echo "$REASONS" | grep -c '[a-zA-Z]' || true)
  if [[ "$REASON_COUNT" -ge 1 ]]; then
    pass "at least one rejected record carries a reason ($REASON_COUNT total)"
    pass "first rejection reason: $(echo "$REASONS" | head -1)"
  else
    failit "no rejection reasons returned" "Validator must populate result['errors'] for failed checks"
  fi
  VALID_COUNT=$(echo "$BATCH" | python3 -c "import json,sys;d=json.load(sys.stdin);print(sum(1 for r in d.get('details',[]) if r.get('validation_status')=='accepted'))")
  if [[ "$VALID_COUNT" -ge 1 ]]; then
    pass "at least one accepted record present (count=$VALID_COUNT)"
  else
    failit "zero accepted records" "Check first payload record's enriched payload satisfies every rule"
  fi
  STEP4_OUT=$(echo "$BATCH" | python3 scripts/fmt.py --type validate-batch-details 2>&1)
  if echo "$STEP4_OUT" | grep -q "best practice"; then
    pass "★ best practice callout rendered: 'Rejecting bad output is a successful pipeline outcome'"
  else
    failit "best practice line missing from validate-batch-details output" "Re-check fmt_validate_batch_details for trailing ★ best practice append"
  fi
fi

# ── STEP 5/7 ────────────────────────────────────────────────────────────────
section "STEP 5/7: Airflow UI routing proof" "LO 3c — same task states Airflow grid shows: validation_branch + write_trusted + write_quarantine"

printf "\n  Command:\n  \$ module4/scripts/airflow_ui_proof.sh\n\n"
AIRFLOW_OUT=$(module4/scripts/airflow_ui_proof.sh 2>&1 || true)
echo "$AIRFLOW_OUT" | sed 's/^/  /'

if echo "$AIRFLOW_OUT" | grep -q "airflow_ui_url"; then
  pass "airflow_ui_url printed for browser pivot"
else
  warnit "airflow_ui_url line missing — visible URL helps recording cut to the UI"
fi

# Strict: parse the three task states and FAIL if any of them is not 'success'.
# Strip ANSI color codes first — the airflow_ui_proof.sh output wraps each
# value in ANSI sequences which break naive sed/grep substring extraction.
AIRFLOW_CLEAN=$(printf '%s' "$AIRFLOW_OUT" | sed -E 's/\x1b\[[0-9;]*m//g')
AF_RUN_STATE=$(printf '%s\n' "$AIRFLOW_CLEAN" | awk '/validation_branch state:/ {print $NF; exit}')
AF_TRUSTED=$(printf '%s\n' "$AIRFLOW_CLEAN" | awk '/write_trusted state:/ {print $NF; exit}')
AF_QUAR=$(printf '%s\n' "$AIRFLOW_CLEAN" | awk '/write_quarantine state:/ {print $NF; exit}')

if echo "$AIRFLOW_OUT" | grep -q "NOTE.*backend reads as: memory"; then
  warnit "Airflow not running — script printed UI guidance instead (start Docker + reset)"
else
  if [[ "$AF_RUN_STATE" == "success" ]]; then
    pass "validation_branch state = success"
  else
    failit "validation_branch state = '$AF_RUN_STATE' (expected 'success')" "Verify DAG triggered + finished; check Airflow scheduler logs"
  fi
  if [[ "$AF_TRUSTED" == "success" ]]; then
    pass "write_trusted state = success"
  else
    failit "write_trusted state = '$AF_TRUSTED' (expected 'success' — both branches must run on a mixed batch)" "Check data/payloads/module4_airflow_trigger.json includes feedback_texts override and the DAG reads it"
  fi
  if [[ "$AF_QUAR" == "success" ]]; then
    pass "write_quarantine state = success"
  else
    failit "write_quarantine state = '$AF_QUAR' (expected 'success' — both branches must run on a mixed batch)" "Check data/payloads/module4_airflow_trigger.json includes feedback_texts override"
  fi
fi

# ── STEP 6/7 ────────────────────────────────────────────────────────────────
section "STEP 6/7: PostgreSQL pipeline_runs aggregate" "LO 3c — accepted, rejected, validation_summary"

printf "\n  Command:\n  \$ curl -s '$API/pipeline/runs?limit=3' | python3 scripts/fmt.py --type pipeline-runs\n\n"
RUNS=$(curl -sf "$API/pipeline/runs?limit=3")
echo "$RUNS" | python3 scripts/fmt.py --type pipeline-runs \
  --title "pipeline_runs aggregate (PostgreSQL)" \
  --why "One row per batch — accepted, rejected, validation_summary" 2>&1 | sed 's/^/  /' | tail -40

ROWS=$(echo "$RUNS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get('runs',[])))")
if [[ "$ROWS" -ge 1 ]]; then pass "pipeline_runs returned $ROWS row(s)"; else failit "pipeline_runs returned no rows" "Verify Step 3 persisted via postgres.insert_pipeline_run"; fi

HAS_SUMMARY=$(echo "$RUNS" | python3 -c "import json,sys;d=json.load(sys.stdin);rows=d if isinstance(d,list) else d.get('runs',[]);print('yes' if any(r.get('validation_summary') for r in rows) else 'no')")
if [[ "$HAS_SUMMARY" == "yes" ]]; then pass "at least one row carries validation_summary"; else warnit "no row has validation_summary"; fi

# ── STEP 7/7 ────────────────────────────────────────────────────────────────
section "STEP 7/7: DuckDB CLI — trusted + quarantine schemas" "LO 1d, 3d — literal table names + reason preserved"

printf "\n  Command:\n  \$ module4/scripts/duckdb_proof.sh\n\n"
DBOUT=$(module4/scripts/duckdb_proof.sh 2>&1 || true)
echo "$DBOUT" | sed 's/^/  /' | head -40

if echo "$DBOUT" | grep -q "trusted.feedback_enriched"; then pass "trusted.feedback_enriched rendered literally"; else failit "trusted.feedback_enriched missing" "Check module4/scripts/duckdb_proof.sh"; fi
if echo "$DBOUT" | grep -q "quarantine.llm_outputs"; then pass "quarantine.llm_outputs rendered literally"; else failit "quarantine.llm_outputs missing" "Check module4/scripts/duckdb_proof.sh"; fi
if echo "$DBOUT" | grep -q "validation_errors"; then pass "validation_errors field shown (reason preserved)"; else failit "validation_errors not shown" "duckdb_proof must select validation_errors column"; fi

# ── Closing: Course summary ─────────────────────────────────────────────────
section "CLOSING: Course summary slide" "Four design contracts the course delivered"

printf "\n  Command:\n  \$ module4/scripts/course_summary.sh\n\n"
SUM=$(module4/scripts/course_summary.sh 2>&1 || true)
echo "$SUM" | sed 's/^/  /'

if echo "$SUM" | grep -q "LLM placement"; then pass "contract 1 — LLM placement present"; else failit "'LLM placement' missing" "Edit module4/scripts/course_summary.sh"; fi
if echo "$SUM" | grep -q "Boundary contracts"; then pass "contract 2 — Boundary contracts present"; else failit "'Boundary contracts' missing" "Edit module4/scripts/course_summary.sh"; fi
if echo "$SUM" | grep -q "Orchestration control"; then pass "contract 3 — Orchestration control present"; else failit "'Orchestration control' missing" "Edit module4/scripts/course_summary.sh"; fi
if echo "$SUM" | grep -q "Output validation"; then pass "contract 4 — Output validation present"; else failit "'Output validation' missing" "Edit module4/scripts/course_summary.sh"; fi

# ── LO coverage ─────────────────────────────────────────────────────────────
printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "  ${BOLD}LO COVERAGE${NC}\n"
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
printf "  1d  Steps 3, 7        Data flow design — LLM output → validation → trusted vs quarantine\n"
printf "  3c  Steps 3, 5, 6     Trigger + monitor: validate-batch + Airflow UI + pipeline_runs\n"
printf "  3d  Steps 1, 2, 4, 7  Guardrails: input risk, rules, reasons + callout, persisted disposition\n\n"

# ── Final verdict ───────────────────────────────────────────────────────────
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ALL_PASS -eq 1 ]]; then
  printf "  ${GREEN}${BOLD}✓ ALL CHECKS PASSED — Module 4 Clip 4 demo is ready${NC}\n"
else
  printf "  ${RED}${BOLD}✗ ONE OR MORE CHECKS FAILED — fix above before recording${NC}\n"
fi
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

printf "  Log saved to: $LOG\n\n"
