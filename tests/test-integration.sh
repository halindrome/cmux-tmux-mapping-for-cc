#!/usr/bin/env bash
# =============================================================================
# test-integration.sh -- End-to-end integration tests for agent panel lifecycle
#
# Tests the full hook lifecycle: SessionStart -> PreToolUse:Agent -> SubagentStop
# All tests use CMUX_FORCE_ENV mocking (no real tmux/cmux required).
# =============================================================================

# Helper: run a hook script with given env vars and stdin, capture stdout+stderr
_run_hook_full() {
  local hook="$1"
  local stdin_data="$2"
  shift 2
  local env_vars=("CLAUDE_PLUGIN_ROOT=${PROJECT_ROOT}" "$@")
  local combined rc=0
  combined=$(echo "$stdin_data" | env "${env_vars[@]}" bash "${PROJECT_ROOT}/hooks/${hook}" 2>&1) || rc=$?
  echo "$combined"
  return $rc
}

# Helper: run a hook script, capture only stdout (suppress stderr)
_run_hook_stdout() {
  local hook="$1"
  local stdin_data="$2"
  shift 2
  local env_vars=("CLAUDE_PLUGIN_ROOT=${PROJECT_ROOT}" "$@")
  local output rc=0
  output=$(echo "$stdin_data" | env "${env_vars[@]}" bash "${PROJECT_ROOT}/hooks/${hook}" 2>/dev/null) || rc=$?
  echo "$output"
  return $rc
}

# =============================================================================
# Integration: Full agent lifecycle
# =============================================================================

# -- test_full_agent_lifecycle ------------------------------------------------
# SessionStart -> agent panel create -> agent cleanup
# Each hook runs in its own subprocess, so we verify each step individually.
rc=0
start_output=$(_run_hook_stdout "tmux-session-start.sh" \
  '{"hook_event_name":"SessionStart","source":"startup"}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_full_agent_lifecycle: SessionStart exits 0"
assert_contains "$start_output" "cmux" "test_full_agent_lifecycle: SessionStart detects cmux"

rc=0
panel_output=$(_run_hook_stdout "agent-tmux-panel.sh" \
  '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"name":"lifecycle-agent"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_full_agent_lifecycle: panel creation exits 0"
assert_contains "$panel_output" "allow" "test_full_agent_lifecycle: panel hook allows"

rc=0
cleanup_output=$(_run_hook_full "agent-tmux-cleanup.sh" \
  '{"tool_input":{"name":"lifecycle-agent"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_full_agent_lifecycle: cleanup exits 0"

# -- test_session_start_exports_env -------------------------------------------
_tmpenvfile=$(mktemp /tmp/cmux-test-integ-env-XXXXXX)
rc=0
output=$(_run_hook_stdout "tmux-session-start.sh" \
  '{"hook_event_name":"SessionStart"}' \
  "CMUX_FORCE_ENV=cmux" "CLAUDE_ENV_FILE=${_tmpenvfile}") || rc=$?
assert_ok "$rc" "test_session_start_exports_env (exit 0)"
_env_contents=$(cat "$_tmpenvfile" 2>/dev/null || echo "")
assert_contains "$_env_contents" "CLAUDE_MUXER=cmux" "test_session_start_exports_env (CLAUDE_MUXER=cmux written)"
rm -f "$_tmpenvfile"

# -- test_agent_panel_uses_agent_name -----------------------------------------
rc=0
output=$(_run_hook_stdout "agent-tmux-panel.sh" \
  '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"name":"named-agent-42"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_contains "$output" "named-agent-42" "test_agent_panel_uses_agent_name"

# -- test_cleanup_hook_with_valid_agent ---------------------------------------
rc=0
output=$(_run_hook_full "agent-tmux-cleanup.sh" \
  '{"tool_input":{"name":"cleanup-target"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_cleanup_hook_with_valid_agent (exit 0)"

# -- test_multiple_agents_different_panels ------------------------------------
rc=0
out1=$(_run_hook_stdout "agent-tmux-panel.sh" \
  '{"tool_input":{"name":"agent-alpha"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_multiple_agents: agent-alpha exits 0"

rc=0
out2=$(_run_hook_stdout "agent-tmux-panel.sh" \
  '{"tool_input":{"name":"agent-beta"}}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_multiple_agents: agent-beta exits 0"

# Both should be allowed and mention their respective agent names
assert_contains "$out1" "agent-alpha" "test_multiple_agents: alpha named"
assert_contains "$out2" "agent-beta" "test_multiple_agents: beta named"

# -- test_lifecycle_tmux_backend ----------------------------------------------
# Same lifecycle test but with tmux backend
rc=0
start_output=$(_run_hook_stdout "tmux-session-start.sh" \
  '{"hook_event_name":"SessionStart"}' \
  "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_lifecycle_tmux: SessionStart exits 0"
assert_contains "$start_output" "tmux" "test_lifecycle_tmux: detects tmux"

rc=0
panel_output=$(_run_hook_stdout "agent-tmux-panel.sh" \
  '{"tool_input":{"name":"tmux-agent"}}' \
  "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_lifecycle_tmux: panel exits 0"
assert_contains "$panel_output" "allow" "test_lifecycle_tmux: allows"
