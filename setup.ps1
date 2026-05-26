$ErrorActionPreference = "Stop"

Write-Host "Setting up Designing Data Systems with LLMs local environment..."

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ProjectRoot

Write-Host "Project root: $ProjectRoot"

Write-Host ""
Write-Host "Checking Python..."
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    $pythonCmd = Get-Command python3 -ErrorAction SilentlyContinue
}

if (-not $pythonCmd) {
    Write-Host "Python 3.12+ is required."
    Write-Host "Install Python from https://www.python.org/downloads/ and rerun this script."
    exit 1
}

$python = $pythonCmd.Source
$pyOk = & $python -c "import sys; print(int(sys.version_info >= (3, 12)))"
$pyVersion = & $python -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"

if ($pyOk -ne "1") {
    Write-Host "Python 3.12+ is required. Detected: $pyVersion"
    exit 1
}

Write-Host "Python detected: $pyVersion"

Write-Host ""
Write-Host "Checking DuckDB CLI..."
$duckdbCmd = Get-Command duckdb -ErrorAction SilentlyContinue
if (-not $duckdbCmd) {
    Write-Host "DuckDB CLI not found."

    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "Trying to install DuckDB CLI with winget..."
        winget install DuckDB.cli --accept-package-agreements --accept-source-agreements
    }
    else {
        Write-Host "Install DuckDB CLI manually from:"
        Write-Host "  https://duckdb.org/docs/installation/"
        Write-Host "Then rerun this script."
        exit 1
    }
}
else {
    Write-Host "DuckDB detected."
}

Write-Host ""
Write-Host "Checking Docker..."
$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Host "Docker is required."
    Write-Host "Install Docker Desktop and rerun this script."
    Write-Host "  https://www.docker.com/products/docker-desktop/"
    exit 1
}

try {
    docker info 2>$null | Out-Null
}
catch {
    Write-Host "Docker is installed but not running."
    Write-Host "Start Docker Desktop and rerun this script."
    exit 1
}
Write-Host "Docker is running."

Write-Host ""
Write-Host "Checking Docker Compose..."
try {
    docker compose version | Out-Null
}
catch {
    Write-Host "Docker Compose is not available."
    Write-Host "Install Docker Compose: https://docs.docker.com/compose/install/"
    exit 1
}
Write-Host "Docker Compose is available."

Write-Host ""
Write-Host "Creating Python virtual environment..."
& $python -m venv .venv

$venvPython = Join-Path $ProjectRoot ".venv\Scripts\python.exe"

Write-Host ""
Write-Host "Upgrading Python packaging tools..."
& $venvPython -m pip install --upgrade pip setuptools wheel

Write-Host ""
Write-Host "Installing Python dependencies..."
if (Test-Path "requirements.txt") {
    & $venvPython -m pip install -r requirements.txt
}
else {
    Write-Host "requirements.txt not found."
    Write-Host "Create requirements.txt before using this repo for student demos."
    exit 1
}

Write-Host ""
Write-Host "Creating local folders..."
New-Item -ItemType Directory -Force -Path data | Out-Null
New-Item -ItemType Directory -Force -Path logs | Out-Null
New-Item -ItemType Directory -Force -Path tmp | Out-Null

Write-Host ""
Write-Host "Creating .env file if missing..."
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "Created .env from .env.example"
    }
    else {
        @"
APP_ENV=local
APP_HOST=0.0.0.0
APP_PORT=8000
DATABASE_URL=postgresql://northwind:northwind@localhost:5432/northwind
DUCKDB_PATH=data/northwind.duckdb
LLM_MODE=stub
"@ | Set-Content ".env"
        Write-Host "Created default .env"
    }
}
else {
    Write-Host ".env already exists"
}

Write-Host ""
Write-Host "Validating Docker Compose file..."
if ((Test-Path "compose.yml") -or (Test-Path "docker-compose.yml")) {
    docker compose config 2>$null | Out-Null
    Write-Host "Docker Compose config is valid."

    Write-Host ""
    Write-Host "Building Docker services..."
    docker compose build
}
else {
    Write-Host "No compose.yml or docker-compose.yml found. Skipping Docker Compose build."
}

Write-Host ""
Write-Host "Running setup validation..."
& $venvPython scripts/check-requirements.py

Write-Host ""
Write-Host "Setup complete."
Write-Host ""
Write-Host "Next commands:"
Write-Host "  .\.venv\Scripts\Activate.ps1"
Write-Host "  docker compose up -d"
Write-Host ""
Write-Host "After the app starts, validate with:"
Write-Host "  curl -s http://localhost:8000/health | python3 -m json.tool"
Write-Host ""
Write-Host "DuckDB check:"
Write-Host '  duckdb data/northwind.duckdb "SELECT count(*) FROM raw.feedback;"'
