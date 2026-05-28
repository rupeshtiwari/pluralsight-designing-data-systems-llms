#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 2 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module2/preflight_log.txt.
#
# Use the log to verify that demo steps align with the learning objectives.
#
# Usage:
#   module2/scripts/preflight_check.sh
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="$PROJECT_ROOT/module2/preflight_log.txt"
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
MODULE 2 — CLIP 4 PREFLIGHT LOG
================================================================================
Demo:    LangGraph agent triage with PostgreSQL and API tools
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API

Learning objectives:
  2a  Design multi-step decision pipelines so learners can automate complex, but common processes
  2b  Integrate tools (databases, APIs, pipelines) to enable LLM actions

HEADER

# ── Header ──────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 2 Clip 4 — Preflight Check                        ║${NC}\n"
printf "${BOLD}║  LangGraph agent triage with PostgreSQL and API tools      ║${NC}\n"
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
  fix "module2/scripts/demo-reset.sh"
  detail "The reset script will start a fresh server with seed data."
  echo "Server not running" >> "$LOG"
  echo ""
  printf "${PINK}${BOLD}Cannot continue without a running server. Exiting.${NC}\n\n"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 (LO 2a)
# ═════════════════════════════════════════════════════════════════════════════
step_header "1/4" "Show the LangGraph state diagram" "2a — Design multi-step decision pipelines"
show_command "curl -s $API/agent/graph | python3 -m json.tool"

log_divider "STEP 1: Show the LangGraph state diagram (LO 2a)"
log "COMMAND:"
log "  curl -s $API/agent/graph | python3 -m json.tool"
log ""

GRAPH=$(curl -sf "$API/agent/graph")
echo "$GRAPH" | python3 -m json.tool > "$TMPD/step1.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

NODES=$(echo "$GRAPH" | python3 -c "import json,sys; d=json.load(sys.stdin); nodes=d.get('nodes',d.get('graph',{}).get('nodes',[])); print(len(nodes) if isinstance(nodes,list) else len(nodes.keys()))")

highlight "node count:" "$NODES"
echo ""
printf "  ${GRAY}★ = read this value aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  node_count: $NODES"
log ""
log "LO COVERAGE:"
log "  2a — State diagram shows the agent workflow graph with node progression"

# Check: graph returned valid data with nodes
if [[ "$NODES" -gt 0 ]]; then
  pass "State diagram returned with $NODES nodes"
  detail "The workflow graph shows explicit node transitions."
  log "RESULT: PASS — $NODES nodes in graph"
else
  fail_check "State diagram returned 0 nodes (expected nodes in graph)"
  fix "module2/scripts/demo-reset.sh"
  detail "The reset script restarts the server with the agent graph configured."
  log "RESULT: FAIL — no nodes in graph"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 2a, 2b)
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/4" "Run the triage workflow for a data quality incident" "2a, 2b — Multi-step pipeline with tool integration"
show_command 'curl -s http://localhost:8000/agent/triage -H "Content-Type: application/json" -d @data/payloads/anomaly_triage.json | python3 -m json.tool'

log_divider "STEP 2: Run the triage workflow (LO 2a, 2b)"
log "COMMAND:"
log '  curl -s http://localhost:8000/agent/triage -H "Content-Type: application/json" -d @data/payloads/anomaly_triage.json | python3 -m json.tool'
log ""
log "INPUT PAYLOAD (data/payloads/anomaly_triage.json):"
cat "$PROJECT_ROOT/data/payloads/anomaly_triage.json" >> "$LOG"
log ""

TRIAGE=$(curl -sf "$API/agent/triage" \
  -H "Content-Type: application/json" \
  -d @"$PROJECT_ROOT/data/payloads/anomaly_triage.json")
echo "$TRIAGE" | python3 -m json.tool > "$TMPD/step2.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

INCIDENT_ID=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin)['incident_id'])")
SEVERITY=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin)['severity'])")
REVIEW_REQ=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin)['review_required'])")
REC_ACTION=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recommended_action','N/A'))" 2>/dev/null || echo "N/A")
ROOT_CAUSE=$(echo "$TRIAGE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('root_cause_hypothesis','N/A'))" 2>/dev/null || echo "N/A")

highlight "severity:" "$SEVERITY"
highlight "root_cause_hypothesis:" "$ROOT_CAUSE"
highlight "recommended_action:" "$REC_ACTION"
highlight "review_required:" "$REVIEW_REQ"
field     "incident_id:" "$INCIDENT_ID"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  incident_id:          $INCIDENT_ID"
log "  severity:             $SEVERITY"
log "  review_required:      $REVIEW_REQ"
log "  recommended_action:   $REC_ACTION"
log "  root_cause_hypothesis: $ROOT_CAUSE"
log ""
log "LO COVERAGE:"
log "  2a — Agent classified severity based on deviation percentage and designed a multi-step pipeline"
log "  2b — Tools integrated: inspect_metadata, retrieve_runbook, classify_severity, recommend_action"

# Check: incident_id = INC-3001
if [[ "$INCIDENT_ID" == "INC-3001" ]]; then
  pass "incident_id = INC-3001"
  detail "The triage workflow processed the correct incident."
  log "RESULT: PASS — incident_id = INC-3001"
else
  fail_check "incident_id = $INCIDENT_ID (expected INC-3001)"
  fix "module2/scripts/demo-reset.sh"
  detail "The server may have stale state. Reset and retry."
  log "RESULT: FAIL — incident_id = $INCIDENT_ID"
fi

# Check: severity = high
if [[ "$SEVERITY" == "high" ]]; then
  pass "severity = high"
  detail "40% deviation exceeds the 10% threshold → high severity."
  log "RESULT: PASS — severity = high"
else
  fail_check "severity = $SEVERITY (expected high)"
  fix "module2/scripts/demo-reset.sh"
  detail "The severity classifier should flag 40% deviation as high."
  detail "Check app/services/llm.py for classify_severity logic."
  log "RESULT: FAIL — severity = $SEVERITY"
fi

# Check: review_required = true/True
REVIEW_LOWER=$(echo "$REVIEW_REQ" | python3 -c "import sys; print(sys.stdin.read().strip().lower())")
if [[ "$REVIEW_LOWER" == "true" ]]; then
  pass "review_required = $REVIEW_REQ"
  detail "The agent does not auto-execute — it requires human review."
  log "RESULT: PASS — review_required = $REVIEW_REQ"
else
  fail_check "review_required = $REVIEW_REQ (expected true)"
  fix "module2/scripts/demo-reset.sh"
  detail "The approval gate should set review_required=true for high severity."
  detail "Check the approval_gate logic in the agent workflow."
  log "RESULT: FAIL — review_required = $REVIEW_REQ"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 2b)
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/4" "Verify tool calls in the agent state" "2b — Integrate tools (databases, APIs, pipelines)"
show_command "curl -s $API/agent/state/INC-3001 | python3 -m json.tool"

log_divider "STEP 3: Verify tool calls in agent state (LO 2b)"
log "COMMAND:"
log "  curl -s $API/agent/state/INC-3001 | python3 -m json.tool"
log ""

STATE=$(curl -sf "$API/agent/state/INC-3001")
echo "$STATE" | python3 -m json.tool > "$TMPD/step3.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step3.json" >> "$LOG"
log ""

TOOL_COUNT=$(echo "$STATE" | python3 -c "import json,sys; d=json.load(sys.stdin); tc=d.get('tool_calls',d.get('steps',[])); print(len(tc))")
TOOL_NAMES=$(echo "$STATE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
tc=d.get('tool_calls',d.get('steps',[]))
if isinstance(tc,list):
    names=[t.get('tool_name',t.get('node','?')) for t in tc]
else:
    names=list(tc.keys())
print(', '.join(names))
")

highlight "tool_call count:" "$TOOL_COUNT"
highlight "tool names:" "$TOOL_NAMES"
echo ""
printf "  ${GRAY}★ = read these values aloud on camera${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  tool_call_count: $TOOL_COUNT"
log "  tool_names:      $TOOL_NAMES"
log ""
log "LO COVERAGE:"
log "  2b — Every tool invocation is traceable; chronological order matches the state diagram"

# Check: tool_calls >= 4
if [[ "$TOOL_COUNT" -ge 4 ]]; then
  pass "tool_calls = $TOOL_COUNT (>= 4 tool invocations recorded)"
  detail "Tools: $TOOL_NAMES"
  log "RESULT: PASS — $TOOL_COUNT tool calls"
else
  fail_check "tool_calls = $TOOL_COUNT (expected >= 4)"
  fix "module2/scripts/demo-reset.sh"
  detail "The agent should invoke at least 4 tools: inspect_metadata,"
  detail "retrieve_runbook, classify_severity, recommend_action."
  detail "Reset the server and re-run the triage workflow."
  log "RESULT: FAIL — only $TOOL_COUNT tool calls"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 2a, 2b)
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/4" "Verify the approval gate decision" "2a, 2b — Approval gate stops autonomous execution"
show_command "curl -s $API/agent/decisions | python3 -m json.tool"

log_divider "STEP 4: Verify the approval gate decision (LO 2a, 2b)"
log "COMMAND:"
log "  curl -s $API/agent/decisions | python3 -m json.tool"
log ""

DECISIONS=$(curl -sf "$API/agent/decisions")
echo "$DECISIONS" | python3 -m json.tool > "$TMPD/step4.json" 2>&1

log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

DEC_INCIDENT=$(echo "$DECISIONS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
decs = d if isinstance(d,list) else d.get('decisions',[])
match = [x for x in decs if x.get('incident_id')=='INC-3001']
print(match[0]['incident_id'] if match else 'MISSING')
")
DEC_REVIEW=$(echo "$DECISIONS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
decs = d if isinstance(d,list) else d.get('decisions',[])
match = [x for x in decs if x.get('incident_id')=='INC-3001']
print(match[0]['review_required'] if match else 'MISSING')
")
DEC_SEVERITY=$(echo "$DECISIONS" | python3 -c "
import json,sys
d=json.load(sys.stdin)
decs = d if isinstance(d,list) else d.get('decisions',[])
match = [x for x in decs if x.get('incident_id')=='INC-3001']
print(match[0].get('severity','N/A') if match else 'MISSING')
")

highlight "review_required:" "$DEC_REVIEW"
field     "incident_id:" "$DEC_INCIDENT"
field     "severity:" "$DEC_SEVERITY"
echo ""
printf "  ${GRAY}★ = read this value aloud on camera (the approval gate)${NC}\n"
echo ""

log "EXTRACTED VALUES:"
log "  incident_id:     $DEC_INCIDENT"
log "  severity:        $DEC_SEVERITY"
log "  review_required: $DEC_REVIEW"
log ""
log "LO COVERAGE:"
log "  2a — Multi-step pipeline ends at approval gate, not auto-execution"
log "  2b — Decision record integrates tool outputs into a final traceable decision"

# Check: decision exists for INC-3001
if [[ "$DEC_INCIDENT" == "INC-3001" ]]; then
  pass "Decision record found for INC-3001"
  detail "The agent created a traceable decision for the incident."
  log "RESULT: PASS — decision found for INC-3001"
else
  fail_check "No decision record found for INC-3001"
  fix "module2/scripts/demo-reset.sh"
  detail "The triage workflow should create a decision record in the decisions store."
  detail "Reset the server and re-run the preflight check."
  log "RESULT: FAIL — no decision for INC-3001"
fi

# Check: review_required = true/True
DEC_REVIEW_LOWER=$(echo "$DEC_REVIEW" | python3 -c "import sys; print(sys.stdin.read().strip().lower())")
if [[ "$DEC_REVIEW_LOWER" == "true" ]]; then
  pass "review_required = $DEC_REVIEW (approval gate is active)"
  detail "The agent recommends but does not act on production systems."
  log "RESULT: PASS — review_required = $DEC_REVIEW"
else
  fail_check "review_required = $DEC_REVIEW (expected true)"
  fix "module2/scripts/demo-reset.sh"
  detail "The approval gate should flag high-severity incidents for human review."
  detail "Check the approval_gate logic in the agent workflow."
  log "RESULT: FAIL — review_required = $DEC_REVIEW"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"

log "| LO | Covered in | Proof |"
log "|----|------------|-------|"
log "| 2a | Step 1, Step 2, Step 4 | State diagram shows workflow graph; triage classified severity=$SEVERITY; approval gate review_required=$DEC_REVIEW |"
log "| 2b | Step 2, Step 3, Step 4 | Tools integrated in triage; $TOOL_COUNT tool calls recorded in order; decision record traces tool outputs |"
log ""
log "All 2 learning objectives (2a, 2b) are covered by the 4 demo steps."

echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}2a${NC}  Steps 1, 2, 4  ${DIM}State diagram + severity classification + approval gate${NC}\n"
printf "  ${BLUE}2b${NC}  Steps 2, 3, 4  ${DIM}Tool integration + traceable tool calls + decision record${NC}\n"

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
  printf "  ${BLUE}Quick fix:${NC} module2/scripts/demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module2/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
  log ""
  log "HOW TO FIX:"
  log "  1. Reset the environment:"
  log "     module2/scripts/demo-reset.sh"
  log ""
  log "  2. Rerun the preflight check:"
  log "     module2/scripts/preflight_check.sh"
  log ""
  log "  3. If reset does not fix it, check:"
  log "     - Is the server running? curl -s http://localhost:8000/health"
  log "     - Are seed files present? ls data/seed/"
  log "     - Are payloads present? ls data/payloads/"
  log "     - Run full setup: ./environment-setup/install-macos-requirements.sh"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module2/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
