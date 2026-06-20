#!/usr/bin/env bash
# module3/scripts/capture_demo_output.sh — Capture golden output for Module 3 demo
# Runs each of the 6 demo steps and saves output to module3/captures/ for
# review before recording.
#
# Usage:
#   module3/scripts/capture_demo_output.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT_DIR="$REPO_ROOT/module3/captures"
mkdir -p "$OUT_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { printf "${GREEN}[OK]${NC}   %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail() { printf "${RED}[ERR]${NC}  %s\n" "$1"; }

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ERRORS=0

API="http://localhost:8000"
FMT="$REPO_ROOT/scripts/fmt.py"

echo "========================================"
echo " Module 3 — Capture Demo Output"
echo " $TIMESTAMP"
echo "========================================"
echo ""

if ! curl -sf "$API/health" >/dev/null 2>&1; then
  fail "FastAPI is not running — start with module3/scripts/demo_up.sh first"
  exit 1
fi
ok "FastAPI is healthy"

# ── Step 1: DAG topology ────────────────────────────────────────────────────
echo ""
echo "Step 1: DAG topology..."
S1="$OUT_DIR/step1_airflow_dag_${TIMESTAMP}.json"
if curl -sf "$API/admin/airflow-dag" -o "$S1"; then
  ok "Step 1 captured -> $(basename "$S1")"
  python3 "$FMT" --type airflow-dag < "$S1"
else
  fail "Step 1 failed — /admin/airflow-dag not reachable"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Trigger DAG ─────────────────────────────────────────────────────
echo ""
echo "Step 2: Trigger DAG..."
S2="$OUT_DIR/step2_airflow_trigger_${TIMESTAMP}.json"
if curl -sf -X POST "$API/admin/airflow-trigger" \
     -H "Content-Type: application/json" \
     -d @"$REPO_ROOT/data/payloads/airflow_trigger.json" -o "$S2"; then
  ok "Step 2 captured -> $(basename "$S2")"
  python3 "$FMT" --type airflow-trigger < "$S2"
else
  fail "Step 2 failed — /admin/airflow-trigger not reachable"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 3: State transitions ───────────────────────────────────────────────
echo ""
echo "Step 3: State transitions..."
S3="$OUT_DIR/step3_airflow_dag_runs_${TIMESTAMP}.json"
if curl -sf "$API/admin/airflow-dag-runs?limit=3" -o "$S3"; then
  ok "Step 3 captured -> $(basename "$S3")"
  python3 "$FMT" --type airflow-dag-runs < "$S3"
else
  fail "Step 3 failed — /admin/airflow-dag-runs not reachable"
  ERRORS=$((ERRORS + 1))
fi

# Pull a real run id for steps 4 and 6
RUN_ID=$(python3 -c "
import json, sys
try:
    d = json.load(open('$S3'))
    print(d.get('dag_runs', [{}])[0].get('dag_run_id',''))
except Exception:
    print('')")

# ── Step 4: Task log fields ─────────────────────────────────────────────────
echo ""
echo "Step 4: Task log fields..."
S4="$OUT_DIR/step4_airflow_task_log_${TIMESTAMP}.json"
if curl -sf "$API/admin/airflow-task-log?dag_run_id=${RUN_ID}&task_id=enrich_via_fastapi" -o "$S4"; then
  ok "Step 4 captured -> $(basename "$S4")"
  python3 "$FMT" --type airflow-task-log < "$S4"
else
  fail "Step 4 failed — /admin/airflow-task-log not reachable"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 5: Disposition summary ─────────────────────────────────────────────
echo ""
echo "Step 5: Disposition summary..."
S5="$OUT_DIR/step5_dispositions_${TIMESTAMP}.json"
if curl -sf "$API/admin/disposition-summary?limit=5" -o "$S5"; then
  ok "Step 5 captured -> $(basename "$S5")"
  python3 "$FMT" --type dispositions < "$S5"
else
  fail "Step 5 failed — /admin/disposition-summary not reachable"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 6: Branch decision ─────────────────────────────────────────────────
echo ""
echo "Step 6: Branch decision..."
S6="$OUT_DIR/step6_airflow_branch_${TIMESTAMP}.json"
if curl -sf "$API/admin/airflow-branch-decision?dag_run_id=${RUN_ID}" -o "$S6"; then
  ok "Step 6 captured -> $(basename "$S6")"
  python3 "$FMT" --type airflow-branch < "$S6"
else
  fail "Step 6 failed — /admin/airflow-branch-decision not reachable"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
if [ "$ERRORS" -eq 0 ]; then
  printf "${GREEN}All 6 steps captured successfully${NC}\n"
else
  printf "${RED}$ERRORS step(s) failed — review output above${NC}\n"
fi
echo "Captures saved to: $OUT_DIR"
echo "========================================"
exit "$ERRORS"
