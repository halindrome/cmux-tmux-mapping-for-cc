#!/usr/bin/env bash
# =============================================================================
# test-detect.sh -- Tests for lib/detect.sh environment detection
# =============================================================================

source "${PROJECT_ROOT}/lib/detect.sh"

# -- test_detect_cmux_forced ------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
result=$(detect_environment)
assert_eq "cmux" "$result" "test_detect_cmux_forced"

# -- test_detect_tmux_forced ------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=tmux
result=$(detect_environment)
assert_eq "tmux" "$result" "test_detect_tmux_forced"

# -- test_detect_none_forced ------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=none
result=$(detect_environment)
assert_eq "none" "$result" "test_detect_none_forced"

# -- test_is_cmux -----------------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
is_cmux
assert_ok $? "test_is_cmux"

# -- test_is_tmux -----------------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=tmux
is_tmux
assert_ok $? "test_is_tmux"

# -- test_is_neither --------------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=none
is_neither
assert_ok $? "test_is_neither"

# -- test_detect_caching ----------------------------------------------------
_DETECTED_ENV=""
CMUX_FORCE_ENV=cmux
result1=$(detect_environment)
result2=$(detect_environment)
assert_eq "$result1" "$result2" "test_detect_caching"

# Reset for next test file
CMUX_FORCE_ENV=none
_DETECTED_ENV=""
