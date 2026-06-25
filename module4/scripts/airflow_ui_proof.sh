#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 4 — Airflow UI routing proof (Step 5, on-camera, ~15 seconds)
#
# Triggers a real Airflow DAG run (northwind_llm_enrichment), waits up to
# 90s for it to complete, then prints the three task states the outline
# requires on-screen:
#   - validation_branch  state
#   - write_trusted      state
#   - write_quarantine   state
#
# Same data Airflow's grid view shows. Also prints the literal Airflow UI
# URL so the recording can pivot to the browser if desired.
#
# If Airflow is unreachable (memory backend), prints a clear NOTE with
# instructions instead of failing the demo.
# ─────────────────────────────────────────────────────────────────────────────

API="${API:-http://localhost:8000}"
AIRFLOW_URL="${AIRFLOW_URL:-http://localhost:8080}"

PINK="\033[38;2;255;22;117m"
LIME="\033[38;2;207;255;110m"
LGRN="\033[38;2;64;255;191m"
BLUE="\033[38;2;42;236;250m"
GRAY="\033[38;2;191;191;191m"
WHITE="\033[1;37m"
NC="\033[0m"

hi() {
  printf "  ${PINK}★${NC} ${BLUE}%s:${NC} ${LGRN}%s${NC}\n\n" "$1" "$2"
}

printf "${WHITE}Airflow UI routing proof — task states the grid view shows${NC}\n"
printf "${GRAY}──────────────────────────────────────────────────────────────────────${NC}\n\n"

DAG_JSON=$(curl -sf "$API/admin/airflow-dag" 2>/dev/null || echo "")
BACKEND=$(echo "$DAG_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('backend','memory'))" 2>/dev/null || echo "memory")

if [[ "$BACKEND" != "airflow" ]]; then
  printf "  ${PINK}NOTE${NC} ${GRAY}Airflow webserver not reachable — backend reads as: %s${NC}\n\n" "$BACKEND"
  printf "  ${GRAY}For the recording, start Docker + Airflow before running this step:${NC}\n"
  printf "    ${GRAY}./scripts/module4-demo-reset.sh${NC}\n\n"
  printf "  ${GRAY}When live, the UI grid for ${LGRN}northwind_llm_enrichment${GRAY} shows three task states:${NC}\n"
  printf "    ${GRAY}- validation_branch  : success${NC}\n"
  printf "    ${GRAY}- write_trusted      : success or skipped${NC}\n"
  printf "    ${GRAY}- write_quarantine   : success or skipped${NC}\n\n"
  hi "airflow_ui_url" "$AIRFLOW_URL/dags/northwind_llm_enrichment/grid"
  exit 0
fi

# Trigger an Airflow DAG run with the proven mixed-batch payload
# (feedback_ids [1, 99] — one accepted, one rejected — so the
# @task.branch decorator returns BOTH write_trusted AND
# write_quarantine and both downstream tasks reach success.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRIG=$(curl -sf -X POST "$API/admin/airflow-trigger" \
  -H "Content-Type: application/json" \
  -d @"$PROJECT_ROOT/data/payloads/airflow_trigger.json" \
  2>/dev/null || echo "")
DAG_RUN_ID=$(echo "$TRIG" | python3 -c "import json,sys;print(json.load(sys.stdin).get('dag_run_id',''))" 2>/dev/null || echo "")

if [[ -z "$DAG_RUN_ID" ]]; then
  printf "  ${PINK}NOTE${NC} ${GRAY}Airflow trigger returned no dag_run_id — visit the UI directly:${NC}\n\n"
  hi "airflow_ui_url" "$AIRFLOW_URL/dags/northwind_llm_enrichment/grid"
  exit 0
fi

hi "dag_run_id" "$DAG_RUN_ID"

# Wait up to 90s for terminal state
WAITED=0
LATEST_STATE=""
while [[ $WAITED -lt 90 ]]; do
  RUN_JSON=$(curl -sf "$API/admin/airflow-dag-runs?limit=1" 2>/dev/null || echo "")
  LATEST_STATE=$(echo "$RUN_JSON" | python3 -c "import json,sys;d=json.load(sys.stdin).get('dag_runs',[]);print(d[0].get('state','') if d else '')" 2>/dev/null || echo "")
  if [[ "$LATEST_STATE" == "success" || "$LATEST_STATE" == "failed" ]]; then
    break
  fi
  sleep 3
  WAITED=$((WAITED + 3))
done

hi "validation_task_run_state" "${LATEST_STATE:-unknown}"

# Pull branch decision — same data the UI shows for the three downstream tasks
BRANCH=$(curl -sf "$API/admin/airflow-branch-decision?dag_run_id=$DAG_RUN_ID" 2>/dev/null || echo "")
BRANCH_STATE=$(echo "$BRANCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('upstream_task_state','unknown'))" 2>/dev/null || echo "unknown")
TRUSTED_STATE=$(echo "$BRANCH" | python3 -c "import json,sys;d=json.load(sys.stdin);s=d.get('downstream_states',{});print(s.get('write_trusted','unknown'))" 2>/dev/null || echo "unknown")
QUAR_STATE=$(echo "$BRANCH" | python3 -c "import json,sys;d=json.load(sys.stdin);s=d.get('downstream_states',{});print(s.get('write_quarantine','unknown'))" 2>/dev/null || echo "unknown")

hi "validation_branch state" "$BRANCH_STATE"
hi "write_trusted state"     "$TRUSTED_STATE"
hi "write_quarantine state"  "$QUAR_STATE"
hi "airflow_ui_url"          "$AIRFLOW_URL/dags/northwind_llm_enrichment/grid"

printf "${GRAY}──────────────────────────────────────────────────────────────────────${NC}\n"
printf "${GRAY}Same three task states the Airflow UI grid renders — proof routing is Airflow-controlled.${NC}\n\n"
