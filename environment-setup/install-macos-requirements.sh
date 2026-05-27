#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; exit 1; }

echo "=============================================="
echo " macOS setup: Designing Data Systems with LLMs"
echo "=============================================="
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This script is for macOS only."
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo ""

echo "Checking Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew is required. Install it from https://brew.sh/ and rerun this script."
fi
pass "Homebrew found: $(brew --version | head -1)"

echo ""
echo "Installing required local tools..."

if ! command -v git >/dev/null 2>&1; then
  warn "Git not found. Installing git..."
  brew install git
fi
pass "Git found: $(git --version)"

if ! command -v python3.12 >/dev/null 2>&1; then
  warn "Python 3.12 not found. Installing python@3.12..."
  brew install python@3.12
fi

PYTHON_CMD="python3.12"
PY_OK="$($PYTHON_CMD -c 'import sys; print(int(sys.version_info >= (3, 12)))')"
if [[ "$PY_OK" != "1" ]]; then
  fail "Python 3.12+ is required."
fi
pass "Python found: $($PYTHON_CMD --version)"

if ! command -v duckdb >/dev/null 2>&1; then
  warn "DuckDB CLI not found. Installing duckdb..."
  brew install duckdb
fi
pass "DuckDB found: $(duckdb --version 2>&1 | head -1)"

if ! command -v curl >/dev/null 2>&1; then
  warn "curl not found. Installing curl..."
  brew install curl
fi
pass "curl found"

echo ""
echo "Checking Docker Desktop..."

if ! command -v docker >/dev/null 2>&1; then
  warn "Docker CLI not found. Installing Docker Desktop..."
  brew install --cask docker || true
  echo ""
  echo "=============================================="
  echo " Docker Desktop has been installed."
  echo " Open Docker Desktop from Applications,"
  echo " wait until it finishes starting,"
  echo " then rerun this script."
  echo "=============================================="
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo ""
  echo "=============================================="
  echo " Docker Desktop is installed but not running."
  echo " Open Docker Desktop, wait until it says"
  echo " Docker is running, then rerun this script."
  echo "=============================================="
  exit 1
fi

pass "Docker is installed and running"

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose is not available. Update Docker Desktop and rerun this script."
fi
pass "Docker Compose found: $(docker compose version)"

echo ""
echo "Creating Python virtual environment..."

if [[ ! -d ".venv" ]]; then
  "$PYTHON_CMD" -m venv .venv
  pass "Created .venv"
else
  pass ".venv already exists"
fi

source .venv/bin/activate

echo ""
echo "Installing Python dependencies..."

python -m pip install --upgrade pip setuptools wheel

if [[ ! -f "requirements.txt" ]]; then
  fail "requirements.txt not found. Cannot install project dependencies."
fi

pip install -r requirements.txt
pass "Python dependencies installed"

echo ""
echo "Creating local folders..."

mkdir -p data logs tmp .run
pass "Created data, logs, tmp, and .run folders"

echo ""
echo "Creating .env file if missing..."

if [[ ! -f ".env" ]]; then
  if [[ -f ".env.example" ]]; then
    cp .env.example .env
    pass "Created .env from .env.example"
  else
    cat > .env <<'EOF'
APP_ENV=local
APP_HOST=0.0.0.0
APP_PORT=8000
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/northwind
DUCKDB_PATH=data/northwind.duckdb
LLM_MODE=stub
EOF
    pass "Created default .env"
  fi
else
  pass ".env already exists"
fi

echo ""
echo "Making scripts executable..."

chmod +x setup.sh 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x environment-setup/*.sh 2>/dev/null || true
pass "Shell scripts are executable"

echo ""
echo "Validating Docker Compose..."

if [[ -f "compose.yml" || -f "docker-compose.yml" ]]; then
  docker compose config >/dev/null
  pass "Docker Compose config is valid"

  echo ""
  echo "Building Docker services..."
  docker compose build
  pass "Docker services built"
else
  warn "No compose.yml or docker-compose.yml found. Skipping Docker build."
fi

echo ""
echo "Final environment validation..."

command -v git >/dev/null 2>&1 || fail "Git missing"
command -v duckdb >/dev/null 2>&1 || fail "DuckDB missing"
command -v curl >/dev/null 2>&1 || fail "curl missing"
docker info >/dev/null 2>&1 || fail "Docker not running"
docker compose version >/dev/null 2>&1 || fail "Docker Compose missing"

python - <<'PY'
import sys
if sys.version_info < (3, 12):
    raise SystemExit("Python 3.12+ required")

required = ["fastapi", "uvicorn", "duckdb", "pydantic", "httpx"]
missing = []

for package in required:
    try:
        __import__(package)
    except ImportError:
        missing.append(package)

if missing:
    raise SystemExit(f"Missing Python packages: {', '.join(missing)}")

print("Python imports validated")
PY

pass "Python imports validated"

echo ""
echo "=============================================="
echo " macOS environment ready for course demos"
echo "=============================================="
echo ""
echo "Next commands:"
echo "  source .venv/bin/activate"
echo "  ./scripts/demo-up.sh"
echo "  ./scripts/run-story.sh"
echo ""
echo "Module 1 demo:"
echo "  ./scripts/module1-demo-reset.sh"
echo "  ./scripts/module1-demo-run.sh"
echo "  ./scripts/module1-demo-verify.sh"
echo ""
