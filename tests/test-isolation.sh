#!/usr/bin/env bash
# =============================================================================
# test-isolation.sh -- Tests for lib/isolation.sh agent panel lifecycle
# =============================================================================

source "${PROJECT_ROOT}/lib/isolation.sh"

# Reset state before tests
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=none

# -- test_create_agent_panel ------------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
handle=$(create_agent_panel "agent-1" 2>/dev/null)
rc=$?
assert_ok "$rc" "test_create_agent_panel (returns 0)"
assert_contains "$handle" "panel-" "test_create_agent_panel (outputs handle)"

# -- test_duplicate_panel_rejected ------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
# Create in current shell (not subshell) so registry is populated
create_agent_panel "agent-dup" >/dev/null 2>&1
rc=0
create_agent_panel "agent-dup" >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_duplicate_panel_rejected"

# -- test_get_agent_panel ---------------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
# Create in current shell, then get the handle directly
create_agent_panel "agent-2" >/dev/null 2>&1
retrieved=$(get_agent_panel "agent-2" 2>/dev/null)
# Handle format is {env}:panel-{N}; verify it matches expected pattern
assert_contains "$retrieved" "panel-" "test_get_agent_panel"

# -- test_destroy_agent_panel -----------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
create_agent_panel "agent-3" >/dev/null 2>&1
destroy_agent_panel "agent-3" >/dev/null 2>&1
rc=0
get_agent_panel "agent-3" >/dev/null 2>&1 || rc=$?
assert_fail "$rc" "test_destroy_agent_panel"

# -- test_list_agent_panels -------------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
create_agent_panel "a1" >/dev/null 2>&1
create_agent_panel "a2" >/dev/null 2>&1
create_agent_panel "a3" >/dev/null 2>&1
listing=$(list_agent_panels 2>/dev/null)
count=$(echo "$listing" | grep -c "panel-")
assert_eq "3" "$count" "test_list_agent_panels"

# -- test_cleanup_all -------------------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
create_agent_panel "b1" >/dev/null 2>&1
create_agent_panel "b2" >/dev/null 2>&1
create_agent_panel "b3" >/dev/null 2>&1
cleanup_all_panels >/dev/null 2>&1
cnt=$(panel_count)
assert_eq "0" "$cnt" "test_cleanup_all"

# -- test_validate_agent_id_valid -------------------------------------------
validate_agent_id "agent-1" 2>/dev/null
assert_ok $? "test_validate_agent_id_valid"

# -- test_validate_agent_id_empty -------------------------------------------
rc=0
validate_agent_id "" 2>/dev/null || rc=$?
assert_fail "$rc" "test_validate_agent_id_empty"

# -- test_panel_env_vars ----------------------------------------------------
_AGENT_PANELS=()
_PANEL_COUNTER=0
create_agent_panel "env-agent" >/dev/null 2>&1
env_output=$(get_panel_env_vars "env-agent" 2>/dev/null)
assert_contains "$env_output" "CMUX_AGENT_ID" "test_panel_env_vars"

# Reset
_AGENT_PANELS=()
_PANEL_COUNTER=0
CMUX_FORCE_ENV=none
_DETECTED_ENV=""
