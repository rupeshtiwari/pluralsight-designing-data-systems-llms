#!/usr/bin/env bash
set -euo pipefail

SESSION="m1-demo"

tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Module 1 demo session terminated"
