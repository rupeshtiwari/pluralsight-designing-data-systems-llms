#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 1 Demo Reset
# Starts the server (if not running), seeds data, and resets state so the
# demo starts from a known baseline. Run this BEFORE module1-demo-run.sh.
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

# Start server if not running
if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
  ok "Server already running"
else
  info "Starting FastAPI server..."
  source .venv/bin/activate 2>/dev/null || true
  rm -f data/northwind.duckdb data/northwind.duckdb.wal
  uvicorn app.main:app --port 8000 > logs/server.log 2>&1 &
  SERVER_PID=$!
  echo "  Server PID: $SERVER_PID"

  for i in $(seq 1 30); do
    if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    fail "Server failed to start. Check logs/server.log"
  fi
  ok "Server started"
fi

# Seed knowledge base (reference docs for pgvector)
info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null
ok "Knowledge base seeded (8 reference documents)"

# Reset metrics
info "Resetting metrics..."
curl -sf -X POST http://localhost:8000/admin/reset-metrics >/dev/null
ok "Metrics reset"

# Show baseline counts
echo ""
printf "${BOLD}Baseline state:${NC}\n"
METRICS=$(curl -sf http://localhost:8000/admin/metrics)
RAW_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['raw_feedback'])")
TRUSTED_COUNT=$(echo "$METRICS" | python3 -c "import json,sys; print(json.load(sys.stdin)['duckdb']['trusted_enriched'])")
echo "  raw.feedback:            $RAW_COUNT rows"
echo "  trusted.feedback_enriched: $TRUSTED_COUNT rows"

echo ""
echo "========================================="
ok "Ready for demo. Run: ./scripts/module1-demo-run.sh"
echo ""
