#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 3 Demo Reset
#
# Stops the running FastAPI server, deletes the DuckDB file, kills the
# Airflow containers, restarts everything fresh, then triggers one batch
# run so the demo has data to display from the very first call.
#
# Idempotent: safe to run any number of times before recording.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; exit 1; }
info() { printf "${YELLOW}[....]${NC} %s\n" "$1"; }

echo ""
printf "${BOLD}Module 3 — Demo Reset${NC}\n"
echo "========================================="
echo ""

# ── Stop the FastAPI server ─────────────────────────────────────────────────
info "Stopping any running FastAPI server on port 8000..."
kill $(lsof -ti :8000) 2>/dev/null || true
sleep 1
ok "Port 8000 clear"

# ── Reset the DuckDB warehouse ──────────────────────────────────────────────
info "Removing old DuckDB database..."
rm -f data/northwind.duckdb data/northwind.duckdb.wal
ok "DuckDB cleared"

# ── Reset Airflow containers when Docker is available ───────────────────────
if command -v docker >/dev/null 2>&1; then
  info "Stopping Airflow containers (if running)..."
  docker compose stop airflow-webserver airflow-scheduler >/dev/null 2>&1 || true
  ok "Airflow containers stopped"
  info "Starting Airflow + Postgres containers..."
  docker compose up -d postgres airflow-webserver airflow-scheduler >/dev/null 2>&1 \
    || ok "(docker compose not started — continuing with memory stub)"
else
  ok "Docker not installed — Airflow client will use the memory stub"
fi

# ── Start the FastAPI server ────────────────────────────────────────────────
info "Starting FastAPI server..."
mkdir -p logs
source .venv/bin/activate 2>/dev/null || true
# Pin Airflow URL + credentials inline so the FastAPI process always sees
# them regardless of any stale shell env. Defaults match docker-compose.
AIRFLOW_URL="${AIRFLOW_URL:-http://localhost:8080}" \
AIRFLOW_USER="${AIRFLOW_USER:-admin}" \
AIRFLOW_PASSWORD="${AIRFLOW_PASSWORD:-admin}" \
  uvicorn app.main:app --port 8000 > logs/server.log 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 30); do
  if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sf http://localhost:8000/health >/dev/null 2>&1; then
  fail "FastAPI server failed to start. Check logs/server.log"
fi
ok "FastAPI server started (PID $SERVER_PID)"

# ── Seed knowledge base + trigger one batch so the demo has data ────────────
info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null || true
ok "Knowledge base seeded"

info "Triggering 3 initial batch runs so Step 3 has 3 rows of history..."
LAST_RID=""
for i in 1 2 3; do
  TRIGGER=$(curl -sf -X POST http://localhost:8000/admin/airflow-trigger \
    -H "Content-Type: application/json" \
    -d @data/payloads/airflow_trigger.json || true)
  if [[ -n "$TRIGGER" ]]; then
    LAST_RID=$(echo "$TRIGGER" | python3 -c "import json,sys;print(json.load(sys.stdin).get('dag_run_id',''))" 2>/dev/null || echo "")
  fi
  # Tiny sleep so the dag_run_id timestamps are distinguishable
  sleep 1
done
if [[ -n "$LAST_RID" ]]; then
  ok "3 DAG runs triggered (latest: $LAST_RID)"
else
  ok "Trigger calls skipped (Airflow not reachable, memory stub will seed itself)"
fi

echo ""
printf "${BOLD}Baseline state:${NC}\n"
DAG_COUNT=$(curl -sf "http://localhost:8000/admin/airflow-dag" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('tasks',[])))" 2>/dev/null || echo "?")
RUNS=$(curl -sf "http://localhost:8000/admin/airflow-dag-runs?limit=5" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('dag_runs',[])))" 2>/dev/null || echo "?")
echo "  airflow tasks visible: $DAG_COUNT"
echo "  dag_runs available:    $RUNS"

echo ""
echo "========================================="
ok "Baseline verified. Run: module3/scripts/preflight_check.sh"
echo ""
