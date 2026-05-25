#!/usr/bin/env bash
set -euo pipefail
#
# Module 2 — Pre-Recording Validation Log
#
# Runs every demo step from the Module 2 recording runbook, captures the
# exact input payload and raw JSON output, and writes a structured plain-text
# log for GPT / reviewer validation before recording.
#
# Usage:
#   scripts/validate_module2.sh
#
# Output:
#   logs/module2_validation.txt

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
API="http://localhost:8000"
LOG="$REPO_ROOT/logs/module2_validation.txt"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

mkdir -p "$REPO_ROOT/logs"

divider() {
    printf '%0.s=' {1..72} >> "$LOG"
    echo "" >> "$LOG"
}

section() {
    echo "" >> "$LOG"
    divider
    echo "$1" >> "$LOG"
    divider
}

# ── Header ──────────────────────────────────────────────────────────────────
cat > "$LOG" <<HEADER
MODULE 2 VALIDATION LOG
=======================
Module:  Architecting agentic data workflows with LangGraph
Clip:    Clip 4 — Demo: LangGraph agent triage with PostgreSQL and API tools
Date:    $(date -u '+%Y-%m-%dT%H:%M:%SZ')
Server:  $API
LOs:     2a, 2b

This file contains the exact input and output for every demo step.
Compare each output against the "Expected output" section to validate
that the demo will produce the correct on-screen proof before recording.

HEADER

# ── Preflight ───────────────────────────────────────────────────────────────
section "PREFLIGHT"

echo "Server health:" >> "$LOG"
curl -sf "$API/health" 2>&1 | python3 -m json.tool >> "$LOG" 2>&1 || echo "FAIL: server not running" >> "$LOG"

echo "" >> "$LOG"
echo "Resetting metrics..." >> "$LOG"
curl -sf -X POST "$API/admin/reset-metrics" > /dev/null 2>&1 && echo "OK" >> "$LOG" || echo "WARN: reset-metrics failed" >> "$LOG"

echo "Seeding knowledge base..." >> "$LOG"
curl -sf -X POST "$API/admin/seed-knowledge-base" > /dev/null 2>&1 && echo "OK" >> "$LOG" || echo "WARN: seed failed" >> "$LOG"

# ── Step 1 ──────────────────────────────────────────────────────────────────
section "STEP 1: Show the LangGraph state diagram (LO 2a)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s http://localhost:8000/agent/graph' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s "$API/agent/graph" > "$TMPD/step1.json" 2>&1
python3 -m json.tool < "$TMPD/step1.json" >> "$LOG" 2>&1 || cat "$TMPD/step1.json" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Mermaid-compatible state diagram text showing nodes:" >> "$LOG"
echo "    inspect_metadata, retrieve_runbook, classify_severity," >> "$LOG"
echo "    recommend_action, approval_gate" >> "$LOG"
echo "  Edges show conditional transitions between nodes." >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Response contains node names: inspect_metadata, retrieve_runbook, classify_severity, recommend_action, approval_gate" >> "$LOG"
echo "  [ ] Response shows edges/transitions between nodes" >> "$LOG"
echo "  [ ] Endpoint returns 200 (not 404 or error)" >> "$LOG"

# ── Step 2 ──────────────────────────────────────────────────────────────────
section "STEP 2: Run the triage workflow for a data quality incident (LO 2a, 2b)"

echo "COMMAND:" >> "$LOG"
echo '  curl -s http://localhost:8000/agent/triage \' >> "$LOG"
echo '    -H "Content-Type: application/json" \' >> "$LOG"
echo '    -d @data/payloads/anomaly_triage.json' >> "$LOG"

echo "" >> "$LOG"
echo "INPUT PAYLOAD (data/payloads/anomaly_triage.json):" >> "$LOG"
cat "$REPO_ROOT/data/payloads/anomaly_triage.json" >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (raw JSON):" >> "$LOG"
curl -s "$API/agent/triage" \
    -H "Content-Type: application/json" \
    -d @"$REPO_ROOT/data/payloads/anomaly_triage.json" \
    > "$TMPD/step2.json" 2>&1
python3 -m json.tool < "$TMPD/step2.json" >> "$LOG" 2>&1

# Extract key fields
INC_ID=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('incident_id','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
SEVERITY=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('severity','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
ROOT_CAUSE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('root_cause_hypothesis','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
REC_ACTION=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('recommended_action','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
EVIDENCE=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('evidence_summary','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")
REVIEW_REQ=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('review_required','MISSING'))" < "$TMPD/step2.json" 2>/dev/null || echo "PARSE_ERROR")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  incident_id:           $INC_ID" >> "$LOG"
echo "  severity:              $SEVERITY" >> "$LOG"
echo "  root_cause_hypothesis: $ROOT_CAUSE" >> "$LOG"
echo "  recommended_action:    $REC_ACTION" >> "$LOG"
echo "  evidence_summary:      $EVIDENCE" >> "$LOG"
echo "  review_required:       $REVIEW_REQ" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  incident_id:           INC-3001" >> "$LOG"
echo "  severity:              high (40% deviation exceeds 10% threshold per DOC-005)" >> "$LOG"
echo "  root_cause_hypothesis: mentions fewer records despite healthy API / source extraction" >> "$LOG"
echo "  recommended_action:    pause downstream pipeline and investigate source" >> "$LOG"
echo "  evidence_summary:      references data quality runbook DOC-005" >> "$LOG"
echo "  review_required:       True (approval gate)" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] incident_id = INC-3001" >> "$LOG"
echo "  [ ] severity = high" >> "$LOG"
echo "  [ ] root_cause_hypothesis mentions source system / fewer records" >> "$LOG"
echo "  [ ] recommended_action mentions pipeline pause / investigation" >> "$LOG"
echo "  [ ] evidence_summary references DOC-005 or data quality runbook" >> "$LOG"
echo "  [ ] review_required = True" >> "$LOG"

# ── Step 3 ──────────────────────────────────────────────────────────────────
section "STEP 3: Verify tool calls recorded in PostgreSQL (LO 2b)"

echo "COMMAND:" >> "$LOG"
echo '  docker exec northwind-postgres psql -U northwind -c \' >> "$LOG"
echo "    \"SELECT tool_name, output_status, created_at FROM agent_tool_calls WHERE incident_id='INC-3001' ORDER BY created_at\"" >> "$LOG"

echo "" >> "$LOG"
echo "ALTERNATIVE (via API — using agent state endpoint):" >> "$LOG"
echo '  curl -s http://localhost:8000/agent/state/INC-3001' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (agent state with tool calls):" >> "$LOG"
curl -s "$API/agent/state/INC-3001" > "$TMPD/step3.json" 2>&1
python3 -m json.tool < "$TMPD/step3.json" >> "$LOG" 2>&1

# Count tool calls
TOOL_COUNT=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d.get('tool_calls',[])))" < "$TMPD/step3.json" 2>/dev/null || echo "0")
TOOL_NAMES=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
names = [tc.get('step','?') for tc in d.get('tool_calls',[])]
print(', '.join(names))
" < "$TMPD/step3.json" 2>/dev/null || echo "PARSE_ERROR")

echo "" >> "$LOG"
echo "EXTRACTED VALUES:" >> "$LOG"
echo "  tool_call_count: $TOOL_COUNT" >> "$LOG"
echo "  tool_names:      $TOOL_NAMES" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  4-5 tool calls in chronological order:" >> "$LOG"
echo "    1. inspect_metadata   - success" >> "$LOG"
echo "    2. retrieve_runbook   - success" >> "$LOG"
echo "    3. classify_severity  - success" >> "$LOG"
echo "    4. recommend_action   - success" >> "$LOG"
echo "    5. approval_gate      - success (optional, may be included)" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] At least 4 tool calls recorded" >> "$LOG"
echo "  [ ] Tool names appear in correct order: inspect_metadata, retrieve_runbook, classify_severity, recommend_action" >> "$LOG"
echo "  [ ] All tool calls show success status" >> "$LOG"
echo "  [ ] Each tool call has a timestamp" >> "$LOG"

# ── Step 4 ──────────────────────────────────────────────────────────────────
section "STEP 4: Verify the approval gate decision in PostgreSQL (LO 2a, 2b)"

echo "COMMAND:" >> "$LOG"
echo '  docker exec northwind-postgres psql -U northwind -c \' >> "$LOG"
echo "    \"SELECT incident_id, severity, recommended_action, review_required FROM agent_decisions WHERE incident_id='INC-3001'\"" >> "$LOG"

echo "" >> "$LOG"
echo "ALTERNATIVE (via API):" >> "$LOG"
echo '  curl -s http://localhost:8000/agent/decisions' >> "$LOG"

echo "" >> "$LOG"
echo "ACTUAL OUTPUT (agent decisions):" >> "$LOG"
curl -s "$API/agent/decisions" > "$TMPD/step4.json" 2>&1
python3 -m json.tool < "$TMPD/step4.json" >> "$LOG" 2>&1

# Find the INC-3001 decision
DECISION_FOUND=$(python3 -c "
import json,sys
data=json.load(sys.stdin)
if isinstance(data, list):
    matches = [d for d in data if d.get('incident_id')=='INC-3001']
    if matches:
        print('YES')
        d = matches[0]
        print(f\"severity={d.get('severity','?')}\")
        print(f\"review_required={d.get('review_required','?')}\")
        print(f\"recommended_action={d.get('recommended_action','?')}\")
    else:
        print('NO')
else:
    print('UNEXPECTED_FORMAT')
" < "$TMPD/step4.json" 2>/dev/null || echo "PARSE_ERROR")

echo "" >> "$LOG"
echo "DECISION FOUND FOR INC-3001:" >> "$LOG"
echo "$DECISION_FOUND" >> "$LOG"

echo "" >> "$LOG"
echo "EXPECTED OUTPUT:" >> "$LOG"
echo "  Single row showing:" >> "$LOG"
echo "    incident_id = INC-3001" >> "$LOG"
echo "    severity = high" >> "$LOG"
echo "    recommended_action describes pipeline pause" >> "$LOG"
echo "    review_required = True" >> "$LOG"

echo "" >> "$LOG"
echo "VALIDATION CHECKLIST:" >> "$LOG"
echo "  [ ] Decision record exists for INC-3001" >> "$LOG"
echo "  [ ] severity = high" >> "$LOG"
echo "  [ ] review_required = True (approval gate stopped auto-execution)" >> "$LOG"
echo "  [ ] recommended_action mentions pipeline pause / investigation" >> "$LOG"

# ── Summary ─────────────────────────────────────────────────────────────────
section "SUMMARY"

echo "Module 2, Clip 4 validation complete." >> "$LOG"
echo "" >> "$LOG"
echo "Proof points to verify:" >> "$LOG"
echo "  1. State diagram shows all 5 workflow nodes with transitions" >> "$LOG"
echo "  2. Triage returns incident_id=INC-3001, severity=high, review_required=True" >> "$LOG"
echo "  3. PostgreSQL has 4+ tool calls in correct order for INC-3001" >> "$LOG"
echo "  4. PostgreSQL has a decision with review_required=True (approval gate)" >> "$LOG"
echo "" >> "$LOG"
echo "If any checklist item fails, fix the issue before recording." >> "$LOG"

echo ""
echo "Validation log written to: $LOG"
echo "Review the file or hand it to GPT for automated verification."
