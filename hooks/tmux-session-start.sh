#!/usr/bin/env bash
# =============================================================================
# tmux-session-start.sh -- SessionStart hook for cmux-tmux-mapping plugin
#
# Detects the tmux/cmux environment on session start and exports CLAUDE_MUXER.
# When cmux is detected and $TMUX is not already set, fakes the tmux environment
# so that Claude Code enters tmux teammate mode and our shim intercepts calls.
# Prints context message to stdout for Claude's session context.
# Always exits 0 -- SessionStart hooks must never block.
#
# Input (stdin): JSON with session_id, cwd, source, model, hook_event_name
# Output (stdout): Context message for Claude
# Side effect: Writes CLAUDE_MUXER (and optionally TMUX shim vars) to CLAUDE_ENV_FILE
# =============================================================================
set -euo pipefail

# Ensure we always exit 0 regardless of errors
trap 'exit 0' EXIT

# Read stdin (JSON input)
_INPUT=$(cat 2>/dev/null || true)

# Parse session_id for persistent state files
_SESSION_ID=$(echo "$_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null || true)

# Source mapper.sh for mux_env
source "${CLAUDE_PLUGIN_ROOT}/lib/mapper.sh"

# Detect multiplexer environment
env=$(mux_env)

# Track whether we activated the shim
_SHIM_ACTIVE=0

# --- TMUX shim activation ---
# When cmux is available but $TMUX is not set (user is NOT in real tmux),
# fake the tmux environment so CC enters tmux teammate mode.
if [[ -z "${TMUX:-}" ]] && command -v cmux >/dev/null 2>&1; then
  # Generate fake TMUX value matching real format: socket_path,PID,counter
  _FAKE_UID="$(id -u)"
  _FAKE_TMUX="/tmp/tmux-${_FAKE_UID}/cmux-shim,$$,0"
  _FAKE_TMUX_PANE="%0"

  # Resolve plugin bin/ directory for PATH prepend
  _PLUGIN_BIN_DIR="${CLAUDE_PLUGIN_ROOT}/bin"

  # Session-scoped registry directory for pane-to-surface mappings
  _REGISTRY_DIR="/tmp/cmux-shim-registry-${_FAKE_UID}-$$"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    {
      echo "export TMUX=\"${_FAKE_TMUX}\""
      echo "export TMUX_PANE=\"${_FAKE_TMUX_PANE}\""
      echo "export CMUX_SHIM_ACTIVE=1"
      echo "export CMUX_REGISTRY_DIR=\"${_REGISTRY_DIR}\""
      echo "export PATH=\"${_PLUGIN_BIN_DIR}:\$PATH\""
    } >> "$CLAUDE_ENV_FILE"
    _SHIM_ACTIVE=1
  else
    echo "cmux-mapper: CLAUDE_ENV_FILE not set, cannot activate tmux shim" >&2
  fi
fi

# Write CLAUDE_MUXER to CLAUDE_ENV_FILE if available
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  echo "export CLAUDE_MUXER=$env" >> "$CLAUDE_ENV_FILE"
fi

# Capture and persist the parent surface ref for this session.
# This lets agent hooks know which surface belongs to CC itself so they
# never accidentally close it, and use it as the split anchor.
if [[ -n "$_SESSION_ID" ]] && command -v cmux >/dev/null 2>&1; then
  _PARENT_SURFACE=$(cmux identify --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('caller',{}).get('surface_ref',''))" \
    2>/dev/null || true)
  if [[ -n "$_PARENT_SURFACE" ]]; then
    echo "$_PARENT_SURFACE" > "/tmp/cmux-session-${_SESSION_ID}"
  fi
fi

# Warn on stderr when no multiplexer is available
if [[ "$env" == "none" && "$_SHIM_ACTIVE" -eq 0 ]]; then
  echo "cmux-mapper: no tmux/cmux detected, panel operations will be unavailable" >&2
fi

# Detect agent vs human context
if [[ -n "${CLAUDE_AGENT_ID:-}" ]]; then
  # Agent mode -- concise, machine-oriented context
  if [[ "$_SHIM_ACTIVE" -eq 1 ]]; then
    echo "cmux-tmux-mapping: env=cmux-shim, agent=${CLAUDE_AGENT_ID}. tmux shim active -- tmux calls routed through cmux."
  elif [[ "$env" == "none" ]]; then
    echo "cmux-tmux-mapping: env=none, agent=${CLAUDE_AGENT_ID}. WARNING: No multiplexer detected. Panel operations (mux_create_panel, mux_send, mux_destroy_panel) are unavailable."
  else
    echo "cmux-tmux-mapping: env=${env}, agent=${CLAUDE_AGENT_ID}. Use mux_create_panel, mux_send, mux_destroy_panel for panel operations."
  fi
else
  # Human mode -- descriptive context
  if [[ "$_SHIM_ACTIVE" -eq 1 ]]; then
    echo "cmux-tmux-mapping plugin active. Multiplexer: cmux (tmux-shim). tmux calls will be transparently routed through cmux."
  elif [[ "$env" == "none" ]]; then
    echo "cmux-tmux-mapping plugin active. Multiplexer: none. WARNING: No tmux or cmux detected -- panel operations are unavailable."
  else
    echo "cmux-tmux-mapping plugin active. Multiplexer: ${env}. Panel API available via lib/mapper.sh."
  fi
fi

exit 0
