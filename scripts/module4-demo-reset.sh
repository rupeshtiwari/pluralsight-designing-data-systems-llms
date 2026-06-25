#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 4 Demo Reset
#
# Stops the running FastAPI server, deletes the DuckDB file, removes orphan
# Airflow containers, brings the stack back up, then seeds one validation
# batch so the demo has data to display from the very first call.
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
printf "${BOLD}Module 4 — Demo Reset${NC}\n"
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

# ── Reset containers when Docker is available ───────────────────────────────
AIRFLOW_LIVE=0
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  info "Removing any orphan northwind containers (handles previous runs from other folders)..."
  docker rm -f northwind-postgres northwind-airflow-webserver northwind-airflow-scheduler 2>/dev/null || true
  docker compose down --remove-orphans 2>/dev/null || true
  ok "Old containers removed"

  info "Starting Airflow + Postgres containers..."
  if docker compose up -d postgres airflow-webserver airflow-scheduler; then
    info "Waiting up to 90s for Airflow webserver to answer http://localhost:8080..."
    WAITED=0
    while [[ $WAITED -lt 90 ]]; do
      if curl -sf -m 2 http://localhost:8080/api/v1/health >/dev/null 2>&1; then
        AIRFLOW_LIVE=1
        ok "Airflow webserver is responding (after ${WAITED}s)"
        break
      fi
      sleep 3
      WAITED=$((WAITED + 3))
    done
    if [[ $AIRFLOW_LIVE -eq 0 ]]; then
      printf "  ${YELLOW}[WARN]${NC} Airflow webserver did not respond in 90s.\n"
      printf "  ${YELLOW}[WARN]${NC} Demo will run with backend=memory. Diagnose with:\n"
      printf "  ${YELLOW}[WARN]${NC}   docker compose ps | grep airflow\n"
    fi
  else
    printf "  ${RED}[FAIL]${NC} docker compose up did not start Airflow.\n"
    printf "  ${RED}[FAIL]${NC} Demo will run with backend=memory. Fix Docker first.\n"
  fi
else
  if command -v docker >/dev/null 2>&1; then
    printf "  ${YELLOW}[WARN]${NC} Docker is installed but the daemon is not running.\n"
    printf "  ${YELLOW}[WARN]${NC} Open Docker Desktop, wait for 'Docker is running', then rerun.\n"
    printf "  ${YELLOW}[WARN]${NC} Demo will run with backend=memory until then.\n"
  else
    ok "Docker not installed — Airflow client will use the memory stub"
  fi
fi

# ── Start the FastAPI server ────────────────────────────────────────────────
info "Starting FastAPI server..."
mkdir -p logs
source .venv/bin/activate 2>/dev/null || true
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

# ── Seed one validation batch so the demo has baseline data ─────────────────
info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null || true
ok "Knowledge base seeded"

ok "Reset complete — DuckDB starts empty so the demo batch is the only one on screen"

echo ""
printf "${BOLD}Baseline state:${NC}\n"
echo "  pipeline_runs rows visible: 0 (clean slate — preflight or recording will create the one batch)"

echo ""
echo "========================================="
ok "Baseline verified. Run: module4/scripts/preflight_check.sh"
echo ""
