#!/usr/bin/env bash
# module3/scripts/preflight_check.sh — Pre-recording checks for Module 3 demo
# Verifies all services and data are ready before recording starts.
#
# Usage:
#   module3/scripts/preflight_check.sh

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; ERRORS=$((ERRORS + 1)); }

ERRORS=0

echo ""
echo "========================================"
echo " Module 3 — Preflight Check"
echo "========================================"
echo ""

# ── 1. Docker Compose services running ───────────────────────────────────────
echo "── Docker Compose Services ──"

for SERVICE in northwind-postgres northwind-api northwind-airflow-webserver northwind-airflow-scheduler; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$SERVICE" 2>/dev/null || echo "not found")
    if [[ "$STATUS" == "running" ]]; then
        ok "$SERVICE is running"
    else
        fail "$SERVICE is not running (status: $STATUS)"
    fi
done

echo ""

# ── 2. Airflow UI accessible ────────────────────────────────────────────────
echo "── Airflow UI ──"

HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
    ok "Airflow webserver is accessible at http://localhost:8080 (HTTP $HTTP_CODE)"
else
    fail "Airflow webserver not accessible (HTTP $HTTP_CODE)"
fi

echo ""

# ── 3. FastAPI healthy ───────────────────────────────────────────────────────
echo "── FastAPI ──"

HEALTH=$(curl -sf http://localhost:8000/health 2>/dev/null || echo '{}')
STATUS=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unreachable")

if [[ "$STATUS" == "healthy" || "$STATUS" == "ok" ]]; then
    ok "FastAPI is healthy (status: $STATUS)"
else
    fail "FastAPI health check failed (status: $STATUS)"
fi

echo ""

# ── 4. DAGs visible in Airflow ───────────────────────────────────────────────
echo "── Airflow DAGs ──"

# Check DAGs via the Airflow REST API (basic auth admin:admin)
DAGS_RESP=$(curl -sf -u admin:admin http://localhost:8080/api/v1/dags 2>/dev/null || echo '{}')

for DAG_ID in northwind_llm_enrichment northwind_static_reconciliation; do
    if echo "$DAGS_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
dag_ids = [d['dag_id'] for d in data.get('dags', [])]
assert '$DAG_ID' in dag_ids
" 2>/dev/null; then
        ok "DAG '$DAG_ID' is visible in Airflow"
    else
        fail "DAG '$DAG_ID' not found in Airflow"
    fi
done

echo ""

# ── 5. Payload files present ────────────────────────────────────────────────
echo "── Demo Payloads ──"

PAYLOAD="data/payloads/batch_feedback.json"
if [[ -f "$PROJECT_DIR/$PAYLOAD" ]]; then
    ITEM_COUNT=$(python3 -c "import json; print(len(json.load(open('$PROJECT_DIR/$PAYLOAD'))))" 2>/dev/null || echo "0")
    ok "$PAYLOAD exists ($ITEM_COUNT items)"
else
    fail "$PAYLOAD not found"
fi

echo ""

# ── 6. DuckDB database accessible ───────────────────────────────────────────
echo "── DuckDB ──"

DUCKDB_PATH="$PROJECT_DIR/data/northwind.duckdb"
if [[ -f "$DUCKDB_PATH" ]]; then
    ok "DuckDB file exists at data/northwind.duckdb"
else
    warn "DuckDB file not found at data/northwind.duckdb (will be created on first use)"
fi

echo ""

# ── 7. tmux session ─────────────────────────────────────────────────────────
echo "── tmux ──"

if tmux has-session -t m3-demo 2>/dev/null; then
    ok "tmux session 'm3-demo' is active"
else
    warn "tmux session 'm3-demo' not found (run demo_up.sh first)"
fi

echo ""

# ── 8. Utilities ─────────────────────────────────────────────────────────────
echo "── Utilities ──"

if [[ -f "$PROJECT_DIR/scripts/fmt.py" ]]; then
    ok "scripts/fmt.py is available"
else
    fail "scripts/fmt.py not found"
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
    printf "${GREEN}All preflight checks passed — ready to record!${NC}\n"
else
    printf "${RED}${ERRORS} check(s) failed — fix before recording.${NC}\n"
fi
echo "========================================"

exit $ERRORS
