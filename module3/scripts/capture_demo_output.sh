#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/module3_capture.log"
API_URL="http://localhost:8000"
TMPDIR_CAP=$(mktemp -d)

cleanup() { rm -rf "$TMPDIR_CAP"; }
trap cleanup EXIT

mkdir -p "$REPO_ROOT/logs"

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

step() { printf "\n${BOLD}[%s] %s${NC}\n" "$1" "$2"; }
ok()   { printf "${GREEN}[OK]${NC}    %s\n" "$1"; }
err()  { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
info() { printf "${YELLOW}[INFO]${NC}  %s\n" "$1"; }

{
    echo "=============================================="
    echo " Module 3 — Demo Output Capture"
    echo " Captured: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "=============================================="
} > "$LOG_FILE"

log() { echo "$1" >> "$LOG_FILE"; }

# Preflight
step "0/4" "Preflight checks"
if ! curl -sf "$API_URL/health" > /dev/null 2>&1; then
    err "Server not running at $API_URL"
    exit 1
fi
ok "Server healthy"

# Log payload content
log ""
log "=== Payload: batch_feedback.json ==="
cat "$REPO_ROOT/data/payloads/batch_feedback.json" >> "$LOG_FILE"

# Reset metrics and seed
info "Resetting metrics..."
curl -sf -X POST "$API_URL/admin/reset-metrics" > /dev/null 2>&1 || true
curl -sf -X POST "$API_URL/admin/seed-knowledge-base" > /dev/null 2>&1 || true
ok "Metrics reset and knowledge base seeded"

# Step 1: Trigger pipeline
step "1/4" "Trigger Airflow DAG via pipeline API"

curl -s -o "$TMPDIR_CAP/step1.json" \
    -X POST "$API_URL/pipeline/trigger" \
    -H "Content-Type: application/json" \
    -d '{"batch_id": "BATCH-20240318-001", "source": "data/payloads/batch_feedback.json"}'

log ""
log "=== Step 1: Trigger pipeline ==="
python3 -m json.tool < "$TMPDIR_CAP/step1.json" >> "$LOG_FILE" 2>&1

info "Formatted output:"
python3 "$REPO_ROOT/scripts/fmt.py" --type raw < "$TMPDIR_CAP/step1.json" 2>/dev/null || python3 -m json.tool < "$TMPDIR_CAP/step1.json"
ok "Pipeline triggered"

# Step 2: Show pipeline runs
step "2/4" "Pipeline run results"

curl -s -o "$TMPDIR_CAP/step2.json" "$API_URL/pipeline/runs"

log ""
log "=== Step 2: Pipeline runs ==="
python3 -m json.tool < "$TMPDIR_CAP/step2.json" >> "$LOG_FILE" 2>&1

info "Formatted output:"
python3 "$REPO_ROOT/scripts/fmt.py" --type raw < "$TMPDIR_CAP/step2.json" 2>/dev/null || python3 -m json.tool < "$TMPDIR_CAP/step2.json"
ok "Pipeline runs retrieved"

# Step 3: Batch details
step "3/4" "Batch enrichment details"

curl -s -o "$TMPDIR_CAP/step3.json" "$API_URL/pipeline/run/BATCH-20240318-001"

log ""
log "=== Step 3: Batch details ==="
python3 -m json.tool < "$TMPDIR_CAP/step3.json" >> "$LOG_FILE" 2>&1

info "Formatted output:"
python3 "$REPO_ROOT/scripts/fmt.py" --type batch < "$TMPDIR_CAP/step3.json" 2>/dev/null || python3 -m json.tool < "$TMPDIR_CAP/step3.json"
ok "Batch details retrieved"

# Step 4: DuckDB trusted and quarantine
step "4/4" "DuckDB trusted output and quarantine"

log ""
log "=== Step 4: DuckDB tables ==="

if command -v duckdb &>/dev/null; then
    info "Trusted table:"
    TRUSTED_OUT=$(cd "$REPO_ROOT" && duckdb data/northwind.duckdb \
        "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5" 2>&1)
    echo "$TRUSTED_OUT"
    log "trusted.feedback_enriched:"
    log "$TRUSTED_OUT"

    info "Quarantine table:"
    QUARANTINE_OUT=$(cd "$REPO_ROOT" && duckdb data/northwind.duckdb \
        "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5" 2>&1)
    echo "$QUARANTINE_OUT"
    log "quarantine.llm_outputs:"
    log "$QUARANTINE_OUT"
else
    info "duckdb CLI not available; skipping direct table queries"
    log "duckdb CLI not available"
fi

ok "Step 4 complete"

echo ""
echo "=============================================="
ok "Module 3 capture complete"
echo "Log saved to: $LOG_FILE"
