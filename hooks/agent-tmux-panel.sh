#!/usr/bin/env bash
# agent-tmux-panel.sh — PreToolUse:Agent hook
#
# No-op: panel creation is handled by CC itself via the tmux shim.
# When CC spawns an agent it calls `tmux split-window` which our shim
# intercepts and translates to a cmux surface — no manual intervention needed.
# Always exits 0 and allows the spawn.
#
# Hook event: PreToolUse (matcher: Agent)

cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
EOF

exit 0
