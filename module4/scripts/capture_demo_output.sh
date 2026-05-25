#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CAPTURE_DIR="$REPO_ROOT/module4/captures"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTFILE="$CAPTURE_DIR/demo_capture_${TIMESTAMP}.txt"

mkdir -p "$CAPTURE_DIR"

# ── Colors ────────────────────────────────────────────────────────────────────
BOLD='\033[1m'
CYAN='\033[0;36m'
NC='\033[0m'

divider() {
  echo ""
  echo "================================================================"
  printf "${BOLD}${CYAN}%s${NC}\n" "$1"
  echo "================================================================"
  echo ""
}

{
  divider "MODULE 4 DEMO CAPTURE — $(date)"

  # ── Step 1: Run the validation batch ────────────────────────────────────────
  divider "STEP 1: Run validation batch and show Airflow routing"
  echo '$ curl -s -X POST http://localhost:8000/pipeline/batch-enrich -H "Content-Type: application/json" -d @data/payloads/batch_validation_test.json | python3 scripts/fmt.py --type batch'
  echo ""
  cd "$REPO_ROOT"
  curl -s -X POST http://localhost:8000/pipeline/batch-enrich \
    -H "Content-Type: application/json" \
    -d @data/payloads/batch_validation_test.json | python3 scripts/fmt.py --type batch 2>&1 || echo "[ERROR] Step 1 failed"
  echo ""

  # ── Step 2: Examine individual validation failures ─────────────────────────
  divider "STEP 2: Examine individual validation failures"
  echo '$ curl -s -X POST http://localhost:8000/validate/output -H "Content-Type: application/json" -d '"'"'{"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}'"'"' | python3 scripts/fmt.py --type validation'
  echo ""
  curl -s -X POST http://localhost:8000/validate/output \
    -H "Content-Type: application/json" \
    -d '{"category": "electronics_repair", "summary": "Customer needs repair", "confidence": 0.92, "source_doc_ids": ["DOC-001"]}' | python3 scripts/fmt.py --type validation 2>&1 || echo "[ERROR] Step 2 failed"
  echo ""

  # ── Step 3: Verify pipeline run summary in PostgreSQL ──────────────────────
  divider "STEP 3: Verify pipeline run summary in PostgreSQL"
  echo '$ docker exec northwind-postgres psql -U northwind -c "SELECT batch_id, accepted_count, rejected_count, validation_summary FROM pipeline_runs ORDER BY created_at DESC LIMIT 3"'
  echo ""
  docker exec northwind-postgres psql -U northwind -c \
    "SELECT batch_id, accepted_count, rejected_count, validation_summary FROM pipeline_runs ORDER BY created_at DESC LIMIT 3" 2>&1 || echo "[ERROR] Step 3 failed"
  echo ""

  # ── Step 4: Verify trusted output and quarantine in DuckDB ─────────────────
  divider "STEP 4a: Trusted output in DuckDB"
  echo '$ duckdb data/northwind.duckdb "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5"'
  echo ""
  duckdb "$REPO_ROOT/data/northwind.duckdb" \
    "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5" 2>&1 || echo "[ERROR] Step 4a failed"
  echo ""

  divider "STEP 4b: Quarantine in DuckDB"
  echo '$ duckdb data/northwind.duckdb "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5"'
  echo ""
  duckdb "$REPO_ROOT/data/northwind.duckdb" \
    "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5" 2>&1 || echo "[ERROR] Step 4b failed"
  echo ""

  divider "CAPTURE COMPLETE"

} 2>&1 | tee "$OUTFILE"

echo ""
echo "Captured to: $OUTFILE"
