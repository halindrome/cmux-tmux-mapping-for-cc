#!/usr/bin/env bash
# agent-tmux-cleanup.sh — SubagentStop hook for panel teardown
#
# Destroys the isolated tmux/cmux panel when an agent finishes.
# Best-effort cleanup — always exits 0.
#
# Hook event: SubagentStop
# Input: JSON on stdin with agent metadata
set -euo pipefail

# Trap to ensure we always exit 0 even on unexpected errors
trap 'exit 0' ERR

# Read JSON input from stdin
INPUT=$(cat)

# Parse agent name (same pattern as panel creation hook)
AGENT_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('name','unknown'))" 2>/dev/null || echo "unknown")

# Source mapper API via plugin root
source "${CLAUDE_PLUGIN_ROOT}/lib/mapper.sh"

# Destroy panel — ignore errors (panel may already be gone)
mux_destroy_panel "$AGENT_NAME" 2>/dev/null || true

exit 0
