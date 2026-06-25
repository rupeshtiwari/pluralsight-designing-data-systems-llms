#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 4 — Batch input risk preview (Step 2a, on-camera, ~10 seconds)
#
# Reads the payload that Step 2 will POST and prints, per record, the
# input risk + the validation gate expected to catch it. This is the
# outline's "ambiguous feedback, stale reference context, invalid
# category values" proof — surfaced explicitly before the run, so the
# audience knows WHY each record is in the batch.
# ─────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PAYLOAD="${1:-$PROJECT_ROOT/data/payloads/module4_validation_batch.json}"

PINK="\033[38;2;255;22;117m"
LGRN="\033[38;2;64;255;191m"
BLUE="\033[38;2;42;236;250m"
GRAY="\033[38;2;191;191;191m"
WHITE="\033[1;37m"
NC="\033[0m"

if [ -x "$PROJECT_ROOT/.venv/bin/python" ]; then PY="$PROJECT_ROOT/.venv/bin/python"; else PY="python3"; fi

"$PY" - "$PAYLOAD" <<'PY'
import sys, json

PINK = "\033[38;2;255;22;117m"
LGRN = "\033[38;2;64;255;191m"
BLUE = "\033[38;2;42;236;250m"
GRAY = "\033[38;2;191;191;191m"
WHITE = "\033[1;37m"
NC = "\033[0m"

with open(sys.argv[1]) as f:
    items = json.load(f)

print(f"{WHITE}Batch input risk preview — why each record is in this batch{NC}")
print(f"{GRAY}──────────────────────────────────────────────────────────────────────{NC}")
print()
for it in items:
    intent = it.get("_intent") or {}
    fid = it.get("feedback_id", "?")
    risk = intent.get("input_risk", "?")
    gate = intent.get("expected_gate", "?")
    print(f"  {PINK}★{NC} {BLUE}feedback_id:{NC} {LGRN}{fid}{NC}")
    print(f"  {PINK}★{NC} {BLUE}input_risk:{NC}   {LGRN}{risk}{NC}")
    print(f"  {PINK}★{NC} {BLUE}expected_gate:{NC} {LGRN}{gate}{NC}")
    print()
PY
