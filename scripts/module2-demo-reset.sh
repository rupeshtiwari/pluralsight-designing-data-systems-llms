#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 2 Demo Reset
# Stops any running server, deletes generated data, and starts fresh so the
# Module 2 LangGraph agent demo always begins from a known baseline:
#   agent_tool_calls   = 0   (empty — no agent runs yet)
#   agent_decisions    = 0   (empty — no decisions yet)
#   incidents seeded   = 3   (NorthWind finance DQ incidents)
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
printf "${BOLD}Module 2 — Demo Reset${NC}\n"
echo "========================================="
echo ""

info "Stopping any running server..."
kill $(lsof -ti :8000) 2>/dev/null || true
sleep 1
ok "Port 8000 clear"

info "Removing old DuckDB database..."
rm -f data/northwind.duckdb data/northwind.duckdb.wal
ok "DuckDB cleared"

# Best-effort: drop Postgres agent rows so the demo starts empty.
# Silently skipped when PG isn't reachable (e.g. inside a sandbox without
# docker compose up postgres).
info "Truncating agent_tool_calls and agent_decisions (if Postgres is up)..."
if command -v psql >/dev/null 2>&1; then
  PGPASSWORD=northwind psql -h localhost -U northwind -d northwind -c \
    "TRUNCATE TABLE agent_tool_calls, agent_decisions;" >/dev/null 2>&1 \
    && ok "Postgres agent tables truncated" \
    || ok "Postgres not reachable — memory backend will start empty on restart"
else
  ok "psql not installed — relying on memory backend"
fi

info "Starting FastAPI server..."
mkdir -p logs
source .venv/bin/activate 2>/dev/null || true
uvicorn app.main:app --port 8000 > logs/server.log 2>&1 &
SERVER_PID=$!

for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -sf http://localhost:8000/health >/dev/null 2>&1; then
  fail "Server failed to start. Check logs/server.log"
fi
ok "Server started (PID $SERVER_PID)"

info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null
ok "Knowledge base seeded (8 reference documents)"

echo ""
printf "${BOLD}Baseline state:${NC}\n"
TC=$(curl -sf "http://localhost:8000/admin/agent-tool-calls?limit=1" | python3 -c "import json,sys;print(json.load(sys.stdin)['count'])" 2>/dev/null || echo "?")
DC=$(curl -sf "http://localhost:8000/admin/agent-decisions?limit=1" | python3 -c "import json,sys;print(json.load(sys.stdin)['count'])" 2>/dev/null || echo "?")
echo "  agent_tool_calls:  $TC rows"
echo "  agent_decisions:   $DC rows"

echo ""
echo "========================================="
ok "Baseline verified. Run: module2/scripts/preflight_check.sh"
echo ""
