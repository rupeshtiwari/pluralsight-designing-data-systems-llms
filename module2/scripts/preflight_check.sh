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
ERRORS=0

echo "========================================"
echo " Module 2 — Pre-recording Preflight"
echo "========================================"
echo ""

# ── 1. FastAPI server health ─────────────────────────────────────────────────
if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    ok "FastAPI server is healthy"
else
    fail "FastAPI server is not responding on http://localhost:8000/health"
    ERRORS=$((ERRORS + 1))
fi

# ── 2. PostgreSQL reachable ──────────────────────────────────────────────────
if docker exec northwind-postgres pg_isready -U northwind > /dev/null 2>&1; then
    ok "PostgreSQL is reachable"
else
    fail "PostgreSQL is not reachable (northwind-postgres container)"
    ERRORS=$((ERRORS + 1))
fi

# ── 3. agent_tool_calls table exists ─────────────────────────────────────────
if docker exec northwind-postgres psql -U northwind -c "SELECT 1 FROM agent_tool_calls LIMIT 0" > /dev/null 2>&1; then
    ok "Table agent_tool_calls exists"
else
    fail "Table agent_tool_calls does not exist"
    ERRORS=$((ERRORS + 1))
fi

# ── 4. agent_decisions table exists ──────────────────────────────────────────
if docker exec northwind-postgres psql -U northwind -c "SELECT 1 FROM agent_decisions LIMIT 0" > /dev/null 2>&1; then
    ok "Table agent_decisions exists"
else
    fail "Table agent_decisions does not exist"
    ERRORS=$((ERRORS + 1))
fi

# ── 5. No stale INC-3001 data (clean state) ─────────────────────────────────
STALE_TOOL_CALLS=$(docker exec northwind-postgres psql -U northwind -t -c "SELECT count(*) FROM agent_tool_calls WHERE incident_id='INC-3001'" 2>/dev/null | tr -d ' ')
STALE_DECISIONS=$(docker exec northwind-postgres psql -U northwind -t -c "SELECT count(*) FROM agent_decisions WHERE incident_id='INC-3001'" 2>/dev/null | tr -d ' ')
if [ "${STALE_TOOL_CALLS:-0}" = "0" ] && [ "${STALE_DECISIONS:-0}" = "0" ]; then
    ok "No stale INC-3001 data in PostgreSQL"
else
    warn "Stale INC-3001 data found (tool_calls=${STALE_TOOL_CALLS}, decisions=${STALE_DECISIONS})"
    warn "Consider cleaning: DELETE FROM agent_tool_calls WHERE incident_id='INC-3001'; DELETE FROM agent_decisions WHERE incident_id='INC-3001';"
fi

# ── 6. Payload file exists ───────────────────────────────────────────────────
if [ -f "$REPO_ROOT/data/payloads/anomaly_triage.json" ]; then
    ok "Payload data/payloads/anomaly_triage.json exists"
else
    fail "Payload data/payloads/anomaly_triage.json is missing"
    ERRORS=$((ERRORS + 1))
fi

# ── 7. fmt.py formatter available ────────────────────────────────────────────
if [ -f "$REPO_ROOT/scripts/fmt.py" ]; then
    ok "scripts/fmt.py formatter exists"
else
    fail "scripts/fmt.py formatter is missing"
    ERRORS=$((ERRORS + 1))
fi

# ── 8. tmux session check ───────────────────────────────────────────────────
if tmux has-session -t m2-demo 2>/dev/null; then
    ok "tmux session m2-demo is running"
else
    warn "tmux session m2-demo is not running (run module2/scripts/demo_up.sh)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
if [ "$ERRORS" -eq 0 ]; then
    printf "${GREEN}Preflight passed — ready to record Module 2 demo${NC}\n"
else
    printf "${RED}Preflight failed with $ERRORS error(s). Fix issues before recording.${NC}\n"
fi
echo "========================================"
exit "$ERRORS"
