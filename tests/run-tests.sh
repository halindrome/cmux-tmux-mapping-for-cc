#!/usr/bin/env bash
# =============================================================================
# run-tests.sh -- Zero-dependency bash test runner
#
# Discovers and runs all tests/test-*.sh files, tracks pass/fail counts,
# and exits with 0 if all pass, 1 if any fail.
# =============================================================================
set -euo pipefail

# Resolve directories
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

# Default: tests should not require live tmux/cmux
export CMUX_FORCE_ENV="${CMUX_FORCE_ENV:-none}"

# Color output (when terminal supports it)
if [[ -t 1 ]]; then
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  GREEN=''
  RED=''
  BOLD=''
  RESET=''
fi

# Counters
_PASS_COUNT=0
_FAIL_COUNT=0
_CURRENT_TEST=""

# ---------------------------------------------------------------------------
# Assertion helpers
# ---------------------------------------------------------------------------

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_eq}"

  if [[ "$expected" == "$actual" ]]; then
    _PASS_COUNT=$(( _PASS_COUNT + 1 ))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "    expected: '%s'\n" "$expected"
    printf "    actual:   '%s'\n" "$actual"
  fi
}

assert_ok() {
  local exit_code="$1"
  local msg="${2:-assert_ok}"

  if [[ "$exit_code" -eq 0 ]]; then
    _PASS_COUNT=$(( _PASS_COUNT + 1 ))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "    expected exit 0, got: %s\n" "$exit_code"
  fi
}

assert_fail() {
  local exit_code="$1"
  local msg="${2:-assert_fail}"

  if [[ "$exit_code" -ne 0 ]]; then
    _PASS_COUNT=$(( _PASS_COUNT + 1 ))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "    expected non-zero exit, got: 0\n"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-assert_contains}"

  if [[ "$haystack" == *"$needle"* ]]; then
    _PASS_COUNT=$(( _PASS_COUNT + 1 ))
    printf "  ${GREEN}PASS${RESET} %s\n" "$msg"
  else
    _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
    printf "  ${RED}FAIL${RESET} %s\n" "$msg"
    printf "    haystack: '%s'\n" "$haystack"
    printf "    needle:   '%s'\n" "$needle"
  fi
}

# Export helpers and counters so test files can use them
export -f assert_eq assert_ok assert_fail assert_contains
export TESTS_DIR PROJECT_ROOT

# ---------------------------------------------------------------------------
# Test discovery and execution
# ---------------------------------------------------------------------------

printf "${BOLD}Running tests...${RESET}\n\n"

# Collect test files
test_files=()
for f in "${TESTS_DIR}"/test-*.sh; do
  [[ -f "$f" ]] && test_files+=("$f")
done

if [[ ${#test_files[@]} -eq 0 ]]; then
  printf "${RED}No test files found!${RESET}\n"
  exit 1
fi

# Run each test file in the current shell (not subshell) so counters accumulate
for test_file in "${test_files[@]}"; do
  test_name="$(basename "$test_file")"
  printf "${BOLD}%s${RESET}\n" "$test_name"

  # Source the test file so it shares our assertion helpers and counters
  # Reset detection cache between test files
  _DETECTED_ENV=""
  source "$test_file"

  printf "\n"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

total=$(( _PASS_COUNT + _FAIL_COUNT ))
printf "${BOLD}Results: ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET} (of %d)\n" \
  "$_PASS_COUNT" "$_FAIL_COUNT" "$total"

if [[ "$_FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
