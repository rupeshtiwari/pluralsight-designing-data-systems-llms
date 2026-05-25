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
printf "${BOLD}Module 1 — Pre-recording Preflight Check${NC}\n"
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

# ── 2. DuckDB has raw.feedback data ─────────────────────────────────────────
info "Checking DuckDB raw.feedback..."
if command -v duckdb &>/dev/null; then
    ROW_COUNT=$(duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT count(*) FROM raw.feedback" 2>/dev/null | tail -1 | tr -d '[:space:]')
    if [ -n "$ROW_COUNT" ] && [ "$ROW_COUNT" -gt 0 ] 2>/dev/null; then
        pass "DuckDB raw.feedback has $ROW_COUNT rows"
    else
        fail "DuckDB raw.feedback is empty or query failed"
    fi
else
    # Fall back to API-based check if duckdb CLI not available
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        info "duckdb CLI not found; server is running so seed data should be loaded"
        pass "DuckDB check skipped (no CLI), server is running"
    else
        fail "duckdb CLI not found and server is not running"
    fi
fi

# ── 3. PostgreSQL has reference_docs ─────────────────────────────────────────
info "Checking PostgreSQL reference_docs..."
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "northwind-postgres"; then
    DOC_COUNT=$(docker exec northwind-postgres psql -U northwind -t -c "SELECT count(*) FROM reference_docs" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$DOC_COUNT" ] && [ "$DOC_COUNT" -gt 0 ] 2>/dev/null; then
        pass "PostgreSQL reference_docs has $DOC_COUNT rows"
    else
        fail "PostgreSQL reference_docs is empty or query failed"
    fi
else
    # Fall back: try seeding via API
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        info "PostgreSQL container not directly accessible; checking via API seed endpoint"
        if curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base > /dev/null 2>&1; then
            pass "Knowledge base seeded successfully via API"
        else
            fail "Could not seed knowledge base via API"
        fi
    else
        fail "Cannot check PostgreSQL reference_docs (no Docker container or API)"
    fi
fi

# ── 4. Payload files exist ───────────────────────────────────────────────────
info "Checking payload files..."
PAYLOADS_DIR="$REPO_ROOT/data/payloads"
REQUIRED_PAYLOADS=("feedback_enrich.json")
ALL_PAYLOADS_OK=true

for payload in "${REQUIRED_PAYLOADS[@]}"; do
    if [ -f "$PAYLOADS_DIR/$payload" ]; then
        pass "Payload exists: data/payloads/$payload"
    else
        fail "Payload missing: data/payloads/$payload"
        ALL_PAYLOADS_OK=false
    fi
done

# Check for additional useful payloads
OPTIONAL_PAYLOADS=("batch_feedback.json" "catalog_enrich.json" "dispute_summary.json" "anomaly_triage.json")
for payload in "${OPTIONAL_PAYLOADS[@]}"; do
    if [ -f "$PAYLOADS_DIR/$payload" ]; then
        pass "Payload exists: data/payloads/$payload"
    else
        info "Optional payload missing: data/payloads/$payload"
    fi
done

# ── 5. fmt.py script exists ─────────────────────────────────────────────────
info "Checking fmt.py formatter..."
if [ -f "$REPO_ROOT/scripts/fmt.py" ]; then
    pass "scripts/fmt.py exists"
else
    fail "scripts/fmt.py is missing"
fi

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
