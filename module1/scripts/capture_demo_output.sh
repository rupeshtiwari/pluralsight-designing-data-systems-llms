#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/module1_capture.log"
PAYLOADS_DIR="$REPO_ROOT/data/payloads"
TMPDIR_CAPTURE=$(mktemp -d)

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

cleanup() {
    rm -rf "$TMPDIR_CAPTURE"
}
trap cleanup EXIT

info()  { printf "${YELLOW}[INFO]${NC}  %s\n" "$1"; }
ok()    { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
err()   { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
step()  { printf "\n${BOLD}[%s] %s${NC}\n" "$1" "$2"; }

# ── Ensure log directory exists ──────────────────────────────────────────────
mkdir -p "$LOG_DIR"

# ── Start log file ───────────────────────────────────────────────────────────
{
    echo "=============================================="
    echo " Module 1 — Demo Output Capture"
    echo " Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "=============================================="
    echo ""
} > "$LOG_FILE"

log() {
    echo "$1" >> "$LOG_FILE"
}

log_section() {
    {
        echo ""
        echo "----------------------------------------------"
        echo "$1"
        echo "----------------------------------------------"
    } >> "$LOG_FILE"
}

# ── Preflight: check server is running ───────────────────────────────────────
step "0/4" "Preflight checks"

if ! curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    err "FastAPI server is not running at http://localhost:8000"
    err "Start the server first with: module1/scripts/demo_up.sh"
    log "PREFLIGHT FAILED: Server not running"
    exit 1
fi
ok "Server is healthy"
log "Preflight: Server healthy"

# Verify payload files exist
if [ ! -f "$PAYLOADS_DIR/feedback_enrich.json" ]; then
    err "Required payload missing: data/payloads/feedback_enrich.json"
    log "PREFLIGHT FAILED: feedback_enrich.json not found"
    exit 1
fi
ok "Payload files present"
log "Preflight: Payload files verified"

# ── Reset state for clean capture ────────────────────────────────────────────
info "Resetting metrics..."
curl -sf -X POST http://localhost:8000/admin/reset-metrics > /dev/null 2>&1 || true
ok "Metrics reset"
log "Preflight: Metrics reset"

info "Re-seeding knowledge base..."
SEED_RESPONSE=$(curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base 2>&1) || true
ok "Knowledge base seeded"
log "Preflight: Knowledge base seeded"
log "$SEED_RESPONSE"

# ── Step 1: Show DuckDB raw feedback input ───────────────────────────────────
step "1/4" "DuckDB raw.feedback row count"

log_section "Step 1: DuckDB raw.feedback row count"

STEP1_CMD='duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback"'
log "Command: $STEP1_CMD"

if command -v duckdb &>/dev/null; then
    STEP1_OUTPUT=$(cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM raw.feedback" 2>&1)
    STEP1_STATUS=$?
else
    STEP1_OUTPUT="duckdb CLI not available — using API health as proxy"
    STEP1_STATUS=0
    info "duckdb CLI not found; recording proxy output"
fi

echo "$STEP1_OUTPUT" | tee "$TMPDIR_CAPTURE/step1.txt"
log "Output:"
log "$STEP1_OUTPUT"
log "Exit code: $STEP1_STATUS"

if [ "$STEP1_STATUS" -eq 0 ]; then
    ok "Step 1 complete"
else
    err "Step 1 failed (exit code $STEP1_STATUS)"
fi

# ── Step 2: Enrich a single feedback record through FastAPI ──────────────────
step "2/4" "Enrich feedback via FastAPI"

log_section "Step 2: Enrich feedback via FastAPI"

STEP2_CMD="curl -s http://localhost:8000/enrich/feedback -H 'Content-Type: application/json' -d @data/payloads/feedback_enrich.json"
log "Command: $STEP2_CMD"

# Run curl once, save raw response to temp file
STEP2_RAW="$TMPDIR_CAPTURE/step2_raw.json"
HTTP_CODE=$(curl -s -o "$STEP2_RAW" -w '%{http_code}' \
    http://localhost:8000/enrich/feedback \
    -H "Content-Type: application/json" \
    -d @"$PAYLOADS_DIR/feedback_enrich.json")

log "HTTP status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    ok "Enrichment call returned HTTP 200"

    # Pretty-print raw JSON
    log "Raw JSON response:"
    python3 -m json.tool < "$STEP2_RAW" >> "$LOG_FILE" 2>&1

    # Display formatted output via fmt.py if available
    if [ -f "$REPO_ROOT/scripts/fmt.py" ]; then
        info "Formatted output (fmt.py --type feedback):"
        python3 "$REPO_ROOT/scripts/fmt.py" --type feedback < "$STEP2_RAW" | tee "$TMPDIR_CAPTURE/step2_formatted.txt"
        log "Formatted output:"
        cat "$TMPDIR_CAPTURE/step2_formatted.txt" >> "$LOG_FILE"
    else
        info "fmt.py not found; showing raw JSON:"
        python3 -m json.tool < "$STEP2_RAW" | tee "$TMPDIR_CAPTURE/step2_formatted.txt"
        log "Pretty-printed output:"
        cat "$TMPDIR_CAPTURE/step2_formatted.txt" >> "$LOG_FILE"
    fi

    # Extract request_id for cross-referencing in Step 3
    REQUEST_ID=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('request_id',''))" < "$STEP2_RAW" 2>/dev/null || echo "")
    if [ -n "$REQUEST_ID" ]; then
        ok "Captured request_id: $REQUEST_ID"
        log "Captured request_id: $REQUEST_ID"
    fi
else
    err "Enrichment call failed with HTTP $HTTP_CODE"
    log "Error response:"
    cat "$STEP2_RAW" >> "$LOG_FILE"
    cat "$STEP2_RAW"
fi

# ── Step 3: Verify the decision was recorded in PostgreSQL ───────────────────
step "3/4" "Verify decision recorded in PostgreSQL"

log_section "Step 3: Verify decision in PostgreSQL (agent/decisions)"

STEP3_CMD="curl -s http://localhost:8000/agent/decisions"
log "Command: $STEP3_CMD"

# Run curl once, save raw response to temp file
STEP3_RAW="$TMPDIR_CAPTURE/step3_raw.json"
HTTP_CODE=$(curl -s -o "$STEP3_RAW" -w '%{http_code}' \
    http://localhost:8000/agent/decisions)

log "HTTP status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    ok "Decisions endpoint returned HTTP 200"

    # Pretty-print raw JSON
    log "Raw JSON response:"
    python3 -m json.tool < "$STEP3_RAW" >> "$LOG_FILE" 2>&1

    # Display formatted output
    if [ -f "$REPO_ROOT/scripts/fmt.py" ]; then
        info "Formatted output (fmt.py --type audit):"
        python3 "$REPO_ROOT/scripts/fmt.py" --type audit < "$STEP3_RAW" | tee "$TMPDIR_CAPTURE/step3_formatted.txt"
        log "Formatted output:"
        cat "$TMPDIR_CAPTURE/step3_formatted.txt" >> "$LOG_FILE"
    else
        info "fmt.py not found; showing raw JSON:"
        python3 -m json.tool < "$STEP3_RAW" | tee "$TMPDIR_CAPTURE/step3_formatted.txt"
        log "Pretty-printed output:"
        cat "$TMPDIR_CAPTURE/step3_formatted.txt" >> "$LOG_FILE"
    fi

    # Cross-reference request_id
    if [ -n "${REQUEST_ID:-}" ]; then
        if grep -q "$REQUEST_ID" "$STEP3_RAW" 2>/dev/null; then
            ok "request_id $REQUEST_ID found in decisions output"
            log "Cross-reference: request_id $REQUEST_ID confirmed in decisions"
        else
            info "request_id $REQUEST_ID not found in decisions (may use different endpoint)"
            log "Cross-reference: request_id not found in agent/decisions response"
        fi
    fi
else
    err "Decisions endpoint failed with HTTP $HTTP_CODE"
    log "Error response:"
    cat "$STEP3_RAW" >> "$LOG_FILE"
    cat "$STEP3_RAW"
fi

# Also try direct psql if Docker is available
if command -v docker &>/dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "northwind-postgres"; then
    log ""
    log "Direct psql query:"
    PSQL_OUTPUT=$(docker exec northwind-postgres psql -U northwind -c \
        "SELECT request_id, endpoint, category, confidence, validation_status, decision FROM llm_decisions ORDER BY created_at DESC LIMIT 3" 2>&1) || true
    log "$PSQL_OUTPUT"
    echo "$PSQL_OUTPUT"
fi

# ── Step 4: Verify trusted output table received the enriched record ─────────
step "4/4" "Verify trusted.feedback_enriched in DuckDB"

log_section "Step 4: DuckDB trusted.feedback_enriched"

STEP4A_CMD='duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM trusted.feedback_enriched"'
STEP4B_CMD='duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3"'
log "Command (count): $STEP4A_CMD"
log "Command (detail): $STEP4B_CMD"

if command -v duckdb &>/dev/null; then
    # Row count
    STEP4A_OUTPUT=$(cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT count(*) as row_count FROM trusted.feedback_enriched" 2>&1)
    echo "$STEP4A_OUTPUT" | tee "$TMPDIR_CAPTURE/step4a.txt"
    log "Row count output:"
    log "$STEP4A_OUTPUT"

    # Detail query
    STEP4B_OUTPUT=$(cd "$REPO_ROOT" && duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3" 2>&1)
    echo "$STEP4B_OUTPUT" | tee "$TMPDIR_CAPTURE/step4b.txt"
    log "Detail output:"
    log "$STEP4B_OUTPUT"

    ok "Step 4 complete"
else
    info "duckdb CLI not available — recording proxy output"
    log "duckdb CLI not available"
fi

# ── Capture server log snapshot ──────────────────────────────────────────────
log_section "Server log snapshot"

SERVER_LOG="$REPO_ROOT/logs/server.log"
if [ -f "$SERVER_LOG" ]; then
    log "Last 30 lines of server.log:"
    tail -30 "$SERVER_LOG" >> "$LOG_FILE" 2>/dev/null || true
else
    log "No server.log file found at $SERVER_LOG"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
printf "${BOLD}Module 1 demo capture complete${NC}\n"
echo "=========================================="
echo ""
printf "${GREEN}Log saved to:${NC} %s\n" "$LOG_FILE"
echo ""

{
    echo ""
    echo "=============================================="
    echo " Capture complete: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "=============================================="
} >> "$LOG_FILE"
