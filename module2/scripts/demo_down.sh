#!/usr/bin/env bash
set -euo pipefail

SESSION="m2-demo"

tmux kill-session -t "$SESSION" 2>/dev/null || true
echo "Module 2 demo session terminated"
