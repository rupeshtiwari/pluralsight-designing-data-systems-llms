#!/usr/bin/env bash
set -u
# Module 4 — Clip 4 preflight: runs every demo step and verifies each one
# produces the output the README expects. Logs to module4/preflight_log.txt.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

LOG="module4/preflight_log.txt"
exec > >(tee "$LOG") 2>&1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[38;2;42;236;250m'
BOLD='\033[1m'
NC='\033[0m'
API="http://localhost:8000"

pass()   { printf "  ${GREEN}✓ PASS${NC}  %s\n" "$1"; }
warnit() { printf "  ${YELLOW}! WARN${NC}  %s\n" "$1"; }
failit() { printf "  ${RED}✗ FAIL${NC}  %s\n" "$1"; printf "         ${YELLOW}fix:${NC} %s\n" "$2"; ALL_PASS=0; }
section() {
  printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
  printf "  ${BOLD}%s${NC}\n" "$1"
  printf "  ${YELLOW}%s${NC}\n" "$2"
  printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

ALL_PASS=1

printf "\n"
printf "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}\n"
printf "${BLUE}║${NC}  ${BOLD}Module 4 Clip 4 — Preflight Check${NC}                          ${BLUE}║${NC}\n"
printf "${BLUE}║${NC}  ${BOLD}Rejecting hallucinated and schema-drifted LLM outputs${NC}      ${BLUE}║${NC}\n"
printf "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}\n"
printf "\n"

printf "  Checking server at $API...\n"
if ! curl -sf "$API/health" >/dev/null 2>&1; then
  failit "FastAPI not reachable on port 8000" "./scripts/module4-demo-reset.sh"
  echo "Aborting — server must be up."
  exit 1
fi
pass "Server is healthy"

# ── STEP 1 ──────────────────────────────────────────────────────────────────
section "STEP 1/6: Show the five validation checks" "LO 3d — schema, source_id, category, confidence, disposition"

printf "\n  Command:\n  \$ curl -s $API/validate/rules | python3 scripts/fmt.py --type validation-rules\n\n"
RULES_JSON=$(curl -sf "$API/validate/rules")
echo "$RULES_JSON" | python3 scripts/fmt.py --type validation-rules \
  --title "Validation rules enforced after generation" \
  --why "Schema, source_id, category, confidence, disposition" 2>&1 | sed 's/^/  /'

if [[ -z "$RULES_JSON" ]]; then
  failit "/validate/rules returned empty" "Check app/routers/validation.py is mounted"
else
  CT=$(echo "$RULES_JSON" | python3 -c "import json,sys;print(json.load(sys.stdin).get('confidence_threshold',''))")
  CATS=$(echo "$RULES_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('allowed_categories',[])))")
  if [[ -n "$CT" ]]; then pass "confidence_threshold present: $CT"; else failit "confidence_threshold missing" "Verify VALIDATION_RULES in app/validators/output_validator.py"; fi
  if [[ "$CATS" -ge 3 ]]; then pass "allowed_categories list populated: $CATS values"; else failit "allowed_categories too small" "Add categories in app/config.py ALLOWED_CATEGORIES"; fi
fi

# ── STEP 2 ──────────────────────────────────────────────────────────────────
section "STEP 2/6: Trigger bad-data batch via /pipeline/validate-batch" "LO 3c, 3d — one valid + four engineered failures"

printf "\n  Command:\n  \$ curl -s -X POST $API/pipeline/validate-batch -d @data/payloads/module4_validation_batch.json\n\n"
BATCH=$(curl -sf -X POST "$API/pipeline/validate-batch" \
  -H "Content-Type: application/json" \
  -d "{\"items\": $(cat data/payloads/module4_validation_batch.json)}")

if [[ -z "$BATCH" ]]; then
  failit "/pipeline/validate-batch returned empty" "Verify endpoint is registered in app/routers/pipeline.py and module4_validation_batch.json is valid JSON"
  BATCH_ID=""
else
  echo "$BATCH" | python3 scripts/fmt.py --type validate-batch \
    --title "Validation batch with bad LLM outputs" \
    --why "5 records: 1 valid, 4 engineered to fail one check each" 2>&1 | sed 's/^/  /'

  BATCH_ID=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('batch_id',''))")
  ACC=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('accepted_count',0))")
  REJ=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('rejected_count',0))")
  TOT=$(echo "$BATCH" | python3 -c "import json,sys;print(json.load(sys.stdin).get('total',0))")

  if [[ -n "$BATCH_ID" ]]; then pass "batch_id assigned: $BATCH_ID"; else failit "batch_id missing" "Endpoint must return batch_id at top level"; fi
  if [[ "$TOT" == "5" ]]; then pass "total = 5 (matches payload)"; else failit "total != 5 (got $TOT)" "Check module4_validation_batch.json has 5 items"; fi
  if [[ "$ACC" -ge 1 ]]; then pass "accepted_count >= 1 (got $ACC)"; else failit "accepted_count = 0" "Verify the first record in payload passes every check"; fi
  if [[ "$REJ" -ge 1 ]]; then pass "rejected_count >= 1 (got $REJ)"; else failit "rejected_count = 0" "Verify other records trigger engineered failures"; fi
fi

# ── STEP 3 ──────────────────────────────────────────────────────────────────
section "STEP 3/6: One valid output + at least one invalid reason" "LO 3d — reason text from the validator, not a generic 'rejected'"

if [[ -n "$BATCH" ]]; then
  REASONS=$(echo "$BATCH" | python3 -c "import json,sys;d=json.load(sys.stdin);[print(r.get('reason','')) for r in d.get('details',[]) if r.get('validation_status')=='rejected']")
  REASON_COUNT=$(echo "$REASONS" | grep -c '[a-zA-Z]' || true)
  if [[ "$REASON_COUNT" -ge 1 ]]; then
    pass "at least one rejected record carries a reason ($REASON_COUNT total)"
    FIRST_REASON=$(echo "$REASONS" | head -1)
    pass "first rejection reason: $FIRST_REASON"
  else
    failit "no rejection reasons returned" "Validator must populate result['errors'] for failed checks"
  fi

  VALID_COUNT=$(echo "$BATCH" | python3 -c "import json,sys;d=json.load(sys.stdin);print(sum(1 for r in d.get('details',[]) if r.get('validation_status')=='accepted'))")
  if [[ "$VALID_COUNT" -ge 1 ]]; then
    pass "at least one accepted record present (count=$VALID_COUNT) — proves gate is not over-rejecting"
  else
    failit "zero accepted records — gate may be rejecting everything" "Check the first payload record's enriched payload satisfies every rule"
  fi
fi

# ── STEP 4 ──────────────────────────────────────────────────────────────────
section "STEP 4/6: Airflow routing — accepted to trusted, rejected to quarantine" "LO 3c, 3d — proves disposition contract"

if [[ -n "$BATCH_ID" ]]; then
  printf "\n  Command:\n  \$ curl -s $API/pipeline/routing-detail/\$BATCH_ID | python3 scripts/fmt.py --type routing-detail\n\n"
  ROUTING=$(curl -sf "$API/pipeline/routing-detail/$BATCH_ID")
  if [[ -z "$ROUTING" ]]; then
    failit "/pipeline/routing-detail/$BATCH_ID returned empty" "Verify endpoint registered + batch_id was persisted in PG"
  else
    echo "$ROUTING" | python3 scripts/fmt.py --type routing-detail \
      --title "Airflow routing for $BATCH_ID" \
      --why "Accepted → trusted; rejected → quarantine" 2>&1 | sed 's/^/  /'

    TR=$(echo "$ROUTING" | python3 -c "import json,sys;print(json.load(sys.stdin).get('trusted_table',''))")
    QR=$(echo "$ROUTING" | python3 -c "import json,sys;print(json.load(sys.stdin).get('quarantine_table',''))")
    if [[ "$TR" == "trusted.feedback_enriched" ]]; then pass "trusted_table = trusted.feedback_enriched"; else failit "trusted_table mismatch (got '$TR')" "Endpoint must hardcode trusted.feedback_enriched"; fi
    if [[ "$QR" == "quarantine.llm_outputs" ]]; then pass "quarantine_table = quarantine.llm_outputs"; else failit "quarantine_table mismatch (got '$QR')" "Endpoint must hardcode quarantine.llm_outputs"; fi
  fi
fi

# ── STEP 5 ──────────────────────────────────────────────────────────────────
section "STEP 5/6: PostgreSQL pipeline_runs aggregate" "LO 3c — accepted_count, rejected_count, validation_summary"

printf "\n  Command:\n  \$ curl -s '$API/pipeline/runs?limit=3' | python3 scripts/fmt.py --type pipeline-runs\n\n"
RUNS=$(curl -sf "$API/pipeline/runs?limit=3")
echo "$RUNS" | python3 scripts/fmt.py --type pipeline-runs \
  --title "pipeline_runs aggregate (PostgreSQL)" \
  --why "One row per batch — accepted, rejected, validation_summary" 2>&1 | sed 's/^/  /' | tail -40

ROWS=$(echo "$RUNS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d) if isinstance(d,list) else len(d.get('runs',[])))")
if [[ "$ROWS" -ge 1 ]]; then
  pass "pipeline_runs returned $ROWS row(s)"
else
  failit "pipeline_runs returned no rows" "Verify Step 2 persisted via postgres.insert_pipeline_run"
fi

HAS_SUMMARY=$(echo "$RUNS" | python3 -c "import json,sys;d=json.load(sys.stdin);rows=d if isinstance(d,list) else d.get('runs',[]);print('yes' if any(r.get('validation_summary') for r in rows) else 'no')")
if [[ "$HAS_SUMMARY" == "yes" ]]; then
  pass "at least one row carries validation_summary"
else
  warnit "no row has validation_summary — Step 5 narration about per-failure alerting will look thin"
fi

# ── STEP 6 ──────────────────────────────────────────────────────────────────
section "STEP 6/6: DuckDB CLI — trusted + quarantine schemas" "LO 1d, 3d — literal table names + reason preserved"

printf "\n  Command:\n  \$ module4/scripts/duckdb_proof.sh\n\n"
DBOUT=$(module4/scripts/duckdb_proof.sh 2>&1 || true)
echo "$DBOUT" | sed 's/^/  /' | head -40

if echo "$DBOUT" | grep -q "trusted.feedback_enriched"; then pass "trusted.feedback_enriched rendered literally"; else failit "trusted.feedback_enriched missing from duckdb_proof output" "Verify module4/scripts/duckdb_proof.sh"; fi
if echo "$DBOUT" | grep -q "quarantine.llm_outputs"; then pass "quarantine.llm_outputs rendered literally"; else failit "quarantine.llm_outputs missing from duckdb_proof output" "Verify module4/scripts/duckdb_proof.sh"; fi
if echo "$DBOUT" | grep -q "validation_errors"; then pass "validation_errors field shown (reason preserved)"; else failit "validation_errors not shown" "duckdb_proof must select validation_errors column"; fi

# ── LO coverage ─────────────────────────────────────────────────────────────
printf "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
printf "  ${BOLD}LO COVERAGE${NC}\n"
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"
printf "  1d  Steps 2, 6  Data flow design — LLM output → validation → trusted vs quarantine\n"
printf "  3c  Steps 2, 5  Trigger + monitor: validate-batch + pipeline_runs aggregate\n"
printf "  3d  Steps 1, 3, 4, 6  Guardrails: rules, reasons, routing, persisted disposition\n\n"

# ── Final verdict ───────────────────────────────────────────────────────────
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
if [[ $ALL_PASS -eq 1 ]]; then
  printf "  ${GREEN}${BOLD}✓ ALL CHECKS PASSED — Module 4 Clip 4 demo is ready${NC}\n"
else
  printf "  ${RED}${BOLD}✗ ONE OR MORE CHECKS FAILED — fix above before recording${NC}\n"
fi
printf "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n\n"

printf "  Log saved to: $LOG\n\n"
