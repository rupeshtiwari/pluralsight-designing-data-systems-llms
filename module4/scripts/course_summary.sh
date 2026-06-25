#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Module 4 — Course summary slide (final on-camera moment, ~15 seconds)
#
# Closes the entire course with the four design contracts the learner now
# owns: LLM placement, boundary contracts, orchestration control, output
# validation. No data calls — just a clean terminal slide using the same
# Pluralsight brand palette as every demo step.
# ─────────────────────────────────────────────────────────────────────────────

PINK="\033[38;2;255;22;117m"
LIME="\033[38;2;207;255;110m"
LGRN="\033[38;2;64;255;191m"
BLUE="\033[38;2;42;236;250m"
GRAY="\033[38;2;191;191;191m"
WHITE="\033[1;37m"
NC="\033[0m"

bar="──────────────────────────────────────────────────────────────────────"

printf "\n"
printf "${WHITE}Course summary — the four design contracts you now own${NC}\n"
printf "${GRAY}%s${NC}\n\n" "$bar"

row() {
  local module="$1"; local phrase="$2"
  printf "  ${PINK}★${NC} ${BLUE}%-10s${NC} ${LGRN}%s${NC}\n\n" "$module:" "$phrase"
}

row "Module 1"  "LLM placement — where the model sits in the data flow"
row "Module 2"  "Boundary contracts — agent tools and approval gates"
row "Module 3"  "Orchestration control — trigger, monitor, branch on data"
row "Module 4"  "Output validation — reject bad output as a successful outcome"

printf "${GRAY}%s${NC}\n" "$bar"
printf "${GRAY}You can now design data systems where LLM outputs land in trusted tables only after every contract holds.${NC}\n\n"
