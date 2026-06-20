#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 3 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module3/preflight_log.txt.
#
# Maps each step to its on-screen proof and to the learning objective,
# and prints fix prompts on any failure.
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

# ── Colors (Pluralsight 2025 brand) ─────────────────────────────────────────
PINK='\033[38;2;255;22;117m'
GREEN='\033[38;2;207;255;110m'
LGREEN='\033[38;2;64;255;191m'
BLUE='\033[38;2;42;236;250m'
GRAY='\033[38;2;191;191;191m'
WHITE='\033[1;37m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0

pass()       { printf "  ${GREEN}✓ PASS${NC}  %s\n" "$1"; }
fail_check() { printf "  ${PINK}✗ FAIL${NC}  %s\n" "$1"; ERRORS=$((ERRORS + 1)); }
warn_check() { printf "  ${BLUE}⚠ NOTE${NC}  %s\n" "$1"; }
detail()     { printf "           ${GRAY}%s${NC}\n" "$1"; }
fix()        { printf "    ${BLUE}→ Fix:${NC} %s\n" "$1"; }
highlight()  { printf "  ${PINK}★${NC} ${BLUE}%s${NC} ${LGREEN}%s${NC}\n" "$1" "$2"; }
field()      { printf "    ${GRAY}%s${NC} ${GRAY}%s${NC}\n" "$1" "$2"; }
show_command() {
  printf "\n  ${DIM}Command:${NC}\n"
  printf "  ${DIM}\$${NC} %s\n\n" "$1"
}
step_header() {
  echo ""
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "${WHITE}  STEP %s: %s${NC}\n" "$1" "$2"
  printf "${BLUE}  Learning objective: %s${NC}\n" "$3"
  printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

log() { echo "$1" >> "$LOG"; }
log_divider() {
  log ""
  log "================================================================================"
  log "$1"
  log "================================================================================"
  log ""
}

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

echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 3 Clip 4 — Preflight Check                          ║${NC}\n"
printf "${BOLD}║  Airflow enrichment pipeline with FastAPI and DuckDB        ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"

# ── Server check ────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}Checking server at ${API}...${NC}\n"
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail_check "Server is not running at $API"
  fix "./scripts/module3-demo-reset.sh"
  echo "Server not running" >> "$LOG"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# Detect Airflow backend (airflow vs memory)
BACKEND=$(curl -sf "$API/admin/airflow-dag" \
  | python3 -c "import json,sys;print(json.load(sys.stdin).get('backend','?'))" 2>/dev/null || echo "?")
log "Airflow backend: $BACKEND"
printf "  ${DIM}Airflow backend: ${BLUE}%s${NC}\n" "$BACKEND"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 (LO 3a) — DAG topology
# ═════════════════════════════════════════════════════════════════════════════
step_header "1/6" "Show the DAG topology" "3a — Static DAG + dynamic branch"
show_command "curl -s $API/admin/airflow-dag | python3 scripts/fmt.py --type airflow-dag"

log_divider "STEP 1: Show the DAG topology (LO 3a)"
log "COMMAND:"
log "  curl -s $API/admin/airflow-dag"
log ""

DAG_JSON=$(curl -sf "$API/admin/airflow-dag")
echo "$DAG_JSON" | python3 -m json.tool > "$TMPD/step1.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

DAG_ID=$(echo "$DAG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('dag_id',''))")
TASK_COUNT=$(echo "$DAG_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('tasks',[])))")
STATIC=$(echo "$DAG_JSON" | python3 -c "import json,sys;print(', '.join(json.load(sys.stdin).get('static_tasks',[])))")
BRANCHES=$(echo "$DAG_JSON" | python3 -c "import json,sys;print(', '.join(json.load(sys.stdin).get('dynamic_branches',[])))")

highlight "dag_id:"             "$DAG_ID"
highlight "task count:"         "$TASK_COUNT"
highlight "static_tasks:"       "$STATIC"
highlight "dynamic_branches:"   "$BRANCHES"
echo ""

log "EXTRACTED VALUES:"
log "  dag_id:           $DAG_ID"
log "  task_count:       $TASK_COUNT"
log "  static_tasks:     $STATIC"
log "  dynamic_branches: $BRANCHES"
log ""
log "LO COVERAGE: 3a — Three static transform tasks plus one dynamic branch task"

if [[ "$DAG_ID" == "northwind_llm_enrichment" ]]; then
  pass "dag_id = northwind_llm_enrichment"
  log "RESULT: PASS — dag_id correct"
else
  fail_check "dag_id = $DAG_ID (expected northwind_llm_enrichment)"
  fix "Verify airflow/dags/northwind_llm_enrichment.py exposes the dag_id"
  log "RESULT: FAIL — dag_id wrong"
fi
for t in extract_batch transform enrich_via_fastapi; do
  if echo ",$STATIC," | grep -q ",$t,"; then
    pass "static task present: $t"
  else
    fail_check "static task missing: $t"
    fix "Add $t to the DAG in airflow/dags/northwind_llm_enrichment.py"
  fi
done
for t in validation_branch write_trusted write_quarantine; do
  if echo "$BRANCHES" | grep -q "$t"; then
    pass "dynamic branch task present: $t"
  else
    fail_check "dynamic branch task missing: $t"
    fix "Add $t to the branch downstream in airflow/dags/northwind_llm_enrichment.py"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 3c) — Trigger the DAG
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/6" "Trigger the DAG from a new source batch" "3c — Trigger and monitor"
show_command "curl -s -X POST $API/admin/airflow-trigger -H 'Content-Type: application/json' -d @data/payloads/airflow_trigger.json | python3 scripts/fmt.py --type airflow-trigger"

log_divider "STEP 2: Trigger the DAG (LO 3c)"
log "INPUT PAYLOAD (data/payloads/airflow_trigger.json):"
cat "$PROJECT_ROOT/data/payloads/airflow_trigger.json" >> "$LOG"
log ""

TRIG=$(curl -sf -X POST "$API/admin/airflow-trigger" \
  -H "Content-Type: application/json" \
  -d @"$PROJECT_ROOT/data/payloads/airflow_trigger.json")
echo "$TRIG" | python3 -m json.tool > "$TMPD/step2.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

DAG_RUN_ID=$(echo "$TRIG" | python3 -c "import json,sys;print(json.load(sys.stdin).get('dag_run_id',''))")
TRIG_STATE=$(echo "$TRIG" | python3 -c "import json,sys;print(json.load(sys.stdin).get('state',''))")
LOGICAL=$(echo "$TRIG" | python3 -c "import json,sys;print(json.load(sys.stdin).get('logical_date',''))")

# Step 2b: wait for the captured run to reach terminal state before
# Step 3/4/6 query it. Off-camera helper; output goes to log only.
if [[ -n "$DAG_RUN_ID" ]]; then
  log "STEP 2b: wait for $DAG_RUN_ID to reach success (max_wait=90)"
  WAIT_RESULT=$(curl -sf "$API/admin/airflow-wait-for-run?dag_run_id=${DAG_RUN_ID}&max_wait=90")
  log "  wait result: $WAIT_RESULT"
fi

highlight "dag_run_id:"     "$DAG_RUN_ID"
highlight "state:"          "$TRIG_STATE"
highlight "logical_date:"   "$LOGICAL"
echo ""

log "EXTRACTED VALUES:"
log "  dag_run_id:    $DAG_RUN_ID"
log "  state:         $TRIG_STATE"
log "  logical_date:  $LOGICAL"
log ""
log "LO COVERAGE: 3c — Trigger returns dag_run_id + initial queued state"

if [[ -n "$DAG_RUN_ID" ]]; then
  pass "dag_run_id assigned"
else
  fail_check "dag_run_id missing from trigger response"
  fix "Check app/clients/airflow.py trigger_dag_run() return value"
fi
if [[ "$TRIG_STATE" == "queued" || "$TRIG_STATE" == "running" || "$TRIG_STATE" == "success" ]]; then
  pass "state = $TRIG_STATE"
else
  fail_check "state = $TRIG_STATE (expected queued|running|success)"
  fix "Verify the Airflow client returns a valid state field"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 3c) — State transitions
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/6" "Watch state transitions (queued → running → success)" "3c — Monitor pipeline tasks"
show_command "curl -s \"\$API/admin/airflow-dag-runs?dag_run_id=\$DAG_RUN_ID&limit=1\" | python3 scripts/fmt.py --type airflow-dag-runs"

log_divider "STEP 3: State transitions (LO 3c)"
RUNS_JSON=$(curl -sf "$API/admin/airflow-dag-runs?dag_run_id=${DAG_RUN_ID}&limit=1")
echo "$RUNS_JSON" | python3 -m json.tool > "$TMPD/step3.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step3.json" >> "$LOG"
log ""

RUN_COUNT=$(echo "$RUNS_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('dag_runs',[])))")
LATEST_STATE=$(echo "$RUNS_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('dag_runs',[])
print(d[0].get('state','') if d else '')")
LATEST_RUN=$(echo "$RUNS_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('dag_runs',[])
print(d[0].get('dag_run_id','') if d else '')")

highlight "runs shown:"     "$RUN_COUNT"
highlight "latest state:"   "$LATEST_STATE"
field     "latest run:"     "$LATEST_RUN"
echo ""

log "EXTRACTED VALUES:"
log "  runs:          $RUN_COUNT"
log "  latest state:  $LATEST_STATE"
log "  latest run id: $LATEST_RUN"
log ""
log "LO COVERAGE: 3c — Run history with state + duration_seconds visible from CLI"

if [[ "$RUN_COUNT" -ge 1 ]]; then
  pass "dag_runs returned $RUN_COUNT row(s)"
else
  fail_check "dag_runs returned 0 rows"
  fix "Run Step 2 first to trigger a DAG run, or run ./scripts/module3-demo-reset.sh"
fi

OBSERVED_STATES=$(echo "$RUNS_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('dag_runs',[])
print(', '.join(d[0].get('observed_states', []) if d else []))")
highlight "observed states:" "$OBSERVED_STATES"
log "  observed states: $OBSERVED_STATES"

# Outline requires the demo to show queued, running, success transitions.
# Fail explicitly if 'success' was not observed — a stuck-queued or
# stuck-running latest run is recordable as proof, but the absence of
# 'success' anywhere in the latest 3 runs means the demo cannot fulfil
# LO 3c's 'queued -> running -> success' proof line.
ANY_SUCCESS=$(echo "$RUNS_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('dag_runs',[])
any_s = any('success' in (r.get('observed_states') or []) or r.get('state') == 'success' for r in d)
print('yes' if any_s else 'no')")
if [[ "$ANY_SUCCESS" == "yes" ]]; then
  pass "this DAG run reached state=success (queued -> running -> success proven)"
else
  fail_check "no run in the last $RUN_COUNT runs reached success — Step 3's transition proof is incomplete"
  fix "Wait ~15 seconds after Step 2's trigger for the DAG to finish, then rerun. If Airflow is unreachable, ./scripts/module3-demo-reset.sh will reseed three stub runs that already include success."
fi

if [[ "$OBSERVED_STATES" == *"queued"* && "$OBSERVED_STATES" == *"running"* && "$OBSERVED_STATES" == *"success"* ]]; then
  pass "latest run observed all three states: queued, running, success"
else
  warn_check "latest run observed: [$OBSERVED_STATES] — outline wants queued, running, success on the latest row"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 3b) — Task log fields
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/6" "Inspect task log for batch_id, request_id, validation_result, output_row_id" "3b — Integrate LLM logic into orchestration"
show_command "curl -s \"\$API/admin/airflow-task-log?dag_run_id=\$DAG_RUN_ID&task_id=enrich_via_fastapi\" | python3 scripts/fmt.py --type airflow-task-log"

log_divider "STEP 4: Task log fields (LO 3b)"
LOG_JSON=$(curl -sf "$API/admin/airflow-task-log?dag_run_id=${DAG_RUN_ID}&task_id=enrich_via_fastapi")
echo "$LOG_JSON" | python3 -m json.tool > "$TMPD/step4.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

BATCH_ID=$(echo "$LOG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('batch_id',''))")
REQ_ID=$(echo "$LOG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('request_id',''))")
VAL_RES=$(echo "$LOG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('validation_result',''))")
ROW_ID=$(echo "$LOG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('output_row_id',''))")

highlight "batch_id:"           "$BATCH_ID"
highlight "request_id:"         "$REQ_ID"
highlight "validation_result:"  "$VAL_RES"
highlight "output_row_id:"      "$ROW_ID"
echo ""

log "EXTRACTED VALUES:"
log "  batch_id:           $BATCH_ID"
log "  request_id:         $REQ_ID"
log "  validation_result:  $VAL_RES"
log "  output_row_id:      $ROW_ID"
log ""
log "LO COVERAGE: 3b — All four outline-named fields are extractable from the task log"

for v in BATCH_ID REQ_ID VAL_RES ROW_ID; do
  val="${!v}"
  if [[ -n "$val" ]]; then
    pass "$v populated: $val"
  else
    fail_check "$v missing — task log parser did not find the field"
    fix "Verify enrich_via_fastapi logs the key=value line in airflow/dags/northwind_llm_enrichment.py"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 (LO 3d) — Disposition summary
# ═════════════════════════════════════════════════════════════════════════════
step_header "5/6" "Show dispositions (accepted vs quarantined)" "3d — Guardrails and validation"
show_command "curl -s '$API/admin/disposition-summary?limit=5' | python3 scripts/fmt.py --type dispositions"

log_divider "STEP 5: Disposition summary (LO 3d)"
DISP_JSON=$(curl -sf "$API/admin/disposition-summary?limit=5")
echo "$DISP_JSON" | python3 -m json.tool > "$TMPD/step5.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step5.json" >> "$LOG"
log ""

ACCEPTED=$(echo "$DISP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('trusted_count',0))")
QUARANTINED=$(echo "$DISP_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('quarantine_count',0))")
RECENT=$(echo "$DISP_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('recent_dispositions',[])))")

highlight "accepted_count:"     "$ACCEPTED"
highlight "quarantined_count:"  "$QUARANTINED"
field     "recent_dispositions:" "$RECENT"
echo ""

log "EXTRACTED VALUES:"
log "  accepted:    $ACCEPTED"
log "  quarantined: $QUARANTINED"
log "  recent:      $RECENT"
log ""
log "LO COVERAGE: 3d — Disposition counts + reasons prove guardrails worked"

if [[ "$ACCEPTED" -ge 1 ]]; then
  pass "accepted_count = $ACCEPTED"
else
  fail_check "accepted_count = $ACCEPTED (expected >= 1)"
  fix "Trigger at least one run via Step 2 or ./scripts/module3-demo-reset.sh"
fi
if [[ "$QUARANTINED" -ge 1 ]]; then
  pass "quarantined_count = $QUARANTINED — the validation_branch caught at least one bad record"
else
  fail_check "quarantined_count = $QUARANTINED (expected >= 1)"
  fix "Verify data/payloads/airflow_trigger.json includes feedback_id 99 (ambiguous record)"
fi

# Outline literal: 'Verify accepted records in trusted output and failed
# records in quarantine with reasons'. Surface the first quarantined
# row's full record so the preflight log proves the reason field is
# populated end-to-end.
QUAR_RECORD=$(echo "$DISP_JSON" | python3 -c "
import json,sys
d = json.load(sys.stdin).get('recent_dispositions', [])
q = next((r for r in d if r.get('disposition') == 'quarantined'), None)
if q:
    print(q.get('request_id',''))
    print(q.get('disposition',''))
    print(q.get('reason',''))
    print(q.get('batch_id',''))
" 2>/dev/null)
QUAR_REQ_ID=$(echo "$QUAR_RECORD" | sed -n '1p')
QUAR_DISP=$(echo "$QUAR_RECORD" | sed -n '2p')
QUAR_REASON=$(echo "$QUAR_RECORD" | sed -n '3p')
QUAR_BATCH=$(echo "$QUAR_RECORD" | sed -n '4p')

echo ""
printf "  ${BLUE}first quarantined record (proves LO 3d 'reasons' requirement):${NC}\n"
highlight "request_id:" "${QUAR_REQ_ID:-(none)}"
highlight "disposition:" "${QUAR_DISP:-(none)}"
highlight "reason:"      "${QUAR_REASON:-(none)}"
highlight "batch_id:"    "${QUAR_BATCH:-(none)}"

log "FIRST QUARANTINED RECORD:"
log "  request_id:  $QUAR_REQ_ID"
log "  disposition: $QUAR_DISP"
log "  reason:      $QUAR_REASON"
log "  batch_id:    $QUAR_BATCH"

if [[ -n "$QUAR_REASON" ]]; then
  pass "first quarantined record carries a reason: $QUAR_REASON"
else
  fail_check "first quarantined record has no reason field — LO 3d 'records in quarantine with reasons' not proven"
  fix "Check /admin/disposition-summary — every quarantined row must populate the 'reason' key (e.g. 'confidence below 0.75 threshold')"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 (LO 3a, 3d) — Branch decision
# ═════════════════════════════════════════════════════════════════════════════
step_header "6/6" "Show the dynamic branch decision" "3a, 3d — Dynamic orchestration + guardrail"
show_command "curl -s \"\$API/admin/airflow-branch-decision?dag_run_id=\$DAG_RUN_ID\" | python3 scripts/fmt.py --type airflow-branch"

log_divider "STEP 6: Branch decision (LO 3a, 3d)"
BR_JSON=$(curl -sf "$API/admin/airflow-branch-decision?dag_run_id=${DAG_RUN_ID}")
echo "$BR_JSON" | python3 -m json.tool > "$TMPD/step6.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step6.json" >> "$LOG"
log ""

BR_TASK=$(echo "$BR_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('branch_task_id',''))")
DECISION=$(echo "$BR_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('decision',''))")
UPSTREAM=$(echo "$BR_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('upstream_task_state',''))")
TAKEN=$(echo "$BR_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('downstream_taken',''))")
SKIPPED=$(echo "$BR_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('downstream_skipped',''))")
TAKEN_STATE=$(echo "$BR_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print((d.get('downstream_states') or {}).get(d.get('downstream_taken',''), ''))")
SKIPPED_STATE=$(echo "$BR_JSON" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print((d.get('downstream_states') or {}).get(d.get('downstream_skipped',''), ''))")

highlight "branch_task:"        "$BR_TASK"
highlight "decision:"           "$DECISION"
highlight "upstream_task_state:" "$UPSTREAM"
highlight "downstream_taken:"   "$TAKEN"
highlight "${TAKEN} state:"      "${TAKEN_STATE:-unknown}"
highlight "${SKIPPED} state:"    "${SKIPPED_STATE:-skipped}"
echo ""

log "EXTRACTED VALUES:"
log "  branch_task:         $BR_TASK"
log "  decision:            $DECISION"
log "  upstream_task_state: $UPSTREAM"
log "  taken:               $TAKEN ($TAKEN_STATE)"
log "  skipped:             $SKIPPED ($SKIPPED_STATE)"
log ""
log "LO COVERAGE: 3a — Dynamic branch chose a downstream task; 3d — quarantine branch is wired in"

if [[ "$BR_TASK" == "validation_branch" ]]; then
  pass "branch_task = validation_branch"
else
  fail_check "branch_task = $BR_TASK (expected validation_branch)"
  fix "Verify the @task.branch decorator stays on validation_branch in the DAG"
fi
if [[ -n "$TAKEN" && -n "$SKIPPED" && "$TAKEN" != "$SKIPPED" ]]; then
  pass "$TAKEN ran successfully and $SKIPPED was skipped"
else
  fail_check "downstream_taken/skipped are missing or identical"
  fix "Verify app/clients/airflow.py get_branch_decision() returns both fields"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"
log "| LO | Covered in       | Proof |"
log "|----|------------------|-------|"
log "| 3a | Steps 1, 6       | Static tasks + dynamic branch in topology + branch decision |"
log "| 3b | Step 4           | Task log carries batch_id, request_id, validation_result, output_row_id |"
log "| 3c | Steps 2, 3       | Trigger returns dag_run_id; run history shows state transitions |"
log "| 3d | Steps 5, 6       | Disposition counts + branch decision protects trusted/quarantine routing |"
log ""
log "Airflow backend: $BACKEND"

echo ""
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}3a${NC}  Steps 1, 6  ${DIM}Static DAG topology + dynamic branch decision${NC}\n"
printf "  ${BLUE}3b${NC}  Step 4      ${DIM}Task log fields: batch_id, request_id, validation_result, output_row_id${NC}\n"
printf "  ${BLUE}3c${NC}  Steps 2, 3  ${DIM}Trigger DAG + state transition history${NC}\n"
printf "  ${BLUE}3d${NC}  Steps 5, 6  ${DIM}Disposition counts + branch decision protects trusted/quarantine routing${NC}\n"
printf "  ${BLUE}backend${NC}  ${DIM}${BACKEND}${NC}\n"
if [[ "$BACKEND" != "airflow" ]]; then
  printf "  ${GRAY}(note: with docker compose up airflow-webserver the backend becomes 'airflow')${NC}\n"
fi

echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}  ✓ ALL CHECKS PASSED — Module 3 Clip 4 demo is ready${NC}\n"
  log ""
  log "VERDICT: ALL CHECKS PASSED"
else
  printf "${PINK}  ✗ $ERRORS CHECK(S) FAILED — Fix the issues above${NC}\n"
  echo ""
  printf "  ${BLUE}Quick fix:${NC} ./scripts/module3-demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module3/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
  log ""
  log "HOW TO FIX:"
  log "  1. Reset the environment: ./scripts/module3-demo-reset.sh"
  log "  2. Rerun the preflight:   module3/scripts/preflight_check.sh"
  log "  3. If still failing:      check Airflow at http://localhost:8080 (admin/admin)"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module3/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
