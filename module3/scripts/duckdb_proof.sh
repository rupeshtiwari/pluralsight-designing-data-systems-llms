#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 3 — DuckDB CLI proof moment (one screen, ~10 seconds on camera)
#
# Reads the live northwind.duckdb file (via a read-only snapshot so FastAPI's
# writer keeps its lock) and prints, in one screen:
#   - trusted.feedback_enriched   (sample row + total count)
#   - quarantine.llm_outputs      (sample row + total count)
#
# Same brand palette as Step 5 so the recap looks native to the clip.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_DB="${DUCKDB_PATH:-$PROJECT_ROOT/data/northwind.duckdb}"

SNAPSHOT_DIR="$(mktemp -d -t duckdb_proof_XXXXXX)"
DB_PATH="$SNAPSHOT_DIR/northwind.duckdb"
cp "$SOURCE_DB" "$DB_PATH"
[ -f "${SOURCE_DB}.wal" ] && cp "${SOURCE_DB}.wal" "${DB_PATH}.wal"
trap 'rm -rf "$SNAPSHOT_DIR"' EXIT

# Prefer the project venv python so the duckdb module installed by
# requirements.txt is available. System python3 on macOS often does not
# have duckdb and the script would crash with ModuleNotFoundError.
if [ -x "$PROJECT_ROOT/.venv/bin/python" ]; then
  PY="$PROJECT_ROOT/.venv/bin/python"
else
  PY="python3"
fi

"$PY" - "$DB_PATH" <<'PY'
import sys, duckdb, shutil, textwrap

PINK = "\033[38;2;255;22;117m"
LIME = "\033[38;2;207;255;110m"
LGRN = "\033[38;2;64;255;191m"
BLUE = "\033[38;2;42;236;250m"
GRAY = "\033[38;2;191;191;191m"
WHITE = "\033[1;37m"
NC = "\033[0m"

TERM_W = shutil.get_terminal_size((110, 24)).columns
con = duckdb.connect(sys.argv[1], read_only=True)

def hi(col, val):
    sval = str(val)
    prefix_plain = f"  ★ {col}: "
    prefix_color = f"  {PINK}★{NC} {BLUE}{col}:{NC} "
    indent = " " * len(prefix_plain)
    width = max(40, TERM_W - len(prefix_plain))
    wrapped = textwrap.wrap(sval, width=width, break_long_words=False,
                            break_on_hyphens=False) or [""]
    print(f"{prefix_color}{LGRN}{wrapped[0]}{NC}")
    for line in wrapped[1:]:
        print(f"{indent}{LGRN}{line}{NC}")
    print()

def section(table, header_color, caption, cols):
    rows = con.execute(
        f"SELECT {', '.join(cols)} FROM {table} ORDER BY 1 DESC LIMIT 1"
    ).fetchall()
    count = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]

    print()
    print(f"  {header_color}{table}{NC}  {GRAY}{caption}{NC}")
    print()
    if rows:
        for col, val in zip(cols, rows[0]):
            hi(col, val)
    hi("row count", count)

print(f"{WHITE}DuckDB CLI proof — trusted + quarantine schemas{NC}")

section(
    "trusted.feedback_enriched",
    LIME,
    "accepted rows the LLM produced and validation passed",
    ["request_id", "category", "confidence", "validation_status"],
)
section(
    "quarantine.llm_outputs",
    PINK,
    "rejected rows the branch routed here",
    ["request_id", "validation_errors"],
)

print()
print(f"  {GRAY}Same accepted vs quarantined split as /admin/disposition-summary in Step 5,{NC}")
print(f"  {GRAY}now read directly from two distinct DuckDB schemas.{NC}")
print()
PY
