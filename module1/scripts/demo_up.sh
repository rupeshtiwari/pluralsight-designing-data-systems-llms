#!/usr/bin/env bash
set -euo pipefail

SESSION="m1-demo"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Kill existing session if present
tmux kill-session -t "$SESSION" 2>/dev/null || true

# Create session with first pane (server logs)
tmux new-session -d -s "$SESSION" -x 200 -y 50

# Configure tmux appearance
tmux set-option -t "$SESSION" status off
tmux set-option -t "$SESSION" pane-border-indicators off
tmux set-option -t "$SESSION" mouse on
tmux set-option -t "$SESSION" pane-border-style "fg=#130F25"
tmux set-option -t "$SESSION" pane-active-border-style "fg=#2AECFA"

# Split into two panes: top (server), bottom (demo)
tmux split-window -t "$SESSION" -v

# Configure top pane (server logs)
tmux select-pane -t "$SESSION:0.0"
tmux send-keys -t "$SESSION:0.0" "cd $REPO_ROOT && source .venv/bin/activate && VIRTUAL_ENV_DISABLE_PROMPT=1 uvicorn app.main:app --host 0.0.0.0 --port 8000 --log-level info" C-m

# Set pane titles
tmux select-pane -t "$SESSION:0.0" -T "SERVER LOGS"
tmux select-pane -t "$SESSION:0.1" -T "DEMO COMMANDS"
tmux set-option -t "$SESSION" pane-border-format "#{?pane_active,#[bg=#2AECFA#,fg=#130F25#,bold] #{pane_title} ,#[bg=#FF1675#,fg=#FFFFFF#,bold] #{pane_title} }"
tmux set-option -t "$SESSION" pane-border-status top

# Configure bottom pane (demo commands)
tmux select-pane -t "$SESSION:0.1"
tmux send-keys -t "$SESSION:0.1" "cd $REPO_ROOT && source .venv/bin/activate && VIRTUAL_ENV_DISABLE_PROMPT=1 PS1='$ ' exec bash --norc --noprofile" C-m
tmux send-keys -t "$SESSION:0.1" "PS1='$ '" C-m

# Wait for server to be healthy
echo "Waiting for server to start..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "Server is healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "ERROR: Server failed to start within 30 seconds"
    exit 1
  fi
  sleep 1
done

# Seed knowledge base and reset metrics
curl -sf -X POST http://localhost:8000/admin/seed-knowledge-base > /dev/null
curl -sf -X POST http://localhost:8000/admin/reset-metrics > /dev/null

echo "Module 1 demo environment ready"
echo "Attach with: tmux attach -t $SESSION"
