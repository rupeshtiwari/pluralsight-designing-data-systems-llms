#!/usr/bin/env bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[ERR]${NC}  %s\n" "$1"; }

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/module2/captures"
mkdir -p "$OUT_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ERRORS=0

echo "========================================"
echo " Module 2 — Capture Demo Output"
echo " $TIMESTAMP"
echo "========================================"
echo ""

# ── Step 1: Show the LangGraph state diagram ─────────────────────────────────
echo "Step 1: Agent workflow graph..."
STEP1_FILE="$OUT_DIR/step1_agent_graph_${TIMESTAMP}.json"
if curl -sf http://localhost:8000/agent/graph -o "$STEP1_FILE" 2>/dev/null; then
    ok "Step 1 captured -> $(basename "$STEP1_FILE")"
    python3 "$REPO_ROOT/scripts/fmt.py" --type raw < "$STEP1_FILE"
    echo ""
else
    fail "Step 1 failed — /agent/graph endpoint not reachable"
    ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Run the triage workflow ──────────────────────────────────────────
echo "Step 2: Triage workflow..."
STEP2_FILE="$OUT_DIR/step2_triage_${TIMESTAMP}.json"
if curl -sf http://localhost:8000/agent/triage \
    -H "Content-Type: application/json" \
    -d @"$REPO_ROOT/data/payloads/anomaly_triage.json" \
    -o "$STEP2_FILE" 2>/dev/null; then
    ok "Step 2 captured -> $(basename "$STEP2_FILE")"
    python3 "$REPO_ROOT/scripts/fmt.py" --type triage < "$STEP2_FILE"
    echo ""
else
    fail "Step 2 failed — /agent/triage endpoint not reachable"
    ERRORS=$((ERRORS + 1))
fi

# ── Step 3: Verify tool calls in PostgreSQL ──────────────────────────────────
echo "Step 3: Agent tool calls..."
STEP3_FILE="$OUT_DIR/step3_tool_calls_${TIMESTAMP}.txt"
if docker exec northwind-postgres psql -U northwind -c \
    "SELECT tool_name, output_status, created_at FROM agent_tool_calls WHERE incident_id='INC-3001' ORDER BY created_at" \
    > "$STEP3_FILE" 2>/dev/null; then
    ok "Step 3 captured -> $(basename "$STEP3_FILE")"
    cat "$STEP3_FILE"
    echo ""
else
    fail "Step 3 failed — could not query agent_tool_calls"
    ERRORS=$((ERRORS + 1))
fi

# ── Step 4: Verify approval gate decision in PostgreSQL ──────────────────────
echo "Step 4: Agent decisions..."
STEP4_FILE="$OUT_DIR/step4_decisions_${TIMESTAMP}.txt"
if docker exec northwind-postgres psql -U northwind -c \
    "SELECT incident_id, severity, recommended_action, review_required FROM agent_decisions WHERE incident_id='INC-3001'" \
    > "$STEP4_FILE" 2>/dev/null; then
    ok "Step 4 captured -> $(basename "$STEP4_FILE")"
    cat "$STEP4_FILE"
    echo ""
else
    fail "Step 4 failed — could not query agent_decisions"
    ERRORS=$((ERRORS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo "========================================"
if [ "$ERRORS" -eq 0 ]; then
    printf "${GREEN}All 4 steps captured successfully${NC}\n"
else
    printf "${RED}$ERRORS step(s) failed — review output above${NC}\n"
fi
echo "Captures saved to: $OUT_DIR"
echo "========================================"
exit "$ERRORS"
