#!/usr/bin/env bash
# module3/scripts/demo_up.sh — Start Module 3 demo environment
# Launches Docker Compose stack (Postgres, FastAPI, Airflow) and sets up
# a tmux session with two panes: docker compose logs (top) and demo shell (bottom).
#
# Usage:
#   module3/scripts/demo_up.sh

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

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WAIT]${NC} %s\n" "$1"; }
fail() { printf "${RED}[ERR]${NC}  %s\n" "$1"; exit 1; }

SESSION="m3-demo"

# ── Pluralsight pane title colors ────────────────────────────────────────────
PS_PINK="\033[38;2;255;22;117m"
PS_LIME="\033[38;2;207;255;110m"
RESET="\033[0m"

# ── Kill stale session if it exists ──────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Killing existing tmux session '$SESSION'..."
    tmux kill-session -t "$SESSION"
fi

# ── Start Docker Compose stack ───────────────────────────────────────────────
echo ""
echo "========================================"
echo " Module 3 — Starting Docker Compose"
echo "========================================"
echo ""

docker compose up -d --build
ok "Docker Compose stack started"

# ── Wait for services to be healthy ──────────────────────────────────────────
echo ""
warn "Waiting for PostgreSQL to be healthy..."
RETRIES=0
MAX_RETRIES=30
until docker exec northwind-postgres pg_isready -U northwind &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        fail "PostgreSQL did not become healthy after ${MAX_RETRIES} attempts"
    fi
    sleep 2
done
ok "PostgreSQL is healthy"

warn "Waiting for FastAPI to be healthy..."
RETRIES=0
until curl -sf http://localhost:8000/health &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        fail "FastAPI did not become healthy after ${MAX_RETRIES} attempts"
    fi
    sleep 2
done
ok "FastAPI is healthy (http://localhost:8000)"

warn "Waiting for Airflow webserver to be ready..."
RETRIES=0
MAX_RETRIES=60
until curl -sf http://localhost:8080/health &>/dev/null; do
    RETRIES=$((RETRIES + 1))
    if [[ $RETRIES -ge $MAX_RETRIES ]]; then
        fail "Airflow webserver did not become ready after ${MAX_RETRIES} attempts"
    fi
    sleep 3
done
ok "Airflow webserver is ready (http://localhost:8080)"

# ── Seed data via API ────────────────────────────────────────────────────────
echo ""
warn "Seeding batch data via FastAPI..."
SEED_RESP=$(curl -sf -X POST http://localhost:8000/pipeline/batch-enrich \
    -H "Content-Type: application/json" \
    -d "{\"items\": $(cat data/payloads/batch_feedback.json)}" 2>&1) || true

if echo "$SEED_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('batch_id')" 2>/dev/null; then
    ok "Batch data seeded successfully"
else
    warn "Batch seed returned unexpected response (may need manual seed)"
fi

# ── Create tmux session ─────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Setting up tmux session: $SESSION"
echo "========================================"
echo ""

# Create session with top pane: filtered docker compose logs
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" "cd $PROJECT_DIR && docker compose logs -f --tail=50 api airflow-webserver airflow-scheduler 2>&1 | grep --line-buffered -E '(INFO|WARNING|ERROR|pipeline|enrichment|validation|batch|trigger|DAG)'" Enter

# Set top pane title
tmux select-pane -t "$SESSION:0.0" -T "Airflow + API Logs"
tmux set-option -t "$SESSION" pane-border-format " #{pane_title} "
tmux set-option -t "$SESSION" pane-border-status top

# Split horizontally: bottom pane for demo commands
tmux split-window -t "$SESSION" -v -p 60
tmux send-keys -t "$SESSION" "cd $PROJECT_DIR" Enter
tmux send-keys -t "$SESSION" "printf '${PS_LIME}Module 3 Demo — Airflow Enrichment Pipeline${RESET}\n'" Enter
tmux send-keys -t "$SESSION" "printf '${PS_PINK}Airflow: http://localhost:8080  (admin/admin)${RESET}\n'" Enter
tmux send-keys -t "$SESSION" "printf '${PS_LIME}FastAPI: http://localhost:8000/docs${RESET}\n\n'" Enter

# Set bottom pane title
tmux select-pane -t "$SESSION:0.1" -T "Demo Commands"

# Focus the demo commands pane
tmux select-pane -t "$SESSION:0.1"

echo ""
ok "tmux session '$SESSION' is ready"
echo ""
echo "  Attach with:  tmux attach -t $SESSION"
echo ""
echo "  Top pane:     Docker Compose logs (filtered)"
echo "  Bottom pane:  Demo commands"
echo ""
echo "  Airflow UI:   http://localhost:8080  (admin/admin)"
echo "  FastAPI docs: http://localhost:8000/docs"
echo "========================================"
