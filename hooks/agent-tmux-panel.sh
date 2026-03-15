#!/usr/bin/env bash
# agent-tmux-panel.sh — PreToolUse:Agent hook for auto-creating agent panels
#
# Creates an isolated tmux/cmux panel when Claude Code spawns an agent.
# Always exits 0 — panel creation failure must never block agent spawn.
#
# Hook event: PreToolUse (matcher: Agent)
# Input: JSON on stdin with tool_input.name
# Output: JSON with permissionDecision "allow"
set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Parse agent name from tool_input (following agent-cmm-gate.sh pattern)
AGENT_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('name','unknown'))" 2>/dev/null || echo "unknown")

if [[ "$AGENT_NAME" == "unknown" ]]; then
  echo "cmux-mapper: could not parse agent name from hook input, using 'unknown'" >&2
fi

# Source mapper API via plugin root
source "${CLAUDE_PLUGIN_ROOT}/lib/mapper.sh"

# Detect multiplexer environment
env=$(mux_env)

if [[ "$env" != "none" ]]; then
  # Create panel — capture output, ignore errors
  panel_handle=$(mux_create_panel "$AGENT_NAME" "v" 2>/dev/null) || true
  if [[ -n "$panel_handle" ]]; then
    echo "Panel created for agent '$AGENT_NAME': $panel_handle" >&2
  else
    echo "Warning: panel creation failed for agent '$AGENT_NAME' (continuing)" >&2
  fi
else
  echo "No multiplexer detected — skipping panel creation for agent '$AGENT_NAME'" >&2
fi

# Always allow agent spawn
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"Panel created for agent: $AGENT_NAME"}}
EOF

exit 0
