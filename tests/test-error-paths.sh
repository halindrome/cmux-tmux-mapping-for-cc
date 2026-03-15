#!/usr/bin/env bash
# =============================================================================
# test-error-paths.sh -- Error path and edge case tests
#
# Tests error handling behavior: missing multiplexer, malformed JSON input,
# hooks always exiting 0, and mapper error paths.
# =============================================================================

source "${PROJECT_ROOT}/lib/mapper.sh"

# Helper: run a hook capturing both stdout and stderr
_run_hook_all() {
  local hook="$1"
  local stdin_data="$2"
  shift 2
  local env_vars=("CLAUDE_PLUGIN_ROOT=${PROJECT_ROOT}" "$@")
  local combined rc=0
  combined=$(echo "$stdin_data" | env "${env_vars[@]}" bash "${PROJECT_ROOT}/hooks/${hook}" 2>&1) || rc=$?
  echo "$combined"
  return $rc
}

# Helper: run a hook capturing only stderr
_run_hook_stderr() {
  local hook="$1"
  local stdin_data="$2"
  shift 2
  local env_vars=("CLAUDE_PLUGIN_ROOT=${PROJECT_ROOT}" "$@")
  local stderr_out rc=0
  stderr_out=$(echo "$stdin_data" | env "${env_vars[@]}" bash "${PROJECT_ROOT}/hooks/${hook}" 2>&1 1>/dev/null) || rc=$?
  echo "$stderr_out"
  return $rc
}

# =============================================================================
# Missing multiplexer tests
# =============================================================================

# -- test_missing_mux_mux_command_fails ---------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=none
rc=0
err=$(mux_command "split-window" 2>&1 >/dev/null) || rc=$?
assert_fail "$rc" "test_missing_mux_mux_command_fails (returns non-zero)"
assert_contains "$err" "no multiplexer" "test_missing_mux_mux_command_fails (error message)"

# -- test_missing_mux_create_panel_fails --------------------------------------
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=none
rc=0
err=$(mux_create_panel "test-agent" 2>&1 >/dev/null) || rc=$?
assert_fail "$rc" "test_missing_mux_create_panel_fails (returns non-zero)"
assert_contains "$err" "no multiplexer" "test_missing_mux_create_panel_fails (error message)"

# -- test_mux_send_no_panel ---------------------------------------------------
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=cmux
rc=0
err=$(mux_send "nonexistent" "hello" 2>&1 >/dev/null) || rc=$?
assert_fail "$rc" "test_mux_send_no_panel (returns non-zero)"
assert_contains "$err" "no panel found" "test_mux_send_no_panel (error message)"

# -- test_mux_send_missing_agent_id -------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
rc=0
mux_send "" "hello" >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_mux_send_missing_agent_id"

# -- test_mux_command_no_subcommand -------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
rc=0
mux_command >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_mux_command_no_subcommand"

# =============================================================================
# Hook malformed input tests
# =============================================================================

# -- test_hook_malformed_json -------------------------------------------------
rc=0
output=$(_run_hook_all "agent-tmux-panel.sh" \
  "not valid json at all" \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_hook_malformed_json (exits 0)"
assert_contains "$output" "unknown" "test_hook_malformed_json (defaults to unknown)"

# -- test_hook_empty_json -----------------------------------------------------
rc=0
output=$(_run_hook_all "agent-tmux-panel.sh" \
  "{}" \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_hook_empty_json (exits 0)"
assert_contains "$output" "unknown" "test_hook_empty_json (defaults to unknown)"

# -- test_hook_missing_tool_input ---------------------------------------------
rc=0
output=$(_run_hook_all "agent-tmux-panel.sh" \
  '{"event":"test","other_field":"value"}' \
  "CMUX_FORCE_ENV=cmux") || rc=$?
assert_ok "$rc" "test_hook_missing_tool_input (exits 0)"
assert_contains "$output" "unknown" "test_hook_missing_tool_input (defaults to unknown)"

# -- test_session_start_no_mux ------------------------------------------------
rc=0
output=$(_run_hook_all "tmux-session-start.sh" \
  '{"hook_event_name":"SessionStart"}' \
  "CMUX_FORCE_ENV=none") || rc=$?
assert_ok "$rc" "test_session_start_no_mux (exits 0)"
assert_contains "$output" "none" "test_session_start_no_mux (reports none)"

# =============================================================================
# Hooks always exit zero
# =============================================================================

# -- test_hooks_always_exit_zero_session_start --------------------------------
rc=0
_run_hook_all "tmux-session-start.sh" "" "CMUX_FORCE_ENV=none" >/dev/null 2>&1 || rc=$?
assert_ok "$rc" "test_hooks_always_exit_zero: session-start with empty stdin"

# -- test_hooks_always_exit_zero_agent_panel ----------------------------------
rc=0
_run_hook_all "agent-tmux-panel.sh" "" "CMUX_FORCE_ENV=none" >/dev/null 2>&1 || rc=$?
assert_ok "$rc" "test_hooks_always_exit_zero: agent-panel with empty stdin"

# -- test_hooks_always_exit_zero_cleanup --------------------------------------
rc=0
_run_hook_all "agent-tmux-cleanup.sh" "" "CMUX_FORCE_ENV=none" >/dev/null 2>&1 || rc=$?
assert_ok "$rc" "test_hooks_always_exit_zero: cleanup with empty stdin"

# -- test_cleanup_hook_malformed_json -----------------------------------------
rc=0
_run_hook_all "agent-tmux-cleanup.sh" "broken json" "CMUX_FORCE_ENV=cmux" >/dev/null 2>&1 || rc=$?
assert_ok "$rc" "test_cleanup_hook_malformed_json (exits 0)"

# =============================================================================
# Isolation error paths
# =============================================================================

# -- test_create_panel_empty_agent_id -----------------------------------------
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=cmux
rc=0
mux_create_panel "" 2>/dev/null || rc=$?
assert_fail "$rc" "test_create_panel_empty_agent_id"

# -- test_destroy_nonexistent_panel -------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
rc=0
mux_destroy_panel "does-not-exist" 2>/dev/null || rc=$?
assert_fail "$rc" "test_destroy_nonexistent_panel"

# -- test_invalid_agent_id_chars ----------------------------------------------
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=cmux
rc=0
mux_create_panel "agent with spaces" 2>/dev/null || rc=$?
assert_fail "$rc" "test_invalid_agent_id_chars"

# Reset
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=none
