#!/usr/bin/env bash
# =============================================================================
# core.sh -- Shared constants and logging helpers for cmux-tmux-mapping-for-cc
#
# Usage:
#   source lib/core.sh
#
# Public API:
#   CMUX_TMUX_MAPPER_VERSION  - Plugin version string
#   E_OK, E_NOT_FOUND, E_BLOCK, E_INVALID_ARGS - Standard error codes
#   log_debug "msg"   - Debug log (only when CMUX_MAPPER_DEBUG=1)
#   log_info  "msg"   - Info log
#   log_warn  "msg"   - Warning log
#   log_error "msg"   - Error log
# =============================================================================
set -euo pipefail

# Guard against double-sourcing
[[ -n "${CMUX_CORE_LOADED:-}" ]] && return 0
CMUX_CORE_LOADED=1

# -- Version -------------------------------------------------------------------
CMUX_TMUX_MAPPER_VERSION="0.1.0"

# -- Error codes ---------------------------------------------------------------
E_OK=0
E_NOT_FOUND=1
E_BLOCK=2
E_INVALID_ARGS=3

# -- Logging helpers (write to stderr) -----------------------------------------

# Log a debug message (only when CMUX_MAPPER_DEBUG=1)
log_debug() {
  [[ "${CMUX_MAPPER_DEBUG:-0}" == "1" ]] && printf '[DEBUG] %s\n' "$*" >&2
  return 0
}

# Log an informational message
log_info() {
  printf '[INFO] %s\n' "$*" >&2
}

# Log a warning message
log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

# Log an error message
log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}
