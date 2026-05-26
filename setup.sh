#!/usr/bin/env bash
set -euo pipefail

echo "Setting up Designing Data Systems with LLMs local environment..."

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"

OS_NAME="$(uname -s)"
echo "Detected OS: $OS_NAME"

echo ""
echo "Checking Python 3..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3.12+ is required."
  echo "Install Python from https://www.python.org/downloads/ and rerun this script."
  exit 1
fi

PYTHON_VERSION="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')"
PYTHON_OK="$(python3 -c 'import sys; print(int(sys.version_info >= (3, 12)))')"

if [[ "$PYTHON_OK" != "1" ]]; then
  echo "Python 3.12+ is required. Detected: $PYTHON_VERSION"
  exit 1
fi

echo "Python detected: $PYTHON_VERSION"

echo ""
echo "Checking DuckDB CLI..."
if ! command -v duckdb >/dev/null 2>&1; then
  echo "DuckDB CLI not found."

  if [[ "$OS_NAME" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      echo "Installing DuckDB CLI with Homebrew..."
      brew install duckdb
    else
      echo "Install Homebrew from https://brew.sh/ or install DuckDB manually:"
      echo "  https://duckdb.org/docs/installation/"
      exit 1
    fi
  elif [[ "$OS_NAME" == "Linux" ]]; then
    echo "Install DuckDB CLI using the official instructions:"
    echo "  https://duckdb.org/docs/installation/"
    echo "Then rerun this script."
    exit 1
  else
    echo "Unsupported shell OS for automatic DuckDB install: $OS_NAME"
    echo "For Windows, use setup.ps1."
    exit 1
  fi
else
  echo "DuckDB detected: $(duckdb --version 2>&1 | head -1)"
fi

echo ""
echo "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required."
  echo "Install Docker Desktop or Docker Engine and rerun this script."
  echo "Docker Desktop: https://www.docker.com/products/docker-desktop/"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running."
  echo "Start Docker Desktop or Docker Engine and rerun this script."
  exit 1
fi

echo "Docker is running."

echo ""
echo "Checking Docker Compose..."
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose is not available."
  echo "Install Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi
echo "Docker Compose is available."

echo ""
echo "Creating Python virtual environment..."
python3 -m venv .venv

echo ""
echo "Activating virtual environment..."
source .venv/bin/activate

echo ""
echo "Upgrading Python packaging tools..."
python -m pip install --upgrade pip setuptools wheel

echo ""
echo "Installing Python dependencies..."
if [[ -f requirements.txt ]]; then
  pip install -r requirements.txt
else
  echo "requirements.txt not found."
  echo "Create requirements.txt before using this repo for student demos."
  exit 1
fi

echo ""
echo "Creating local folders..."
mkdir -p data logs tmp

echo ""
echo "Creating .env file if missing..."
if [[ ! -f .env ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example .env
    echo "Created .env from .env.example"
  else
    cat > .env <<'EOF'
APP_ENV=local
APP_HOST=0.0.0.0
APP_PORT=8000
DATABASE_URL=postgresql://northwind:northwind@localhost:5432/northwind
DUCKDB_PATH=data/northwind.duckdb
LLM_MODE=stub
EOF
    echo "Created default .env"
  fi
else
  echo ".env already exists"
fi

echo ""
echo "Validating Docker Compose file..."
if [[ -f compose.yml || -f docker-compose.yml ]]; then
  docker compose config >/dev/null
  echo "Docker Compose config is valid."

  echo ""
  echo "Building Docker services..."
  docker compose build
else
  echo "No compose.yml or docker-compose.yml found. Skipping Docker Compose build."
fi

echo ""
echo "Running setup validation..."
python scripts/check-requirements.py

echo ""
echo "Setup complete."
echo ""
echo "Next commands:"
echo "  source .venv/bin/activate"
echo "  docker compose up -d"
echo ""
echo "After the app starts, validate with:"
echo "  curl -s http://localhost:8000/health | python3 -m json.tool"
echo ""
echo "DuckDB check:"
echo '  duckdb data/northwind.duckdb "SELECT count(*) FROM raw.feedback;"'
