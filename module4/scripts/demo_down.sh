#!/usr/bin/env bash
set -euo pipefail

SESSION="m4-demo"

tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Module 4 demo session terminated"
