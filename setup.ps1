# ─────────────────────────────────────────────────────────────────────────────
# Student-facing setup for "Designing Data Systems with LLMs"
# Windows PowerShell. For macOS/Linux use setup.sh.
# ─────────────────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

function OK($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function FAIL($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }
function INFO($msg) { Write-Host "[....] $msg" -ForegroundColor Yellow }
function HDR($msg)  { Write-Host "`n-- $msg" -ForegroundColor White }

Write-Host ""
Write-Host "========================================="
Write-Host " Designing Data Systems with LLMs"
Write-Host " Project Setup"
Write-Host "========================================="
Write-Host ""
Write-Host "Project root: $ProjectRoot"

# ── 1. Python ────────────────────────────────────────────────────────────────
HDR "Python 3.12+"

$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) { $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $pythonCmd) { FAIL "Python 3.12+ required. Install from https://www.python.org/downloads/" }

$python = $pythonCmd.Source
$pyOk = & $python -c "import sys; print(int(sys.version_info >= (3, 12)))"
$pyVer = & $python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"

if ($pyOk -ne "1") { FAIL "Python 3.12+ required (detected $pyVer)" }
OK "Python $pyVer"

# ── 2. Docker (hard requirement) ─────────────────────────────────────────────
HDR "Docker"

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    FAIL "Docker not found. Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
}

$dockerInfo = docker info 2>&1
if ($LASTEXITCODE -ne 0) {
    FAIL "Docker daemon is not running. Start Docker Desktop and rerun this script."
}
OK "Docker daemon is running"

$composeVer = docker compose version 2>&1
if ($LASTEXITCODE -ne 0) {
    FAIL "Docker Compose not available. Update Docker Desktop or install Compose."
}
OK "Docker Compose available"

# ── 3. DuckDB CLI ────────────────────────────────────────────────────────────
HDR "DuckDB CLI"

if (-not (Get-Command duckdb -ErrorAction SilentlyContinue)) {
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        INFO "Installing DuckDB CLI with winget..."
        winget install DuckDB.cli --accept-package-agreements --accept-source-agreements
    }
    else {
        Write-Host ""
        Write-Host "  DuckDB CLI is not installed."
        Write-Host "  Download from: https://duckdb.org/docs/installation/"
        Write-Host ""
        FAIL "DuckDB CLI required. Install it and rerun this script."
    }
}
OK "DuckDB CLI detected"

# ── 4. Virtual environment ───────────────────────────────────────────────────
HDR "Python virtual environment"

$venvDir = Join-Path $ProjectRoot ".venv"
$venvPython = Join-Path $venvDir "Scripts\python.exe"

if (Test-Path $venvPython) {
    OK ".venv already exists"
}
else {
    INFO "Creating .venv..."
    & $python -m venv .venv
    OK ".venv created"
}

INFO "Upgrading pip..."
& $venvPython -m pip install --upgrade pip setuptools wheel --quiet
OK "pip upgraded"

# ── 5. Python dependencies ───────────────────────────────────────────────────
HDR "Python dependencies"

if (-not (Test-Path "requirements.txt")) { FAIL "requirements.txt not found" }

INFO "Installing from requirements.txt..."
& $venvPython -m pip install -r requirements.txt --quiet
OK "All Python packages installed"

# ── 6. Directories ───────────────────────────────────────────────────────────
HDR "Project directories"

foreach ($dir in @("data", "data\seed", "data\payloads", "logs", "tmp", ".run")) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
}
OK "data/ logs/ tmp/ .run/ created"

# ── 7. Environment file ─────────────────────────────────────────────────────
HDR "Environment file"

if (Test-Path ".env") {
    OK ".env already exists"
}
elseif (Test-Path ".env.example") {
    Copy-Item ".env.example" ".env"
    OK "Created .env from .env.example"
}
else {
    @"
POSTGRES_URL=postgresql://northwind:northwind@localhost:5432/northwind
DUCKDB_PATH=data/northwind.duckdb
LLM_STUB_MODE=true
"@ | Set-Content ".env"
    OK "Created default .env"
}

# ── 8. Docker Compose ────────────────────────────────────────────────────────
HDR "Docker Compose"

$hasCompose = (Test-Path "docker-compose.yml") -or (Test-Path "compose.yml")
if (-not $hasCompose) { FAIL "No docker-compose.yml or compose.yml found" }

docker compose config --quiet 2>$null
OK "Compose config is valid"

INFO "Building Docker images (this may take a few minutes on first run)..."
docker compose build --quiet
OK "Docker images built"

# ── 9. Seed DuckDB ──────────────────────────────────────────────────────────
HDR "Seed data"

INFO "Initializing DuckDB tables and loading seed data..."
& $venvPython scripts/seed-data.py
OK "DuckDB seeded"

# ── 10. Final validation ────────────────────────────────────────────────────
HDR "Validation"

& $venvPython scripts/check-requirements.py

# ── Done ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================="
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "========================================="
Write-Host ""
Write-Host "Next steps:"
Write-Host ""
Write-Host "  1. Start the demo environment:"
Write-Host "     docker compose up -d"
Write-Host "     # then wait for health check:"
Write-Host "     curl http://localhost:8000/health"
Write-Host ""
Write-Host "  2. Validate the demo is working:"
Write-Host "     .\.venv\Scripts\Activate.ps1"
Write-Host "     python scripts/run-story.py"
Write-Host ""
