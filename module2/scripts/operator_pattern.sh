#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 2 — Operator pattern recap (final on-camera moment, ~10 seconds)
#
# Closes the clip with the six phrases that name the LangGraph operator
# pattern the demo just proved. No data calls — just a clean terminal
# slide so the audience leaves with the vocabulary.
#
# Uses the same brand palette and ★ label: value pattern that every demo
# step formatter uses, so it visually belongs to the same clip.
# ─────────────────────────────────────────────────────────────────────────────

PINK="\033[38;2;255;22;117m"      # ★ marker
LIME="\033[38;2;207;255;110m"     # heading
LGRN="\033[38;2;64;255;191m"      # value (pattern phrase)
BLUE="\033[38;2;42;236;250m"      # label (step)
GRAY="\033[38;2;191;191;191m"     # footer
WHITE="\033[1;37m"
NC="\033[0m"

bar="──────────────────────────────────────────────────────────────────────"

printf "\n"
printf "${WHITE}LangGraph operator pattern — what this clip proved${NC}\n"
printf "${GRAY}%s${NC}\n\n" "$bar"

row() {
  local step="$1"; local phrase="$2"
  printf "  ${PINK}★${NC} ${BLUE}%-8s${NC} ${LGRN}%s${NC}\n\n" "$step:" "$phrase"
}

row "Step 1"  "compiled topology"
row "Step 2"  "structured agent state"
row "Step 2b" "real execution path"
row "Step 3"  "durable tool receipts"
row "Step 4"  "decision ledger"
row "Step 5"  "conditional routing"

printf "\n${GRAY}%s${NC}\n" "$bar"
printf "${GRAY}Agents propose. Humans approve. Every step is auditable.${NC}\n\n"
