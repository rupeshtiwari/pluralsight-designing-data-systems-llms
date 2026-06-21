#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 2 — Operator pattern recap (final on-camera moment, ~10 seconds)
#
# Closes the clip with the six phrases that name the LangGraph operator
# pattern the demo just proved. No data calls — just a clean terminal
# slide so the audience leaves with the vocabulary.
# ─────────────────────────────────────────────────────────────────────────────

BOLD='\033[1m'
PINK='\033[38;2;240;101;149m'
LIME='\033[38;2;163;230;53m'
LGRN='\033[38;2;132;204;22m'
BLUE='\033[38;2;56;189;248m'
GRAY='\033[38;2;148;163;184m'
WHITE='\033[38;2;255;255;255m'
NC='\033[0m'

bar="══════════════════════════════════════════════════════════════════════"

printf "\n"
printf "${PINK}╔%s╗${NC}\n" "$bar"
printf "${PINK}║${NC}   ${BOLD}${WHITE}LangGraph operator pattern — what this clip proved${NC}              ${PINK}║${NC}\n"
printf "${PINK}╚%s╝${NC}\n" "$bar"
printf "\n"

row() {
  local color="$1"; local label="$2"; local proof="$3"
  printf "   ${color}●${NC} ${BOLD}${color}%-26s${NC}  ${GRAY}%s${NC}\n" "$label" "$proof"
  printf "\n"
}

row "$LIME" "compiled topology"        "Step 1   /agent/graph — Mermaid from compiled.get_graph()"
row "$BLUE" "structured agent state"   "Step 2   /agent/triage returns full AgentState as JSON"
row "$LIME" "real execution path"      "Step 2b  /agent/state/{id} — node-by-node trace"
row "$LGRN" "durable tool receipts"    "Step 3   agent_tool_calls table in Postgres"
row "$PINK" "decision ledger"          "Step 4   agent_decisions table — review_required status"
row "$BLUE" "conditional routing"      "Step 5   high-severity → human gate, low-severity → auto-resolve"

printf "${PINK}%s${NC}\n" "──────────────────────────────────────────────────────────────────────"
printf "   ${BOLD}${WHITE}Agents propose. Humans approve. Every step is auditable.${NC}\n"
printf "${PINK}%s${NC}\n\n" "──────────────────────────────────────────────────────────────────────"
