#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 3 — DuckDB CLI proof moment (10–15 seconds on camera)
#
# The outline explicitly requires "DuckDB CLI shows trusted and quarantine
# tables". This script runs the exact two queries the reviewer expects against
# the live DuckDB file Airflow wrote to, so the recording has literal proof
# of both tables — not just the FastAPI /admin/disposition-summary view.
#
# Uses the `duckdb` CLI when installed; otherwise falls back to the python
# duckdb module so the recording has the same output either way.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_PATH="${DUCKDB_PATH:-$PROJECT_ROOT/data/northwind.duckdb}"

BOLD='\033[1m'
LIME='\033[38;2;163;230;53m'
PINK='\033[38;2;240;101;149m'
GRAY='\033[38;2;148;163;184m'
NC='\033[0m'

run_sql() {
  local sql="$1"
  if command -v duckdb >/dev/null 2>&1; then
    duckdb -readonly "$DB_PATH" -c "$sql"
  else
    python3 - "$DB_PATH" "$sql" <<'PY'
import sys, duckdb
db_path, sql = sys.argv[1], sys.argv[2]
con = duckdb.connect(db_path, read_only=True)
rows = con.execute(sql).fetchall()
cols = [d[0] for d in con.description]
widths = [max(len(c), *(len(str(r[i])) for r in rows)) if rows else len(c) for i, c in enumerate(cols)]
def line(parts): print("│ " + " │ ".join(str(p).ljust(widths[i]) for i, p in enumerate(parts)) + " │")
sep = "├" + "┼".join("─" * (w + 2) for w in widths) + "┤"
top = "┌" + "┬".join("─" * (w + 2) for w in widths) + "┐"
bot = "└" + "┴".join("─" * (w + 2) for w in widths) + "┘"
print(top); line(cols); print(sep)
for r in rows: line(r)
print(bot)
PY
  fi
}

printf "${BOLD}DuckDB CLI proof — Module 3 Clip 4${NC}\n"
printf "${GRAY}file: %s${NC}\n\n" "$DB_PATH"

printf "${BOLD}${LIME}trusted.feedback_enriched${NC}  (accepted rows the LLM produced and validation passed)\n"
echo   "──────────────────────────────────────────────────────────────────────────────"
run_sql "SELECT request_id, category, confidence, validation_status FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5;"
echo ""
run_sql "SELECT COUNT(*) AS trusted_row_count FROM trusted.feedback_enriched;"

echo ""
printf "${BOLD}${PINK}quarantine.llm_outputs${NC}     (rejected rows — branch sent them here, trusted table stayed clean)\n"
echo   "──────────────────────────────────────────────────────────────────────────────"
run_sql "SELECT request_id, validation_errors FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5;"
echo ""
run_sql "SELECT COUNT(*) AS quarantine_row_count FROM quarantine.llm_outputs;"

echo ""
printf "${GRAY}This is the same accepted vs quarantined split that ${NC}"
printf "${GRAY}/admin/disposition-summary surfaces in Step 5,${NC}\n"
printf "${GRAY}now read directly from the DuckDB warehouse — proving the branch decision landed rows in two distinct schemas.${NC}\n"
