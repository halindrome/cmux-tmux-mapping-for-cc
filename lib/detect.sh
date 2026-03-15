#!/usr/bin/env bash
# =============================================================================
# detect.sh -- Environment detection for cmux-tmux-mapping-for-cc
#
# Determines whether the current session is running inside cmux, tmux, or
# neither. This is the foundation that all other mapping functions depend on
# to route commands correctly.
#
# Usage:
#   source lib/detect.sh
#   env=$(detect_environment)
#   if is_cmux; then echo "Running in cmux"; fi
#   if is_tmux; then echo "Running in tmux"; fi
#   if is_neither; then echo "No multiplexer detected"; fi
#
# Public API:
#   detect_environment  - Returns "cmux", "tmux", or "none"
#   is_cmux             - Returns 0 if cmux detected, 1 otherwise
#   is_tmux             - Returns 0 if tmux detected, 1 otherwise
#   is_neither          - Returns 0 if neither detected, 1 otherwise
#
# Environment Variables:
#   CMUX_FORCE_ENV      - Override detection (set to "cmux", "tmux", or "none")
# =============================================================================
set -euo pipefail

# Source shared constants and logging
_DETECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_DETECT_DIR}/core.sh"

# Guard against double-sourcing
[[ -n "${CMUX_DETECT_LOADED:-}" ]] && return 0
CMUX_DETECT_LOADED=1

# Cached detection result
_DETECTED_ENV=""

# Detect the current multiplexer environment.
# Returns "cmux", "tmux", or "none" on stdout.
detect_environment() {
  # Return cached result if available
  if [[ -n "$_DETECTED_ENV" ]]; then
    printf '%s\n' "$_DETECTED_ENV"
    return "$E_OK"
  fi

  # Allow override for testing
  if [[ -n "${CMUX_FORCE_ENV:-}" ]]; then
    _DETECTED_ENV="$CMUX_FORCE_ENV"
    log_debug "Environment forced to: $_DETECTED_ENV"
    printf '%s\n' "$_DETECTED_ENV"
    return "$E_OK"
  fi

  # Detection logic (fail-safe: default to "none" on errors)
  # 1. Check for cmux: CLI available AND cmux identify succeeds
  if command -v cmux >/dev/null 2>&1 && cmux identify --json >/dev/null 2>&1; then
    _DETECTED_ENV="cmux"
    log_debug "Detected environment: cmux"
  # 2. Check for tmux: $TMUX variable set and non-empty
  elif [[ -n "${TMUX:-}" ]]; then
    _DETECTED_ENV="tmux"
    log_debug "Detected environment: tmux"
  # 3. Neither
  else
    _DETECTED_ENV="none"
    log_debug "Detected environment: none"
  fi

  printf '%s\n' "$_DETECTED_ENV"
  return "$E_OK"
}

# Returns 0 (true) if running inside cmux, 1 (false) otherwise
is_cmux() {
  [[ "$(detect_environment)" == "cmux" ]]
}

# Returns 0 (true) if running inside tmux, 1 (false) otherwise
is_tmux() {
  [[ "$(detect_environment)" == "tmux" ]]
}

# Returns 0 (true) if neither cmux nor tmux detected, 1 (false) otherwise
is_neither() {
  [[ "$(detect_environment)" == "none" ]]
}
