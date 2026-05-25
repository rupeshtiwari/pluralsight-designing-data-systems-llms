#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_FILE="$REPO_ROOT/logs/module1_capture.log"
API_URL="http://localhost:8000"

mkdir -p "$REPO_ROOT/logs"

exec > >(tee "$LOG_FILE") 2>&1

echo "=== Module 1 Demo Capture ==="
echo "Date: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo ""

# Preflight
echo "[preflight] Checking server health..."
if ! curl -sf "$API_URL/health" > /dev/null 2>&1; then
    echo "[preflight] FAIL: Server not running at $API_URL"
    exit 1
fi
echo "[preflight] Server is healthy"

# Log payload content for verification
echo ""
echo "=== Payload Verification ==="
echo "--- feedback_enrich.json ---"
cat "$REPO_ROOT/data/payloads/feedback_enrich.json"
echo ""

# Reset metrics and seed
echo ""
echo "[setup] Resetting metrics..."
curl -sf -X POST "$API_URL/admin/reset-metrics" > /dev/null
echo "[setup] Seeding knowledge base..."
curl -sf -X POST "$API_URL/admin/seed-knowledge-base" > /dev/null
echo "[setup] Ready"
echo ""

# Step 1: DuckDB raw feedback count
echo "=== [1/4] DuckDB raw feedback input ==="
duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT count(*) as row_count FROM raw.feedback"
echo ""

# Step 2: Enrich a single feedback record
echo "=== [2/4] Enrich feedback via FastAPI ==="
STEP2_TMP=$(mktemp)
curl -s "$API_URL/enrich/feedback" \
    -H "Content-Type: application/json" \
    -d @"$REPO_ROOT/data/payloads/feedback_enrich.json" \
    > "$STEP2_TMP"

echo "--- Formatted output ---"
cat "$STEP2_TMP" | python3 "$REPO_ROOT/scripts/fmt.py" --type feedback
echo ""
echo "--- Raw JSON ---"
cat "$STEP2_TMP" | python3 -m json.tool
echo ""
rm -f "$STEP2_TMP"

# Step 3: Verify decision in PostgreSQL
echo "=== [3/4] PostgreSQL llm_decisions ==="
docker exec northwind-postgres psql -U northwind -c \
    "SELECT request_id, endpoint, category, confidence, validation_status, decision FROM llm_decisions ORDER BY created_at DESC LIMIT 3"
echo ""

# Step 4: Verify trusted output table
echo "=== [4/4] DuckDB trusted output ==="
duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT count(*) as row_count FROM trusted.feedback_enriched"
echo ""
duckdb "$REPO_ROOT/data/northwind.duckdb" "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3"
echo ""

echo "=== Capture complete ==="
echo "Log saved to: $LOG_FILE"
