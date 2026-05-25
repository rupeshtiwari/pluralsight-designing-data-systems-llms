#!/usr/bin/env bash
# module3/scripts/demo_down.sh — Tear down Module 3 demo environment
# Kills the tmux session and stops the Docker Compose stack.
#
# Usage:
#   module3/scripts/demo_down.sh

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
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }

SESSION="m3-demo"

echo ""
echo "========================================"
echo " Module 3 — Tearing Down Demo"
echo "========================================"
echo ""

# ── Kill tmux session ────────────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    ok "tmux session '$SESSION' killed"
else
    warn "tmux session '$SESSION' not found (already stopped)"
fi

# ── Stop Docker Compose stack ────────────────────────────────────────────────
if docker compose ps --status running 2>/dev/null | grep -q "northwind"; then
    echo ""
    warn "Stopping Docker Compose stack..."
    docker compose down --remove-orphans
    ok "Docker Compose stack stopped"
else
    warn "Docker Compose stack not running (already stopped)"
fi

# ── Clean up DuckDB WAL if present ──────────────────────────────────────────
if [[ -f "$PROJECT_DIR/data/northwind.duckdb.wal" ]]; then
    rm -f "$PROJECT_DIR/data/northwind.duckdb.wal"
    ok "Removed DuckDB WAL file"
fi

echo ""
echo "========================================"
ok "Module 3 demo environment torn down"
echo "========================================"
