#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Student-facing setup for "Designing Data Systems with LLMs"
# Supports macOS and Linux. For Windows use setup.ps1.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; exit 1; }
info() { printf "${YELLOW}[....]${NC} %s\n" "$1"; }
hdr()  { printf "\n${BOLD}── %s${NC}\n" "$1"; }

echo ""
echo "========================================="
echo " Designing Data Systems with LLMs"
echo " Project Setup"
echo "========================================="
echo ""
echo "Project root: $PROJECT_ROOT"

OS_NAME="$(uname -s)"
echo "Detected OS:  $OS_NAME"

# ── 1. Python ────────────────────────────────────────────────────────────────
hdr "Python 3.12+"

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 not found. Install Python 3.12+ from https://www.python.org/downloads/"
fi

PY_VER="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')"
PY_OK="$(python3 -c 'import sys; print(int(sys.version_info >= (3, 12)))')"

if [[ "$PY_OK" != "1" ]]; then
  fail "Python 3.12+ required (detected $PY_VER). Install from https://www.python.org/downloads/"
fi
ok "Python $PY_VER"

# ── 2. Docker (hard requirement) ─────────────────────────────────────────────
hdr "Docker"

if ! command -v docker >/dev/null 2>&1; then
  fail "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
fi

if ! docker info >/dev/null 2>&1; then
  fail "Docker is installed but the daemon is not running. Start Docker Desktop and rerun this script."
fi
ok "Docker daemon is running"

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose not available. Update Docker Desktop or install Compose: https://docs.docker.com/compose/install/"
fi
ok "Docker Compose $(docker compose version --short 2>/dev/null || echo 'available')"

# ── 3. DuckDB CLI ────────────────────────────────────────────────────────────
hdr "DuckDB CLI"

if ! command -v duckdb >/dev/null 2>&1; then
  if [[ "$OS_NAME" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    info "Installing DuckDB CLI via Homebrew..."
    brew install duckdb
  else
    echo ""
    echo "  DuckDB CLI is not installed. Install it before running demos."
    echo ""
    echo "  macOS (Homebrew):  brew install duckdb"
    echo "  Linux:             https://duckdb.org/docs/installation/"
    echo ""
    fail "DuckDB CLI required. Install it and rerun this script."
  fi
fi
ok "DuckDB CLI $(duckdb --version 2>&1 | head -1)"

# ── 4. tmux (optional) ──────────────────────────────────────────────────────
hdr "tmux (optional — needed for author recording only)"

if command -v tmux >/dev/null 2>&1; then
  ok "tmux $(tmux -V 2>/dev/null || echo 'installed')"
else
  info "tmux not found. Not required for students. Authors: brew install tmux"
fi

# ── 5. Virtual environment ───────────────────────────────────────────────────
hdr "Python virtual environment"

if [[ -d .venv && -f .venv/bin/activate ]]; then
  ok ".venv already exists"
else
  info "Creating .venv..."
  python3 -m venv .venv
  ok ".venv created"
fi

source .venv/bin/activate

info "Upgrading pip..."
python -m pip install --upgrade pip setuptools wheel --quiet
ok "pip upgraded"

# ── 6. Python dependencies ───────────────────────────────────────────────────
hdr "Python dependencies"

if [[ ! -f requirements.txt ]]; then
  fail "requirements.txt not found"
fi

info "Installing from requirements.txt..."
pip install -r requirements.txt --quiet
ok "All Python packages installed"

# ── 7. Directories ───────────────────────────────────────────────────────────
hdr "Project directories"

for dir in data data/seed data/payloads logs tmp .run; do
  mkdir -p "$dir"
done
ok "data/ logs/ tmp/ .run/ created"

# ── 8. Environment file ─────────────────────────────────────────────────────
hdr "Environment file"

if [[ -f .env ]]; then
  ok ".env already exists"
elif [[ -f .env.example ]]; then
  cp .env.example .env
  ok "Created .env from .env.example"
else
  cat > .env <<'ENVEOF'
POSTGRES_URL=postgresql://northwind:northwind@localhost:5432/northwind
DUCKDB_PATH=data/northwind.duckdb
LLM_STUB_MODE=true
ENVEOF
  ok "Created default .env"
fi

# ── 9. Docker Compose ────────────────────────────────────────────────────────
hdr "Docker Compose"

if [[ -f docker-compose.yml || -f compose.yml ]]; then
  docker compose config --quiet
  ok "Compose config is valid"

  info "Building Docker images (this may take a few minutes on first run)..."
  docker compose build --quiet
  ok "Docker images built"
else
  fail "No docker-compose.yml or compose.yml found in project root"
fi

# ── 10. Seed DuckDB ─────────────────────────────────────────────────────────
hdr "Seed data"

info "Initializing DuckDB tables and loading seed data..."
python scripts/seed-data.py
ok "DuckDB seeded"

# ── 11. Final validation ────────────────────────────────────────────────────
hdr "Validation"

python scripts/check-requirements.py

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
printf "${GREEN}${BOLD}Setup complete!${NC}\n"
echo "========================================="
echo ""
echo "Next steps:"
echo ""
echo "  1. Start the demo environment:"
echo "     ./scripts/demo-up.sh"
echo ""
echo "  2. Validate the demo is working:"
echo "     ./scripts/run-story.sh"
echo ""
echo "  3. For author recording (requires tmux):"
echo "     module1/scripts/demo_up.sh"
echo "     tmux attach -t m1-demo"
echo ""
