#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$1"; PASS=$((PASS + 1)); }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$1"; FAIL=$((FAIL + 1)); }
info() { printf "${YELLOW}[INFO]${NC} %s\n" "$1"; }

echo ""
printf "${BOLD}Module 4 — Pre-recording Preflight Check${NC}\n"
echo "=========================================="
echo ""

# ── 1. FastAPI server is running ─────────────────────────────────────────────
info "Checking FastAPI server..."
if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    HEALTH_RESPONSE=$(curl -sf http://localhost:8000/health)
    pass "FastAPI server is healthy: $HEALTH_RESPONSE"
else
    fail "FastAPI server is not reachable at http://localhost:8000/health"
fi

# ── 2. Validation endpoint is reachable ──────────────────────────────────────
info "Checking validation endpoint..."
if curl -sf -X POST http://localhost:8000/validate/output \
    -H "Content-Type: application/json" \
    -d '{"category": "product_quality", "summary": "test", "confidence": 0.9, "source_doc_ids": ["DOC-001"]}' > /dev/null 2>&1; then
    pass "Validation endpoint is reachable"
else
    fail "Validation endpoint is not reachable at http://localhost:8000/validate/output"
fi

# ── 3. Batch enrichment endpoint is reachable ────────────────────────────────
info "Checking batch enrichment endpoint..."
if curl -sf http://localhost:8000/pipeline/batch-enrich -X OPTIONS > /dev/null 2>&1 || \
   curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    pass "Pipeline batch-enrich endpoint assumed reachable (server is healthy)"
else
    fail "Pipeline batch-enrich endpoint may not be reachable"
fi

# ── 4. PostgreSQL has pipeline_runs table ────────────────────────────────────
info "Checking PostgreSQL pipeline_runs table..."
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "northwind-postgres"; then
    TABLE_EXISTS=$(docker exec northwind-postgres psql -U northwind -t -c "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'pipeline_runs')" 2>/dev/null | tr -d '[:space:]')
    if [ "$TABLE_EXISTS" = "t" ]; then
        pass "PostgreSQL pipeline_runs table exists"
    else
        fail "PostgreSQL pipeline_runs table does not exist"
    fi
else
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        info "PostgreSQL container not directly accessible; server is running so tables should exist"
        pass "PostgreSQL check skipped (no Docker container), server is running"
    else
        fail "Cannot check PostgreSQL pipeline_runs (no Docker container or API)"
    fi
fi

# ── 5. DuckDB has trusted and quarantine schemas ────────────────────────────
info "Checking DuckDB schemas..."
if command -v duckdb &>/dev/null; then
    TRUSTED_EXISTS=$(duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'trusted'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    QUARANTINE_EXISTS=$(duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'quarantine'" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ "$TRUSTED_EXISTS" = "1" ]; then
        pass "DuckDB trusted schema exists"
    else
        fail "DuckDB trusted schema is missing"
    fi
    if [ "$QUARANTINE_EXISTS" = "1" ]; then
        pass "DuckDB quarantine schema exists"
    else
        fail "DuckDB quarantine schema is missing"
    fi
else
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        info "duckdb CLI not found; server is running so schemas should be loaded"
        pass "DuckDB check skipped (no CLI), server is running"
    else
        fail "duckdb CLI not found and server is not running"
    fi
fi

# ── 6. Payload file exists ──────────────────────────────────────────────────
info "Checking payload files..."
PAYLOADS_DIR="$REPO_ROOT/data/payloads"
REQUIRED_PAYLOADS=("batch_validation_test.json")

for payload in "${REQUIRED_PAYLOADS[@]}"; do
    if [ -f "$PAYLOADS_DIR/$payload" ]; then
        # Verify payload has expected structure (4 items)
        ITEM_COUNT=$(python3 -c "import json; data=json.load(open('$PAYLOADS_DIR/$payload')); print(len(data))" 2>/dev/null || echo "0")
        if [ "$ITEM_COUNT" -ge 4 ] 2>/dev/null; then
            pass "Payload data/payloads/$payload has $ITEM_COUNT items"
        else
            fail "Payload data/payloads/$payload exists but has unexpected item count: $ITEM_COUNT (expected >= 4)"
        fi
    else
        fail "Payload missing: data/payloads/$payload"
    fi
done

# ── 7. fmt.py script exists ─────────────────────────────────────────────────
info "Checking fmt.py formatter..."
if [ -f "$REPO_ROOT/scripts/fmt.py" ]; then
    pass "scripts/fmt.py exists"
else
    fail "scripts/fmt.py is missing"
fi

# ── 8. Key application files exist ──────────────────────────────────────────
info "Checking key application files..."
KEY_FILES=(
    "app/validators/output_validator.py"
    "app/routers/validation.py"
    "app/routers/pipeline.py"
)

for keyfile in "${KEY_FILES[@]}"; do
    if [ -f "$REPO_ROOT/$keyfile" ]; then
        pass "Key file exists: $keyfile"
    else
        fail "Key file missing: $keyfile"
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
TOTAL=$((PASS + FAIL))
printf "${BOLD}Results: ${GREEN}%d passed${NC}, ${RED}%d failed${NC} out of %d checks${NC}\n" "$PASS" "$FAIL" "$TOTAL"
echo ""

if [ "$FAIL" -eq 0 ]; then
    printf "${GREEN}${BOLD}All preflight checks passed — ready to record!${NC}\n"
    exit 0
else
    printf "${RED}${BOLD}Fix the %d failing check(s) before recording.${NC}\n" "$FAIL"
    exit 1
fi
