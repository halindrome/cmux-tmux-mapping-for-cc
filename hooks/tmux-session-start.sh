#!/usr/bin/env bash
# =============================================================================
# tmux-session-start.sh -- SessionStart hook for cmux-tmux-mapping plugin
#
# Detects the tmux/cmux environment on session start and exports CLAUDE_MUXER.
# Prints context message to stdout for Claude's session context.
# Always exits 0 -- SessionStart hooks must never block.
#
# Input (stdin): JSON with session_id, cwd, source, model, hook_event_name
# Output (stdout): Context message for Claude
# Side effect: Writes CLAUDE_MUXER to CLAUDE_ENV_FILE when available
# =============================================================================
set -euo pipefail

# Ensure we always exit 0 regardless of errors
trap 'exit 0' EXIT

# Read stdin (JSON input) -- store but don't parse
_INPUT=$(cat 2>/dev/null || true)

# Source mapper.sh for mux_env
source "${CLAUDE_PLUGIN_ROOT}/lib/mapper.sh"

# Detect multiplexer environment
env=$(mux_env)

# Write to CLAUDE_ENV_FILE if available
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo "export CLAUDE_MUXER=$env" >> "$CLAUDE_ENV_FILE"
fi

# Warn on stderr when no multiplexer is available
if [[ "$env" == "none" ]]; then
  echo "cmux-mapper: no tmux/cmux detected, panel operations will be unavailable" >&2
fi

# Detect agent vs human context
if [[ -n "${CLAUDE_AGENT_ID:-}" ]]; then
  # Agent mode -- concise, machine-oriented context
  if [[ "$env" == "none" ]]; then
    echo "cmux-tmux-mapping: env=none, agent=${CLAUDE_AGENT_ID}. WARNING: No multiplexer detected. Panel operations (mux_create_panel, mux_send, mux_destroy_panel) are unavailable."
  else
    echo "cmux-tmux-mapping: env=${env}, agent=${CLAUDE_AGENT_ID}. Use mux_create_panel, mux_send, mux_destroy_panel for panel operations."
  fi
else
  # Human mode -- descriptive context
  if [[ "$env" == "none" ]]; then
    echo "cmux-tmux-mapping plugin active. Multiplexer: none. WARNING: No tmux or cmux detected -- panel operations are unavailable."
  else
    echo "cmux-tmux-mapping plugin active. Multiplexer: ${env}. Panel API available via lib/mapper.sh."
  fi
fi

exit 0
