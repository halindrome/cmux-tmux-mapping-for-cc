#!/usr/bin/env bash
# =============================================================================
# test-hooks.sh -- Integration tests for hook scripts
#
# Tests SessionStart, Agent Panel, and Cleanup hooks using CMUX_FORCE_ENV
# mocking (no real tmux/cmux required). Each hook is invoked as a subprocess.
# =============================================================================

# Helper: run a hook script with given env vars and stdin, capture exit code and stdout
_run_hook() {
  local hook="$1"
  local stdin_data="$2"
  shift 2
  # Remaining args are VAR=value pairs
  local env_vars=("CLAUDE_PLUGIN_ROOT=${PROJECT_ROOT}" "$@")
  local output rc=0
  output=$(echo "$stdin_data" | env "${env_vars[@]}" bash "${PROJECT_ROOT}/hooks/${hook}" 2>/dev/null) || rc=$?
  echo "$output"
  return $rc
}

# =============================================================================
# SessionStart hook tests
# =============================================================================

# -- test_session_start_tmux_env -----------------------------------------------
rc=0
output=$(_run_hook "tmux-session-start.sh" '{"hook_event_name":"SessionStart","source":"startup"}' "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_session_start_tmux_env (exit 0)"
assert_contains "$output" "tmux" "test_session_start_tmux_env (contains tmux)"

# -- test_session_start_cmux_env -----------------------------------------------
rc=0
output=$(_run_hook "tmux-session-start.sh" '{"hook_event_name":"SessionStart","source":"startup"}' "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_session_start_cmux_env (exit 0)"
assert_contains "$output" "cmux" "test_session_start_cmux_env (contains cmux)"

# -- test_session_start_none_env -----------------------------------------------
rc=0
output=$(_run_hook "tmux-session-start.sh" '{"hook_event_name":"SessionStart","source":"startup"}' "CMUX_FORCE_ENV=none") || rc=$?
assert_ok "$rc" "test_session_start_none_env (exit 0)"
assert_contains "$output" "none" "test_session_start_none_env (contains none)"

# -- test_session_start_agent_mode ---------------------------------------------
rc=0
output=$(_run_hook "tmux-session-start.sh" '{"hook_event_name":"SessionStart","source":"startup"}' "CMUX_FORCE_ENV=tmux" "CLAUDE_AGENT_ID=test-agent") || rc=$?
assert_ok "$rc" "test_session_start_agent_mode (exit 0)"
assert_contains "$output" "agent" "test_session_start_agent_mode (contains agent context)"

# -- test_session_start_env_file -----------------------------------------------
_tmpenvfile=$(mktemp /tmp/cmux-test-env-XXXXXX)
rc=0
output=$(_run_hook "tmux-session-start.sh" '{"hook_event_name":"SessionStart","source":"startup"}' "CMUX_FORCE_ENV=tmux" "CLAUDE_ENV_FILE=${_tmpenvfile}") || rc=$?
assert_ok "$rc" "test_session_start_env_file (exit 0)"
_envfile_contents=$(cat "$_tmpenvfile" 2>/dev/null || echo "")
assert_contains "$_envfile_contents" "CLAUDE_MUXER" "test_session_start_env_file (CLAUDE_MUXER written)"
rm -f "$_tmpenvfile"

# =============================================================================
# Agent panel hook tests
# =============================================================================

# -- test_agent_panel_allow ----------------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-panel.sh" '{"hook_event_name":"PreToolUse","tool_name":"Agent","tool_input":{"name":"dev-agent-1"}}' "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_agent_panel_allow (exit 0)"
assert_contains "$output" "allow" "test_agent_panel_allow (contains allow)"

# -- test_agent_panel_exit_zero_cmux -------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-panel.sh" '{"tool_input":{"name":"test-cmux"}}' "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_agent_panel_exit_zero_cmux"
assert_contains "$output" "allow" "test_agent_panel_exit_zero_cmux (allows)"

# -- test_agent_panel_no_env ---------------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-panel.sh" '{"tool_input":{"name":"test-none"}}' "CMUX_FORCE_ENV=none") || rc=$?
assert_ok "$rc" "test_agent_panel_no_env (exit 0)"
assert_contains "$output" "allow" "test_agent_panel_no_env (still allows)"

# -- test_agent_panel_parse_name -----------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-panel.sh" '{"tool_input":{"name":"my-special-agent"}}' "CMUX_FORCE_ENV=tmux") || rc=$?
assert_contains "$output" "my-special-agent" "test_agent_panel_parse_name"

# =============================================================================
# Cleanup hook tests
# =============================================================================

# -- test_cleanup_exit_zero ----------------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-cleanup.sh" '{"tool_input":{"name":"dev-agent-1"}}' "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_cleanup_exit_zero"

# -- test_cleanup_no_panel -----------------------------------------------------
# Agent that never had a panel -- should still exit 0
rc=0
output=$(_run_hook "agent-tmux-cleanup.sh" '{"tool_input":{"name":"nonexistent-agent"}}' "CMUX_FORCE_ENV=tmux") || rc=$?
assert_ok "$rc" "test_cleanup_no_panel (graceful)"

# -- test_cleanup_no_env -------------------------------------------------------
rc=0
output=$(_run_hook "agent-tmux-cleanup.sh" '{"tool_input":{"name":"test"}}' "CMUX_FORCE_ENV=none") || rc=$?
assert_ok "$rc" "test_cleanup_no_env (exit 0 even without muxer)"
