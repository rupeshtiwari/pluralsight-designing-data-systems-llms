#!/usr/bin/env bash
# setup-macos.sh — Idempotent macOS setup for NorthWind Markets demo project
# Safe to run multiple times.

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[ERR]${NC}  %s\n" "$1"; }

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "========================================"
echo " NorthWind Markets — macOS Setup"
echo "========================================"
echo ""

# ── 1. Homebrew ───────────────────────────────────────────────────────────────
if command -v brew &>/dev/null; then
    ok "Homebrew already installed ($(brew --version | head -1))"
else
    warn "Homebrew not found — installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to PATH for Apple Silicon Macs
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    ok "Homebrew installed"
fi

# ── 2. tmux (required for demo recording) ────────────────────────────────────
if command -v tmux &>/dev/null; then
    ok "tmux already installed ($(tmux -V))"
else
    warn "tmux not found — installing via Homebrew..."
    brew install tmux
    ok "tmux installed ($(tmux -V))"
fi

# ── 3. Python 3.12 ───────────────────────────────────────────────────────────
PYTHON_CMD=""
# Check if python3.12 is already available
if command -v python3.12 &>/dev/null; then
    PYTHON_CMD="python3.12"
    ok "Python 3.12 already installed ($(python3.12 --version))"
elif command -v python3 &>/dev/null && python3 --version 2>&1 | grep -q "3\.12"; then
    PYTHON_CMD="python3"
    ok "Python 3.12 already installed ($(python3 --version))"
else
    warn "Python 3.12 not found — installing via Homebrew..."
    brew install python@3.12
    if command -v python3.12 &>/dev/null; then
        PYTHON_CMD="python3.12"
    else
        # Homebrew may link it as python3
        PYTHON_CMD="$(brew --prefix python@3.12)/bin/python3.12"
    fi
    ok "Python 3.12 installed ($($PYTHON_CMD --version))"
fi

# ── 4. Virtual environment ───────────────────────────────────────────────────
VENV_DIR="$PROJECT_DIR/.venv"
if [[ -d "$VENV_DIR" && -f "$VENV_DIR/bin/activate" ]]; then
    ok "Virtual environment already exists at .venv/"
else
    warn "Creating virtual environment at .venv/ ..."
    $PYTHON_CMD -m venv "$VENV_DIR"
    ok "Virtual environment created"
fi

# Activate
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
ok "Virtual environment activated ($(python --version))"

# ── 5. Pip dependencies ──────────────────────────────────────────────────────
if [[ -f "$PROJECT_DIR/requirements.txt" ]]; then
    warn "Installing pip dependencies from requirements.txt ..."
    pip install --upgrade pip --quiet
    pip install -r "$PROJECT_DIR/requirements.txt" --quiet
    ok "All pip dependencies installed"
else
    fail "requirements.txt not found — skipping dependency install"
fi

# ── 6. DuckDB CLI ───────────────────────────────────────────────────────────
if command -v duckdb &>/dev/null; then
    ok "DuckDB CLI already installed ($(duckdb --version 2>&1 | head -1))"
else
    warn "DuckDB CLI not found — installing via Homebrew..."
    brew install duckdb
    ok "DuckDB CLI installed ($(duckdb --version 2>&1 | head -1))"
fi

# ── 7. Docker Desktop check ──────────────────────────────────────────────────
if command -v docker &>/dev/null; then
    if docker info &>/dev/null 2>&1; then
        ok "Docker Desktop is installed and running"
    else
        warn "Docker is installed but the daemon is not running."
        warn "Please start Docker Desktop before running docker-compose."
    fi
else
    fail "Docker not found. Please install Docker Desktop for macOS:"
    fail "  https://www.docker.com/products/docker-desktop/"
    fail "Docker is required for PostgreSQL (pgvector) and Airflow services."
fi

# ── 8. Required directories ──────────────────────────────────────────────────
for dir in logs .run data data/seed airflow/dags airflow/plugins; do
    if [[ -d "$PROJECT_DIR/$dir" ]]; then
        ok "Directory $dir/ already exists"
    else
        mkdir -p "$PROJECT_DIR/$dir"
        ok "Created directory $dir/"
    fi
done

# ── 9. Verification ──────────────────────────────────────────────────────────
echo ""
echo "── Verification ─────────────────────────────────────────"

ERRORS=0

# tmux version
if tmux -V &>/dev/null; then
    ok "tmux: $(tmux -V)"
else
    fail "tmux verification failed"
    ERRORS=$((ERRORS + 1))
fi

# DuckDB CLI
if command -v duckdb &>/dev/null; then
    ok "duckdb CLI: $(duckdb --version 2>&1 | head -1)"
else
    fail "duckdb CLI not found"
    ERRORS=$((ERRORS + 1))
fi

# Python imports
IMPORTS_TO_CHECK="fastapi uvicorn duckdb pydantic httpx structlog"
for pkg in $IMPORTS_TO_CHECK; do
    if python -c "import $pkg" &>/dev/null 2>&1; then
        ok "Python import: $pkg"
    else
        fail "Python import failed: $pkg"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
    printf "${GREEN}Setup complete — all checks passed!${NC}\n"
else
    printf "${RED}Setup complete with $ERRORS error(s). Review warnings above.${NC}\n"
fi
echo ""
echo "Next steps:"
echo "  source .venv/bin/activate"
echo "  docker compose up -d"
echo "  open http://localhost:8000/docs    # FastAPI"
echo "  open http://localhost:8080         # Airflow (admin/admin)"
echo "========================================"
