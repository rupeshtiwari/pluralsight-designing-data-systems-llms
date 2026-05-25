#!/usr/bin/env bash
# module3/scripts/capture_demo_output.sh — Capture golden output for Module 3 demo
# Resets state, seeds data, runs each of the 4 demo steps, and saves output
# to .run/module3/ for review before recording.
#
# Usage:
#   module3/scripts/capture_demo_output.sh

set -euo pipefail

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WAIT]${NC} %s\n" "$1"; }
fail() { printf "${RED}[ERR]${NC}  %s\n" "$1"; exit 1; }

OUTDIR="$PROJECT_DIR/.run/module3"
mkdir -p "$OUTDIR"

echo ""
echo "========================================"
echo " Module 3 — Capture Demo Output"
echo "========================================"
echo ""

# ── Verify services are running ──────────────────────────────────────────────
warn "Checking services..."

if ! curl -sf http://localhost:8000/health &>/dev/null; then
    fail "FastAPI is not running — start with module3/scripts/demo_up.sh first"
fi
ok "FastAPI is healthy"

if ! curl -sf http://localhost:8080/health &>/dev/null; then
    fail "Airflow is not running — start with module3/scripts/demo_up.sh first"
fi
ok "Airflow is healthy"

# ── Reset: clear pipeline metrics for a clean capture ────────────────────────
echo ""
warn "Resetting pipeline state for clean capture..."

# Reset by calling the metrics reset endpoint if available, otherwise proceed
curl -sf -X POST http://localhost:8000/pipeline/reset 2>/dev/null && ok "Pipeline state reset" || warn "No reset endpoint — proceeding with current state"

# ── Seed: batch-enrich the feedback payload ──────────────────────────────────
echo ""
warn "Seeding batch data via pipeline/batch-enrich..."

SEED_RESP=$(curl -sf -X POST http://localhost:8000/pipeline/batch-enrich \
    -H "Content-Type: application/json" \
    -d "{\"items\": $(cat data/payloads/batch_feedback.json)}")

BATCH_ID=$(echo "$SEED_RESP" | python3 -c "import sys,json; print(json.load(sys.stdin).get('batch_id','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
ok "Batch seeded: $BATCH_ID"

# Save seed response
echo "$SEED_RESP" | python3 -m json.tool > "$OUTDIR/seed_response.json" 2>/dev/null || echo "$SEED_RESP" > "$OUTDIR/seed_response.json"
ok "Seed response saved to .run/module3/seed_response.json"

# ── Step 1: Trigger the Airflow DAG ─────────────────────────────────────────
echo ""
echo "── Step 1: Trigger DAG ──"

STEP1_OUT=$(curl -s -X POST http://localhost:8000/pipeline/trigger \
    -H "Content-Type: application/json" \
    -d '{"batch_id": "BATCH-20240318-001", "source": "data/payloads/batch_feedback.json"}')

echo "$STEP1_OUT" | python3 scripts/fmt.py --type raw > "$OUTDIR/step1_trigger.txt" 2>/dev/null || echo "$STEP1_OUT" > "$OUTDIR/step1_trigger.txt"
ok "Step 1 output saved to .run/module3/step1_trigger.txt"

echo "$STEP1_OUT" | python3 scripts/fmt.py --type raw
echo ""

# ── Step 2: Show pipeline runs (DAG graph is visual — capture the run list) ──
echo ""
echo "── Step 2: Pipeline Runs ──"

STEP2_OUT=$(curl -s http://localhost:8000/pipeline/runs)

echo "$STEP2_OUT" | python3 scripts/fmt.py --type raw > "$OUTDIR/step2_runs.txt" 2>/dev/null || echo "$STEP2_OUT" > "$OUTDIR/step2_runs.txt"
ok "Step 2 output saved to .run/module3/step2_runs.txt"

echo "$STEP2_OUT" | python3 scripts/fmt.py --type raw
echo ""

# ── Step 3: Examine batch details for traceability ──────────────────────────
echo ""
echo "── Step 3: Batch Details ──"

STEP3_OUT=$(curl -s "http://localhost:8000/pipeline/run/$BATCH_ID")

echo "$STEP3_OUT" | python3 scripts/fmt.py --type batch > "$OUTDIR/step3_batch.txt" 2>/dev/null || echo "$STEP3_OUT" > "$OUTDIR/step3_batch.txt"
ok "Step 3 output saved to .run/module3/step3_batch.txt"

echo "$STEP3_OUT" | python3 scripts/fmt.py --type batch
echo ""

# ── Step 4: Verify DuckDB trusted and quarantine tables ─────────────────────
echo ""
echo "── Step 4: DuckDB Verification ──"

DUCKDB_PATH="$PROJECT_DIR/data/northwind.duckdb"

STEP4A_OUT=""
STEP4B_OUT=""

if command -v duckdb &>/dev/null && [[ -f "$DUCKDB_PATH" ]]; then
    STEP4A_OUT=$(duckdb "$DUCKDB_PATH" "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5" 2>&1 || echo "(query failed — table may not exist yet)")
    STEP4B_OUT=$(duckdb "$DUCKDB_PATH" "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5" 2>&1 || echo "(query failed — table may not exist yet)")
else
    STEP4A_OUT="(duckdb CLI not available or database file not found)"
    STEP4B_OUT="(duckdb CLI not available or database file not found)"
fi

echo "$STEP4A_OUT" > "$OUTDIR/step4_trusted.txt"
echo "$STEP4B_OUT" > "$OUTDIR/step4_quarantine.txt"
ok "Step 4 trusted output saved to .run/module3/step4_trusted.txt"
ok "Step 4 quarantine output saved to .run/module3/step4_quarantine.txt"

echo ""
echo "trusted.feedback_enriched:"
echo "$STEP4A_OUT"
echo ""
echo "quarantine.llm_outputs:"
echo "$STEP4B_OUT"
echo ""

# ── Summary ──────────────────────────────────────────────────────────────────
echo "========================================"
echo " Captured files:"
echo ""
ls -la "$OUTDIR"/
echo ""
ok "All 4 demo steps captured to .run/module3/"
echo "  Review output before recording."
echo "========================================"
