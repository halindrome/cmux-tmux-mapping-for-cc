#!/usr/bin/env bash
# =============================================================================
# test-mapper.sh -- Integration tests for lib/mapper.sh unified API
# =============================================================================

source "${PROJECT_ROOT}/lib/mapper.sh"

# Reset state
_AGENT_PANELS=()
_PANEL_COUNTER=0

# -- test_mux_env_cmux ------------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
result=$(mux_env)
assert_eq "cmux" "$result" "test_mux_env_cmux"

# -- test_mux_env_tmux ------------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=tmux
result=$(mux_env)
assert_eq "tmux" "$result" "test_mux_env_tmux"

# -- test_mux_command_cmux_split --------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
result=$(mux_command "split-window" "-v" 2>/dev/null)
assert_contains "$result" "cmux" "test_mux_command_cmux_split (cmux)"
assert_contains "$result" "new-split" "test_mux_command_cmux_split (new-split)"

# -- test_mux_command_tmux_passthrough --------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=tmux
result=$(mux_command "split-window" "-v" 2>/dev/null)
assert_contains "$result" "tmux" "test_mux_command_tmux_passthrough (tmux)"
assert_contains "$result" "split-window" "test_mux_command_tmux_passthrough (split-window)"

# -- test_mux_command_none_errors -------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=none
rc=0
mux_command "split-window" >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_mux_command_none_errors"

# Reset
CMUX_FORCE_ENV=none
_DETECTED_ENV=""
_AGENT_PANELS=()
_PANEL_COUNTER=0
