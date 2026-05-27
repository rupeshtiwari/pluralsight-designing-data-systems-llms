#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Start the demo environment: docker compose up + wait for /health
# Does NOT require tmux. Students use this; authors use moduleN/scripts/demo_up.sh.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; exit 1; }
info() { printf "${YELLOW}[....]${NC} %s\n" "$1"; }

echo ""
echo "Starting demo environment..."

# Check Docker is running
if ! docker info >/dev/null 2>&1; then
  fail "Docker is not running. Start Docker Desktop and try again."
fi

# Start containers
info "Running docker compose up -d..."
docker compose up -d

# Wait for FastAPI health
info "Waiting for FastAPI at http://localhost:8000/health..."
MAX_WAIT=60
ELAPSED=0
while ! curl -sf http://localhost:8000/health >/dev/null 2>&1; do
  sleep 2
  ELAPSED=$((ELAPSED + 2))
  if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo ""
    fail "FastAPI did not become healthy within ${MAX_WAIT}s. Check: docker compose logs api"
  fi
done
ok "FastAPI is healthy"

# Seed knowledge base
info "Seeding knowledge base..."
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base >/dev/null 2>&1 || true
ok "Knowledge base seeded"

# Reset metrics for clean state
curl -sf -X POST http://localhost:8000/admin/reset-metrics >/dev/null 2>&1 || true
ok "Metrics reset"

# Show container status
echo ""
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || docker compose ps

echo ""
ok "Demo environment is ready"
echo ""
echo "  FastAPI docs:  http://localhost:8000/docs"
echo "  Health check:  curl -s http://localhost:8000/health | python3 -m json.tool"
echo ""
echo "  Validate:      ./scripts/run-story.sh"
echo "  Stop:          docker compose down"
echo ""
