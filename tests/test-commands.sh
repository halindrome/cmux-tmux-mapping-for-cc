#!/usr/bin/env bash
# =============================================================================
# test-commands.sh -- Tests for lib/commands.sh command mapping functions
# =============================================================================

source "${PROJECT_ROOT}/lib/commands.sh"

# -- test_map_split_window_vertical -----------------------------------------
result=$(map_split_window -v 2>/dev/null)
assert_contains "$result" "new-split" "test_map_split_window_vertical (new-split)"
assert_contains "$result" "-v" "test_map_split_window_vertical (-v)"

# -- test_map_split_window_horizontal ---------------------------------------
result=$(map_split_window -h 2>/dev/null)
assert_contains "$result" "new-split" "test_map_split_window_horizontal (new-split)"
assert_contains "$result" "-h" "test_map_split_window_horizontal (-h)"

# -- test_map_send_keys ----------------------------------------------------
result=$(map_send_keys -t "sess:0.1" "echo hello" Enter 2>/dev/null)
assert_contains "$result" "cmux send" "test_map_send_keys (cmux send)"

# -- test_map_select_pane --------------------------------------------------
result=$(map_select_pane -t "sess:0.1" 2>/dev/null)
assert_contains "$result" "select-surface" "test_map_select_pane"

# -- test_map_kill_pane ----------------------------------------------------
result=$(map_kill_pane -t "sess:0.1" 2>/dev/null)
assert_contains "$result" "close-surface" "test_map_kill_pane"

# -- test_map_list_panes ---------------------------------------------------
result=$(map_list_panes 2>/dev/null)
assert_contains "$result" "list-panes" "test_map_list_panes"

# -- test_map_new_session --------------------------------------------------
result=$(map_new_session -s "test" 2>/dev/null)
assert_contains "$result" "new-workspace" "test_map_new_session"

# -- test_map_kill_session -------------------------------------------------
result=$(map_kill_session -t "test" 2>/dev/null)
assert_contains "$result" "close-workspace" "test_map_kill_session"

# -- test_map_command_dispatcher --------------------------------------------
result=$(map_command "split-window -v" 2>/dev/null)
assert_contains "$result" "new-split" "test_map_command_dispatcher"

# -- test_map_unknown_command -----------------------------------------------
rc=0
map_command "unknown-cmd" >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_map_unknown_command"
