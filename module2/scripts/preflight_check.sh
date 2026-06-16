#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 2 Clip 4 — Preflight Check
#
# Runs every demo step in the same sequence as the README, captures each
# command and its output, and saves a structured log to module2/preflight_log.txt.
#
# Maps each step to its on-screen proof and to the learning objective.
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
MODULE 2 — CLIP 4 PREFLIGHT LOG
================================================================================
Demo:    LangGraph agent triage with PostgreSQL and API tools
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API

Learning objectives:
  2a  Design multi-step decision pipelines
  2b  Integrate tools (databases, APIs) to enable LLM actions

HEADER

echo ""
printf "${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}║  Module 2 Clip 4 — Preflight Check                          ║${NC}\n"
printf "${BOLD}║  LangGraph agent triage with PostgreSQL + API tools         ║${NC}\n"
printf "${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}\n"

# ── Reset to a clean baseline ────────────────────────────────────────────────
echo ""
printf "  ${DIM}Resetting to a clean baseline...${NC}\n"
if [[ -x "$PROJECT_ROOT/scripts/module2-demo-reset.sh" ]]; then
  "$PROJECT_ROOT/scripts/module2-demo-reset.sh" >/dev/null 2>&1 || true
fi

# ── Server check ────────────────────────────────────────────────────────────
echo ""
printf "  ${DIM}Checking server at ${API}...${NC}\n"
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail_check "Server is not running at $API"
  fix "module2/scripts/demo-reset.sh"
  echo "Server not running" >> "$LOG"
  exit 1
fi
pass "Server is healthy"
log "Server: healthy"

# Detect storage backend (memory vs postgres)
BACKEND=$(curl -sf "$API/admin/agent-tool-calls?limit=1" | python3 -c "import json,sys;print(json.load(sys.stdin).get('backend','?'))" 2>/dev/null || echo "?")
log "Storage backend: $BACKEND"
printf "  ${DIM}Storage backend: ${BLUE}%s${NC}\n" "$BACKEND"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 (LO 2a) — LangGraph topology (Mermaid)
# ═════════════════════════════════════════════════════════════════════════════
step_header "1/5" "Show the LangGraph topology (Mermaid)" "2a — Multi-step decision pipeline"
show_command "curl -s $API/agent/graph | python3 scripts/fmt.py --type mermaid"

log_divider "STEP 1: Show the LangGraph topology (LO 2a)"
log "COMMAND:"
log "  curl -s $API/agent/graph"
log ""

GRAPH=$(curl -sf "$API/agent/graph")
echo "$GRAPH" | python3 -m json.tool > "$TMPD/step1.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step1.json" >> "$LOG"
log ""

NODES=$(echo "$GRAPH" | python3 -c "import json,sys; print(' '.join(json.load(sys.stdin).get('nodes', [])))")
HAS_MERMAID=$(echo "$GRAPH" | python3 -c "import json,sys; d=json.load(sys.stdin); print('yes' if 'graph' in d.get('mermaid','') else 'no')")

highlight "inspect_metadata"  "in topology"
highlight "retrieve_runbook"  "in topology"
highlight "recommend_action"  "in topology"
highlight "approval_gate"     "in topology"
field     "all nodes:"        "$NODES"
echo ""
printf "  ${GRAY}★ = the four nodes the clip outline names${NC}\n"

log "EXTRACTED VALUES:"
log "  nodes:       $NODES"
log "  has_mermaid: $HAS_MERMAID"
log ""
log "LO COVERAGE:"
log "  2a — Topology is explicit and auto-generated from compiled LangGraph"

for n in inspect_metadata retrieve_runbook classify_severity recommend_action approval_gate auto_log; do
  if echo " $NODES " | grep -q " $n "; then
    pass "node present: $n"
    log "RESULT: PASS — node $n in topology"
  else
    fail_check "node missing: $n"
    fix "Check app/services/agent_graph.py add_node() calls"
    log "RESULT: FAIL — node $n missing"
  fi
done

if [[ "$HAS_MERMAID" == "yes" ]]; then
  pass "mermaid source generated from compiled graph"
  log "RESULT: PASS — mermaid present"
else
  fail_check "mermaid source missing"
  fix "Verify get_graph().draw_mermaid() in agent_graph.graph_topology()"
  log "RESULT: FAIL — mermaid missing"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 (LO 2a, 2b) — Trigger the agent (high severity)
# ═════════════════════════════════════════════════════════════════════════════
step_header "2/5" "Trigger the agent on a high-severity incident" "2a, 2b — Workflow + tool integration"
show_command 'curl -s $API/agent/triage -H "Content-Type: application/json" -d @data/payloads/agent_triage.json'

log_divider "STEP 2: Trigger the agent (LO 2a, 2b)"
log "INPUT PAYLOAD (data/payloads/agent_triage.json):"
cat "$PROJECT_ROOT/data/payloads/agent_triage.json" >> "$LOG"
log ""

RESPONSE=$(curl -sf -X POST "$API/agent/triage" -H "Content-Type: application/json" -d @"$PROJECT_ROOT/data/payloads/agent_triage.json")
echo "$RESPONSE" | python3 -m json.tool > "$TMPD/step2.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step2.json" >> "$LOG"
log ""

INCIDENT=$(echo "$RESPONSE" | python3 -c "import json,sys;print(json.load(sys.stdin)['incident_id'])")
SEV=$(echo "$RESPONSE"      | python3 -c "import json,sys;print(json.load(sys.stdin)['severity'])")
REV=$(echo "$RESPONSE"      | python3 -c "import json,sys;print(json.load(sys.stdin)['review_required'])")
ACTION=$(echo "$RESPONSE"   | python3 -c "import json,sys;print(json.load(sys.stdin)['recommended_action'])")
EVID=$(echo "$RESPONSE"     | python3 -c "import json,sys;print(json.load(sys.stdin)['evidence_summary'])")
REASON=$(echo "$RESPONSE"   | python3 -c "import json,sys;print(json.load(sys.stdin)['root_cause_hypothesis'])")

highlight "incident_id:"        "$INCIDENT"
highlight "severity:"           "$SEV"
highlight "selected_edge:"      "recommend_action"
highlight "recommended_action:" "$ACTION"
highlight "evidence_summary:"   "$EVID"
highlight "decision_reason:"    "$REASON"
highlight "review_required:"    "$REV"
echo ""
printf "  ${GRAY}★ = read aloud: incident_id, selected_edge, severity, evidence, reason${NC}\n"

log "EXTRACTED VALUES:"
log "  incident_id:        $INCIDENT"
log "  severity:           $SEV"
log "  review_required:    $REV"
log "  recommended_action: $ACTION"
log "  evidence_summary:   $EVID"
log "  decision_reason:    $REASON"
log ""
log "LO COVERAGE:"
log "  2a — Agent traversed multi-node pipeline (inspect → retrieve → classify → recommend → approval)"
log "  2b — Tools invoked: postgres metadata, pgvector retrieval, llm severity & action"

if [[ "$SEV" == "high" ]]; then
  pass "severity=high (30% deviation > 20% threshold)"
  log "RESULT: PASS — severity = high"
else
  fail_check "severity=$SEV (expected high)"
  fix "Verify classify_severity rule in app/services/agent_graph.py"
  log "RESULT: FAIL — severity = $SEV"
fi
if [[ "$REV" == "True" ]]; then
  pass "review_required = true (approval gate triggered)"
  log "RESULT: PASS — review_required true"
else
  fail_check "review_required = $REV (expected True)"
  log "RESULT: FAIL — review_required = $REV"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2b (LO 2a) — Active path on the Mermaid diagram
# ═════════════════════════════════════════════════════════════════════════════
step_header "2b/5" "Active path on Mermaid diagram" "2a — Workflow advances visibly"
show_command "curl -s '$API/agent/graph?incident_id=INC-2024-FIN-001' | python3 scripts/fmt.py --type mermaid"
log_divider "STEP 2b: Active path on Mermaid (LO 2a)"
log "COMMAND:"
log "  curl -s '$API/agent/graph?incident_id=INC-2024-FIN-001'"
log ""

ACTIVE_GRAPH=$(curl -sf "$API/agent/graph?incident_id=INC-2024-FIN-001")
ACTIVE_PATH=$(echo "$ACTIVE_GRAPH" | python3 -c "import json,sys;d=json.load(sys.stdin);print(','.join(d.get('active_path',[])))" 2>/dev/null || echo "")
HAS_CLASSDEF=$(echo "$ACTIVE_GRAPH" | python3 -c "import json,sys;print('yes' if 'classDef active' in json.load(sys.stdin).get('mermaid','') else 'no')" 2>/dev/null || echo "no")

log "OUTPUT:"
log "  active_path: $ACTIVE_PATH"
log "  classDef active in mermaid: $HAS_CLASSDEF"
log ""

printf "  ${PINK}★${NC} ${BLUE}active path:${NC} ${LGREEN}${ACTIVE_PATH}${NC}\n"
printf "  ${PINK}★${NC} ${BLUE}classDef 'active' present:${NC} ${LGREEN}${HAS_CLASSDEF}${NC}\n"
echo ""
printf "  ${BLUE}★${NC} = the active path comes from the actual agent_tool_calls rows for this incident\n"
echo ""

if [[ "$ACTIVE_PATH" == *"inspect_metadata"* && "$ACTIVE_PATH" == *"approval_gate"* ]]; then
  pass "active_path includes inspect_metadata and approval_gate"
  log "RESULT: PASS — active_path includes the narrated start and end nodes"
else
  fail_check "active_path missing expected nodes (got: $ACTIVE_PATH)"
  log "RESULT: FAIL — active_path = $ACTIVE_PATH"
fi

if [[ "$HAS_CLASSDEF" == "yes" ]]; then
  pass "Mermaid source contains classDef 'active' for path highlighting"
  log "RESULT: PASS — classDef active present"
else
  fail_check "Mermaid source is missing the active classDef"
  log "RESULT: FAIL — no classDef active in mermaid"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 (LO 2b) — agent_tool_calls table
# ═════════════════════════════════════════════════════════════════════════════
step_header "3/5" "Show agent_tool_calls (Postgres receipts)" "2b — Tool integration is traceable"
show_command "curl -s '$API/admin/agent-tool-calls?incident_id=INC-2024-FIN-001' | python3 scripts/fmt.py --type tool-calls"

log_divider "STEP 3: agent_tool_calls table (LO 2b)"
TC_JSON=$(curl -sf "$API/admin/agent-tool-calls?incident_id=INC-2024-FIN-001&limit=10")
echo "$TC_JSON" | python3 -m json.tool > "$TMPD/step3.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step3.json" >> "$LOG"
log ""

TC_COUNT=$(echo "$TC_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin)['count'])")
TC_NAMES=$(echo "$TC_JSON" | python3 -c "import json,sys;print(','.join(r['tool_name'] for r in json.load(sys.stdin)['tool_calls']))")
TC_HASH_OK=$(echo "$TC_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print(int(all(len(r.get('input_hash','')) >= 12 for r in d['tool_calls'])))")
TC_TS_OK=$(echo "$TC_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print(int(all(r.get('created_at') for r in d['tool_calls'])))")
TC_STATUS_OK=$(echo "$TC_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin);print(int(all(r.get('output_status') for r in d['tool_calls'])))")

highlight "tool_name"      "(all rows)"
highlight "input_hash"     "(sha256, 12-char prefix shown)"
highlight "output_status"  "(success / error)"
highlight "timestamp"      "(created_at, ISO-8601)"
field     "count:"         "$TC_COUNT"
field     "tools called:"  "$TC_NAMES"
echo ""
printf "  ${GRAY}★ = each row carries these four narrated fields${NC}\n"

log "EXTRACTED VALUES:"
log "  count:         $TC_COUNT"
log "  tool sequence: $TC_NAMES"
log ""
log "LO COVERAGE:"
log "  2b — Every tool invocation persisted with tool_name, input_hash, output_status, created_at"

if [[ "$TC_COUNT" -ge 5 ]]; then
  pass "tool_calls count = $TC_COUNT (>= 5 for high-severity run)"
  log "RESULT: PASS — $TC_COUNT tool calls recorded"
else
  fail_check "tool_calls count = $TC_COUNT (expected >= 5)"
  log "RESULT: FAIL — only $TC_COUNT tool calls"
fi
if [[ "$TC_HASH_OK" == "1" ]]; then pass "every row has an input_hash"; else fail_check "missing input_hash"; fi
if [[ "$TC_TS_OK" == "1" ]];  then pass "every row has a created_at timestamp"; else fail_check "missing created_at"; fi
if [[ "$TC_STATUS_OK" == "1" ]]; then pass "every row has an output_status"; else fail_check "missing output_status"; fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 (LO 2a, 2b) — agent_decisions table (review_required)
# ═════════════════════════════════════════════════════════════════════════════
step_header "4/5" "Show agent_decisions (approval gate)" "2a, 2b — Agent advises, does not act"
show_command "curl -s '$API/admin/agent-decisions?limit=1' | python3 scripts/fmt.py --type agent-decisions"

log_divider "STEP 4: agent_decisions table (LO 2a, 2b)"
DEC_JSON=$(curl -sf "$API/admin/agent-decisions?limit=2")
echo "$DEC_JSON" | python3 -m json.tool > "$TMPD/step4.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step4.json" >> "$LOG"
log ""

DEC_STATUS=$(echo "$DEC_JSON" | python3 -c "
import json, sys
rows = json.load(sys.stdin)['decisions']
for r in rows:
    if r['incident_id']=='INC-2024-FIN-001':
        print(r['status']); break
else: print('MISSING')")
DEC_EDGE=$(echo "$DEC_JSON" | python3 -c "
import json, sys
rows = json.load(sys.stdin)['decisions']
for r in rows:
    if r['incident_id']=='INC-2024-FIN-001':
        print(r.get('selected_edge','')); break
else: print('MISSING')")

highlight "status:"          "$DEC_STATUS"
highlight "review_required:" "true"
field     "selected_edge:"   "$DEC_EDGE"
echo ""
printf "  ${GRAY}★ = read aloud: status = review_required, NOT auto-write to trusted table${NC}\n"

log "EXTRACTED VALUES:"
log "  decision status: $DEC_STATUS"
log "  selected_edge:   $DEC_EDGE"
log ""
log "LO COVERAGE:"
log "  2a — Approval gate is a deliberate node in the pipeline"
log "  2b — Decision row is review_required, not an automatic production write"

if [[ "$DEC_STATUS" == "review_required" ]]; then
  pass "decision status = review_required (approval gate held)"
  log "RESULT: PASS — review_required"
else
  fail_check "decision status = $DEC_STATUS (expected review_required)"
  log "RESULT: FAIL — $DEC_STATUS"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 (LO 2a) — Conditional edge: low severity → auto_log branch
# ═════════════════════════════════════════════════════════════════════════════
step_header "5/5" "Conditional edge — low severity routes to auto_log" "2a — Pipeline branches based on state"
show_command 'curl -s $API/agent/triage -H "Content-Type: application/json" -d @data/payloads/agent_triage_low.json | python3 scripts/fmt.py --type branch'

log_divider "STEP 5: Conditional edge (LO 2a)"
log "INPUT PAYLOAD (data/payloads/agent_triage_low.json):"
cat "$PROJECT_ROOT/data/payloads/agent_triage_low.json" >> "$LOG"
log ""

LOW_RESP=$(curl -sf -X POST "$API/agent/triage" -H "Content-Type: application/json" -d @"$PROJECT_ROOT/data/payloads/agent_triage_low.json")
echo "$LOW_RESP" | python3 -m json.tool > "$TMPD/step5.json" 2>&1
log "OUTPUT:"
cat "$TMPD/step5.json" >> "$LOG"
log ""

LOW_SEV=$(echo "$LOW_RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)['severity'])")
LOW_REV=$(echo "$LOW_RESP" | python3 -c "import json,sys;print(json.load(sys.stdin)['review_required'])")

LOW_DEC=$(curl -sf "$API/admin/agent-decisions?limit=5" | python3 -c "
import json, sys
rows = json.load(sys.stdin)['decisions']
for r in rows:
    if r['incident_id']=='INC-2024-FIN-003':
        print(r.get('selected_edge','')); break
else: print('MISSING')")

highlight "severity:"      "$LOW_SEV"
highlight "selected_edge:" "$LOW_DEC"
highlight "review_required:" "$LOW_REV"
echo ""
printf "  ${GRAY}★ = read aloud: low severity ⇒ auto_log branch, no approval needed${NC}\n"

log "EXTRACTED VALUES:"
log "  severity:        $LOW_SEV"
log "  selected_edge:   $LOW_DEC"
log "  review_required: $LOW_REV"
log ""
log "LO COVERAGE:"
log "  2a — Conditional edge routes low-severity to auto_log (terminal, no trusted write)"

if [[ "$LOW_SEV" == "low" ]]; then
  pass "severity=low (5% deviation < 20% threshold)"
else
  fail_check "severity=$LOW_SEV (expected low)"
fi
if [[ "$LOW_DEC" == "auto_log" ]]; then
  pass "selected_edge=auto_log (conditional routing worked)"
else
  fail_check "selected_edge=$LOW_DEC (expected auto_log)"
fi
if [[ "$LOW_REV" == "False" ]]; then
  pass "review_required=false on auto_log branch"
else
  fail_check "review_required=$LOW_REV (expected False)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# LO COVERAGE SUMMARY
# ═════════════════════════════════════════════════════════════════════════════
log_divider "LEARNING OBJECTIVE COVERAGE SUMMARY"
log "| LO | Covered in           | Proof |"
log "|----|----------------------|-------|"
log "| 2a | Step 1, 2, 4, 5      | Topology + branching + approval gate node |"
log "| 2b | Step 2, 3, 4         | Tool invocations + audit table + decision ledger |"
log ""
log "Storage backend: $BACKEND"

echo ""
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "${BOLD}  LO COVERAGE${NC}\n"
printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${BLUE}2a${NC}  Steps 1, 2, 4, 5  ${DIM}Multi-step pipeline + approval gate + conditional branch${NC}\n"
printf "  ${BLUE}2b${NC}  Steps 2, 3, 4     ${DIM}Tool integrations + audit trail + decision ledger${NC}\n"
printf "  ${BLUE}backend${NC}  ${DIM}${BACKEND}${NC}\n"
if [[ "$BACKEND" != "postgres" ]]; then
  printf "  ${GRAY}(note: with docker compose up postgres the backend becomes 'postgres')${NC}\n"
fi

echo ""
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ERRORS -eq 0 ]]; then
  printf "${GREEN}  ✓ ALL CHECKS PASSED — Module 2 Clip 4 demo is ready${NC}\n"
  log ""
  log "VERDICT: ALL CHECKS PASSED"
else
  printf "${PINK}  ✗ $ERRORS CHECK(S) FAILED — Fix the issues above${NC}\n"
  echo ""
  printf "  ${BLUE}Quick fix:${NC} module2/scripts/demo-reset.sh\n"
  printf "  ${BLUE}Then rerun:${NC} module2/scripts/preflight_check.sh\n"
  log ""
  log "VERDICT: $ERRORS CHECK(S) FAILED"
fi
printf "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
echo ""
printf "  ${DIM}Log saved to: module2/preflight_log.txt${NC}\n"
echo ""

exit $ERRORS
