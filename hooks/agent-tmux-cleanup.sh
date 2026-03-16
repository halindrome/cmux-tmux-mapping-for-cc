#!/usr/bin/env bash
# agent-tmux-cleanup.sh — SubagentStop hook
#
# No-op: panel cleanup is handled by CC itself via the tmux shim.
# When CC destroys an agent pane it calls `tmux kill-pane` which our shim
# intercepts and routes to cmux — no manual intervention needed.
#
# Hook event: SubagentStop

exit 0
