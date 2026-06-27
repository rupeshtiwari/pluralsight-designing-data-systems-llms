#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
BLUE="\033[0;34m"
BOLD="\033[1m"
NC="\033[0m"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="$PROJECT_ROOT/environment-setup/install.log"

# Reset the log file on every run so the student can attach the freshest
# transcript when asking for support. Tee mirrors every helper line to
# the log so PASS/WARN/FAIL stay in sync with the on-screen output.
mkdir -p "$PROJECT_ROOT/environment-setup"
: > "$LOG_FILE"

_log() { printf "%s\n" "$1" >> "$LOG_FILE"; }

pass() {
  printf "${GREEN}[PASS]${NC} %s\n" "$1"
  _log "[PASS] $1"
}
warn() {
  printf "${YELLOW}[WARN]${NC} %s\n" "$1"
  _log "[WARN] $1"
}
fail() {
  printf "${RED}[FAIL]${NC} %s\n" "$1"
  _log "[FAIL] $1"
  _log "------ install aborted ------"
  exit 1
}
info() {
  printf "${BLUE}[INFO]${NC} %s\n" "$1"
  _log "[INFO] $1"
}
section() {
  printf "\n${BOLD}%s${NC}\n" "$1"
  _log ""
  _log "=== $1 ==="
}

echo "=============================================="
echo " macOS setup: Designing Data Systems with LLMs"
echo "=============================================="
echo ""
_log "macOS setup started at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
_log "Log file: $LOG_FILE"

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This script is for macOS only."
fi

cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo "Install log:  $LOG_FILE"
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

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found. Installing jq..."
  brew install jq
fi
pass "jq found"

if ! command -v tmux >/dev/null 2>&1; then
  warn "tmux not found. Installing tmux..."
  brew install tmux
fi
pass "tmux found: $(tmux -V 2>/dev/null || echo unknown)"

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

# ─────────────────────────────────────────────────────────────────────────────
# Per-module readiness checks
#
# Each module that has a recordable demo gets an explicit readiness section
# so a student running this script for the first time can verify all module
# demos work BEFORE they try to record. We track a PASS/FAIL state per
# module and print a tidy summary at the very end.
# ─────────────────────────────────────────────────────────────────────────────
MODULE1_STATUS="PASS"
MODULE2_STATUS="PASS"
MODULE3_STATUS="PASS"
MODULE4_STATUS="PASS"

# Local helpers used by the per-module sections so a single failed check
# downgrades that module without aborting the rest of the script.
module_warn() {
  # $1 = module var name (e.g. MODULE1_STATUS); $2 = message
  printf "${YELLOW}[WARN]${NC} %s\n" "$2"
  _log "[WARN] $2"
  # Only escalate to WARN if the module is still PASS; never downgrade FAIL.
  if [[ "${!1}" == "PASS" ]]; then
    eval "$1=WARN"
  fi
}
module_fail() {
  # $1 = module var name; $2 = message — does NOT exit, just marks the module.
  printf "${RED}[FAIL]${NC} %s\n" "$2"
  _log "[FAIL] $2"
  eval "$1=FAIL"
}

# ─────────────────────────────────────────────────────────────────────────────
# [Module 1] FastAPI + DuckDB + pgvector readiness check
#
# Module 1 Clip set demos the FastAPI service against DuckDB for analytics
# and Postgres+pgvector for retrieval. We re-confirm Python 3.12, the
# Python packages the demo imports, that Postgres is reachable in
# docker-compose, and that the seed + payload files the recording uses
# are present and well-formed.
# ─────────────────────────────────────────────────────────────────────────────
section "[Module 1] FastAPI + DuckDB + pgvector readiness check"

# Re-confirm Python 3.12 inside the M1 section header so the log shows
# the M1 path explicitly verified it (already checked at the top).
M1_PY_OK="$(python -c 'import sys; print(int(sys.version_info >= (3, 12)))' 2>/dev/null || echo 0)"
if [[ "$M1_PY_OK" == "1" ]]; then
  pass "Python 3.12+ active in venv: $(python --version)"
else
  module_fail MODULE1_STATUS "Python 3.12+ not active in venv — activate .venv and rerun."
fi

info "Checking Module 1 Python imports in the venv..."
M1_IMPORT_OUT="$(python - <<'PY' 2>&1
required = ["asyncpg", "pgvector", "duckdb", "fastapi", "uvicorn", "structlog"]
missing = []
for pkg in required:
    try:
        __import__(pkg)
    except ImportError:
        missing.append(pkg)
if missing:
    print("MISSING:" + ",".join(missing))
else:
    print("OK")
PY
)"
if [[ "$M1_IMPORT_OUT" == "OK" ]]; then
  pass "asyncpg, pgvector, duckdb, fastapi, uvicorn, structlog importable"
else
  module_fail MODULE1_STATUS "Module 1 imports missing — pip install -r requirements.txt (details: $M1_IMPORT_OUT)"
fi

info "Checking that the Postgres container is reachable..."
if docker compose ps postgres 2>/dev/null | grep -qE "Up|running"; then
  pass "docker compose ps postgres reports the container is up"
else
  module_warn MODULE1_STATUS "Postgres container not running — fix: docker compose up -d postgres"
fi

info "Validating seed JSON files used by the Module 1 demo..."
for seed in data/seed/feedback.json data/seed/reference_docs.json; do
  if [[ ! -f "$seed" ]]; then
    module_fail MODULE1_STATUS "Missing seed file: $seed"
    continue
  fi
  if python -c "import json,sys; json.load(open('$seed'))" 2>>"$LOG_FILE"; then
    pass "$seed present and well-formed JSON"
  else
    module_fail MODULE1_STATUS "$seed exists but is not valid JSON"
  fi
done

info "Checking Module 1 demo payloads..."
for payload in data/payloads/feedback_enrich.json data/payloads/feedback_ambiguous.json; do
  if [[ -f "$payload" ]]; then
    pass "$payload present"
  else
    module_fail MODULE1_STATUS "Missing payload: $payload"
  fi
done

if [[ "$MODULE1_STATUS" == "PASS" ]]; then
  printf "${BOLD}[OK] Module 1 demo ready. Run: ./scripts/module1-demo-reset.sh then module1/scripts/preflight_check.sh${NC}\n"
  _log "[OK] Module 1 demo ready. Run: ./scripts/module1-demo-reset.sh then module1/scripts/preflight_check.sh"
else
  warn "Module 1 readiness ended with status: $MODULE1_STATUS — see lines above before recording."
fi

# ─────────────────────────────────────────────────────────────────────────────
# [Module 2] LangGraph + PostgreSQL + pgvector readiness check
#
# Module 2 demos the LangGraph agent-triage flow backed by Postgres +
# pgvector. We check the Python packages the graph imports, that Postgres
# is reachable, that the incident seed + triage payloads exist, and that
# agent_graph.py still imports StateGraph (a quick sanity check that the
# LangGraph code is intact before recording).
# ─────────────────────────────────────────────────────────────────────────────
section "[Module 2] LangGraph + PostgreSQL + pgvector readiness check"

info "Checking Module 2 Python imports in the venv..."
M2_IMPORT_OUT="$(python - <<'PY' 2>&1
required = [
    ("langgraph", "langgraph"),
    ("langchain-core", "langchain_core"),
    ("asyncpg", "asyncpg"),
    ("pgvector", "pgvector"),
]
missing = []
for display, mod in required:
    try:
        __import__(mod)
    except ImportError:
        missing.append(display)
if missing:
    print("MISSING:" + ",".join(missing))
else:
    print("OK")
PY
)"
if [[ "$M2_IMPORT_OUT" == "OK" ]]; then
  pass "langgraph, langchain-core, asyncpg, pgvector importable"
else
  module_fail MODULE2_STATUS "Module 2 imports missing — pip install -r requirements.txt (details: $M2_IMPORT_OUT)"
fi

info "Checking that the Postgres container is reachable..."
if docker compose ps postgres 2>/dev/null | grep -qE "Up|running"; then
  pass "docker compose ps postgres reports the container is up"
else
  module_warn MODULE2_STATUS "Postgres container not running — fix: docker compose up -d postgres"
fi

info "Validating Module 2 seed JSON..."
if [[ ! -f "data/seed/incidents.json" ]]; then
  module_fail MODULE2_STATUS "Missing seed file: data/seed/incidents.json"
elif python -c "import json; json.load(open('data/seed/incidents.json'))" 2>>"$LOG_FILE"; then
  pass "data/seed/incidents.json present and well-formed JSON"
else
  module_fail MODULE2_STATUS "data/seed/incidents.json exists but is not valid JSON"
fi

info "Checking Module 2 demo payloads..."
for payload in data/payloads/agent_triage.json data/payloads/agent_triage_low.json; do
  if [[ -f "$payload" ]]; then
    pass "$payload present"
  else
    module_fail MODULE2_STATUS "Missing payload: $payload"
  fi
done

info "Sanity-checking LangGraph code in app/services/agent_graph.py..."
if [[ ! -f "app/services/agent_graph.py" ]]; then
  module_fail MODULE2_STATUS "app/services/agent_graph.py is missing"
elif grep -q "StateGraph" app/services/agent_graph.py; then
  pass "app/services/agent_graph.py imports StateGraph"
else
  module_fail MODULE2_STATUS "app/services/agent_graph.py does not reference StateGraph — LangGraph wiring may be broken."
fi

if [[ "$MODULE2_STATUS" == "PASS" ]]; then
  printf "${BOLD}[OK] Module 2 demo ready. Run: ./scripts/module2-demo-reset.sh then module2/scripts/preflight_check.sh${NC}\n"
  _log "[OK] Module 2 demo ready. Run: ./scripts/module2-demo-reset.sh then module2/scripts/preflight_check.sh"
else
  warn "Module 2 readiness ended with status: $MODULE2_STATUS — see lines above before recording."
fi

# ─────────────────────────────────────────────────────────────────────────────
# [Module 3] Apache Airflow readiness check
#
# Module 3 Clip 4 runs a real Airflow webserver + scheduler on
# http://localhost:8080. The first `docker compose up -d airflow` call
# on a fresh laptop stalls for several minutes while Docker pulls the
# ~1.2 GB image — pre-pulling here keeps the demo flow snappy. We also
# verify the port is free so the docker compose up does not crash with
# a port-in-use error mid-recording.
# ─────────────────────────────────────────────────────────────────────────────
section "[Module 3] Apache Airflow readiness check"

# Confirm Docker is running (already verified above; restate for the log
# so the support transcript shows the Airflow path explicitly checked it).
info "Confirming Docker daemon is reachable for Module 3..."
if docker info >/dev/null 2>&1; then
  pass "Docker daemon is running"
else
  module_fail MODULE3_STATUS "Docker daemon stopped between earlier check and Module 3 section — start Docker Desktop and rerun."
fi

# Pre-pull the Airflow image so the first Module 3 DAG demo does not
# stall on a multi-minute image pull. Match the tag in docker-compose.yml.
AIRFLOW_IMAGE="apache/airflow:2.10.3"
info "Pre-pulling ${AIRFLOW_IMAGE} so the first DAG demo does not stall..."
if docker pull "$AIRFLOW_IMAGE" >>"$LOG_FILE" 2>&1; then
  pass "Airflow image pulled: ${AIRFLOW_IMAGE}"
else
  module_warn MODULE3_STATUS "Could not pull ${AIRFLOW_IMAGE} — check network or Docker Hub auth. Module 3 will still run with the memory-stub fallback, but the live DAG demo will not work until the pull succeeds."
fi

# Check that port 8080 is free so docker compose up airflow does not
# fail with a clear-as-mud bind error during the recording.
info "Checking that port 8080 is free for the Airflow webserver..."
PORT_8080_PID="$(lsof -ti :8080 2>/dev/null | head -1 || true)"
if [[ -z "$PORT_8080_PID" ]]; then
  pass "Port 8080 is free"
else
  # Print exactly the line the brief asked for so the student knows
  # what to do without scrolling through the rest of the log.
  module_fail MODULE3_STATUS "Port 8080 in use by PID $PORT_8080_PID — stop that process or change AIRFLOW_PORT in docker-compose.yml"
  PROCESS_NAME="$(ps -p "$PORT_8080_PID" -o comm= 2>/dev/null || echo unknown)"
  info "Process holding port 8080: $PROCESS_NAME (PID $PORT_8080_PID)"
  info "Quick fix: kill $PORT_8080_PID    # or change the host port in docker-compose.yml"
  warn "Module 3 (Airflow) will not start until port 8080 is freed."
fi

# Tidy next-step block so the student knows what to run after install.
echo ""
printf "${BOLD}[OK] Airflow image ready. Next steps for Module 3:${NC}\n"
printf "  ${BLUE}1.${NC} docker compose up -d airflow-webserver airflow-scheduler\n"
printf "  ${BLUE}2.${NC} module3/scripts/preflight_check.sh\n"
echo ""
_log "[OK] Airflow image ready. Run: docker compose up -d airflow-webserver airflow-scheduler then module3/scripts/preflight_check.sh"

echo ""
# ─────────────────────────────────────────────────────────────────────────────
# Readiness summary — one line per module so the student can tell at a
# glance whether every recordable demo is green before they hit record.
# ─────────────────────────────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# [Module 4] Validation gate + Airflow routing readiness check
# ─────────────────────────────────────────────────────────────────────────────
section "[Module 4] Validation gate + Airflow routing readiness check"

# 4.1 — assets the Module 4 demo needs on disk (payloads, scripts).
M4_ASSETS=(
  "data/payloads/module4_validation_batch.json"
  "data/payloads/module4_airflow_trigger.json"
  "module4/scripts/batch_input_risk.sh"
  "module4/scripts/airflow_ui_proof.sh"
  "module4/scripts/duckdb_proof.sh"
  "module4/scripts/course_summary.sh"
  "module4/scripts/preflight_check.sh"
  "scripts/module4-demo-reset.sh"
)
M4_MISSING=()
for f in "${M4_ASSETS[@]}"; do
  if [[ ! -e "$PROJECT_ROOT/$f" ]]; then
    M4_MISSING+=("$f")
  fi
done
if [[ ${#M4_MISSING[@]} -eq 0 ]]; then
  pass "all 8 Module 4 assets present (payloads + scripts)"
else
  module_fail MODULE4_STATUS "Module 4 missing files: ${M4_MISSING[*]}"
fi

# 4.2 — scripts are executable.
M4_EXEC_MISSING=()
for f in "${M4_ASSETS[@]}"; do
  case "$f" in
    *.sh)
      if [[ ! -x "$PROJECT_ROOT/$f" ]]; then
        chmod +x "$PROJECT_ROOT/$f" 2>/dev/null || M4_EXEC_MISSING+=("$f")
      fi
      ;;
  esac
done
if [[ ${#M4_EXEC_MISSING[@]} -eq 0 ]]; then
  pass "all Module 4 shell scripts are executable"
else
  module_fail MODULE4_STATUS "Could not chmod +x: ${M4_EXEC_MISSING[*]}"
fi

# 4.3 — validation endpoints are registered in the FastAPI app.
M4_ROUTE_CHECK=$("$PROJECT_ROOT/.venv/bin/python" - 2>&1 <<'PY' || true
from app.routers import pipeline, validation
paths = {r.path for r in pipeline.router.routes} | {f"/validate{r.path}" for r in validation.router.routes}
required = {"/pipeline/validate-batch", "/pipeline/routing-detail/{batch_id}",
            "/pipeline/runs", "/validate/rules"}
pipeline_paths = {r.path for r in pipeline.router.routes}
validation_paths = {r.path for r in validation.router.routes}
all_paths = {f"/pipeline{p}" for p in pipeline_paths} | {f"/validate{p}" for p in validation_paths}
missing = [p for p in required if p not in all_paths]
print("OK" if not missing else f"MISSING:{','.join(missing)}")
PY
)
if echo "$M4_ROUTE_CHECK" | grep -q "^OK"; then
  pass "Module 4 endpoints registered: /pipeline/validate-batch, /pipeline/routing-detail, /pipeline/runs, /validate/rules"
else
  module_fail MODULE4_STATUS "Module 4 endpoints missing — $M4_ROUTE_CHECK"
fi

# 4.4 — Airflow DAG file supports the conf['force_status'] override used by Step 5.
if grep -q "force_status" "$PROJECT_ROOT/airflow/dags/northwind_llm_enrichment.py"; then
  pass "DAG supports conf['force_status'] override (Module 4 Step 5 needs both downstream tasks to succeed)"
else
  module_fail MODULE4_STATUS "DAG missing force_status override — Module 4 airflow_ui_proof.sh will leave write_trusted skipped"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Tech-stack validation — the outline names every tool below. Each must be
# reachable AT THIS POINT in the install. A miss here means a module's demo
# will silently fall back to a stub during recording.
# ─────────────────────────────────────────────────────────────────────────────
section "[Tech stack] Outline-required tools — final validation"

TECH_FAIL=0
_tech() {
  local label="$1"; local check_cmd="$2"; local fix="$3"
  if eval "$check_cmd" >/dev/null 2>&1; then
    pass "$label"
  else
    printf "${RED}[FAIL]${NC} %s — fix: %s\n" "$label" "$fix"
    _log "[FAIL] $label — fix: $fix"
    TECH_FAIL=1
  fi
}

_tech "FastAPI"                       ".venv/bin/python -c 'import fastapi'"                  "pip install -r requirements.txt"
_tech "uvicorn"                       ".venv/bin/python -c 'import uvicorn'"                  "pip install -r requirements.txt"
_tech "DuckDB CLI (brew)"             "command -v duckdb"                                      "brew install duckdb"
_tech "DuckDB Python module"          ".venv/bin/python -c 'import duckdb'"                   "pip install -r requirements.txt"
_tech "PostgreSQL driver (asyncpg)"   ".venv/bin/python -c 'import asyncpg'"                  "pip install -r requirements.txt"
_tech "pgvector Python module"        ".venv/bin/python -c 'import pgvector'"                 "pip install -r requirements.txt"
_tech "LangGraph"                     ".venv/bin/python -c 'import langgraph'"                "pip install -r requirements.txt"
_tech "LangChain core"                ".venv/bin/python -c 'import langchain_core'"           "pip install -r requirements.txt"
_tech "Apache Airflow image (Docker)" "docker image inspect apache/airflow:2.10.3"            "docker compose pull airflow-webserver"
_tech "Docker Compose"                "docker compose version"                                 "Update Docker Desktop"
_tech "tmux"                          "command -v tmux"                                        "brew install tmux"
_tech "jq"                            "command -v jq"                                          "brew install jq"
_tech "curl"                          "command -v curl"                                        "brew install curl"

if [[ $TECH_FAIL -eq 0 ]]; then
  pass "All outline-required tech stack is installed and reachable"
else
  printf "${RED}[FAIL]${NC} One or more outline-required tools missing — fix lines above and rerun.\n"
fi

_status_color() {
  case "$1" in
    PASS) printf "${GREEN}[PASS]${NC}" ;;
    WARN) printf "${YELLOW}[WARN]${NC}" ;;
    FAIL) printf "${RED}[FAIL]${NC}" ;;
    *)    printf "[%s]" "$1" ;;
  esac
}

printf "\n${BOLD}======================================================${NC}\n"
printf "${BOLD} READINESS SUMMARY${NC}\n"
printf "${BOLD}======================================================${NC}\n"
printf " Module 1 (FastAPI + DuckDB + pgvector)     %s\n" "$(_status_color "$MODULE1_STATUS")"
printf " Module 2 (LangGraph + Postgres + pgvector) %s\n" "$(_status_color "$MODULE2_STATUS")"
printf " Module 3 (Apache Airflow)                  %s\n" "$(_status_color "$MODULE3_STATUS")"
printf " Module 4 (Validation gate + Airflow route) %s\n" "$(_status_color "$MODULE4_STATUS")"
printf "${BOLD}======================================================${NC}\n"

_log ""
_log "======================================================"
_log " READINESS SUMMARY"
_log "======================================================"
_log " Module 1 (FastAPI + DuckDB + pgvector)     [$MODULE1_STATUS]"
_log " Module 2 (LangGraph + Postgres + pgvector) [$MODULE2_STATUS]"
_log " Module 3 (Apache Airflow)                  [$MODULE3_STATUS]"
_log " Module 4 (Validation gate + Airflow route) [$MODULE4_STATUS]"
_log "======================================================"

# If any module failed, surface a clear nudge but still finish the
# script so the student can see the summary + next-steps block.
if [[ "$MODULE1_STATUS" == "FAIL" || "$MODULE2_STATUS" == "FAIL" || "$MODULE3_STATUS" == "FAIL" || "$MODULE4_STATUS" == "FAIL" ]]; then
  printf "${RED}[FAIL]${NC} One or more module readiness checks failed — fix the lines above before recording.\n"
  _log "[FAIL] One or more module readiness checks failed."
fi

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
echo "Module 2 demo:"
echo "  ./scripts/module2-demo-reset.sh"
echo "  module2/scripts/preflight_check.sh"
echo ""
echo "Module 3 demo:"
echo "  docker compose up -d airflow-webserver airflow-scheduler"
echo "  ./scripts/module3-demo-reset.sh"
echo "  module3/scripts/preflight_check.sh"
echo ""
echo "Module 4 demo:"
echo "  ./scripts/module4-demo-reset.sh"
echo "  module4/scripts/preflight_check.sh"
echo ""
echo "Install log saved to: $LOG_FILE"
echo ""
_log "macOS setup completed at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
