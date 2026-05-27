#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Demo Reset
# Stops any running server, deletes generated data, and starts fresh so the
# demo always begins from a known baseline:
#   raw.feedback = 10    (seed data)
#   trusted.feedback_enriched = 0    (empty — nothing enriched yet)
#   llm_decisions = 0    (empty — no decisions yet)
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
printf "${BOLD}Module 1 — Demo Reset${NC}\n"
echo "========================================="
echo ""

# Stop any running server (clears in-memory llm_decisions)
info "Stopping any running server..."
kill $(lsof -ti :8000) 2>/dev/null || true
sleep 1
ok "Port 8000 clear"

# Delete DuckDB (removes all trusted + quarantine rows from prior runs)
info "Removing old DuckDB database..."
rm -f data/northwind.duckdb data/northwind.duckdb.wal
ok "DuckDB cleared"

# Start fresh server (creates tables + seeds raw data on startup)
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

# Seed knowledge base (reference docs for pgvector retrieval)
info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null
ok "Knowledge base seeded (8 reference documents)"

# Show baseline counts — these must be exact for a clean demo
echo ""
printf "${BOLD}Baseline state:${NC}\n"
METRICS=$(curl -sf http://localhost:8000/admin/metrics)
RAW_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['raw_feedback'])")
TRUSTED_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
echo "  raw.feedback:              $RAW_COUNT rows"
echo "  trusted.feedback_enriched: $TRUSTED_COUNT rows"

if [[ "$RAW_COUNT" -eq 10 && "$TRUSTED_COUNT" -eq 0 ]]; then
  echo ""
  echo "========================================="
  ok "Baseline verified. Run: ./scripts/module1-demo-run.sh"
else
  echo ""
  fail "Unexpected baseline (expected raw=10, trusted=0). Check seed data."
fi
echo ""
