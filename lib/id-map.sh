#!/usr/bin/env bash
# ==============================================================================
# id-map.sh — Identifier translation between tmux and cmux targeting schemes
#
# Purpose:
#   Translates tmux's "session:window.pane" target format to cmux's workspace/
#   surface identifiers, and vice versa. Maintains a bidirectional mapping table
#   so that commands translated by commands.sh can reference the correct cmux
#   surface for a given tmux pane target.
#
# Relationship:
#   Sourced by lib/commands.sh. Does NOT execute any tmux or cmux commands —
#   it only translates identifiers.
#
# Public API:
#   register_mapping    tmux_target cmux_surface  — Register a tmux<->cmux pair
#   tmux_target_to_cmux tmux_target               — Look up cmux surface for tmux target
#   cmux_to_tmux_target cmux_surface              — Reverse: cmux surface -> tmux target
#   clear_mappings                                — Reset the ID map (useful for testing)
#
# Identifier Scheme:
#   tmux targets: "session:window.pane" (e.g. "my-sess:0.1")
#     Partial forms: "0.1" (pane only), "sess:0" (session:window), "sess:0.1" (full)
#   cmux surfaces: opaque string IDs (e.g. "surface-abc-123")
#
# Limitations:
#   - Mapping is in-memory only; lost when the shell exits
#   - No persistence across sessions (caller must re-register)
#   - Partial tmux targets are stored as-is; no normalization to full form
#
# Example:
#   source lib/id-map.sh
#   register_mapping "my-sess:0.1" "surface-abc"
#   tmux_target_to_cmux "my-sess:0.1"  # prints: surface-abc
#   cmux_to_tmux_target "surface-abc"   # prints: my-sess:0.1
# ==============================================================================

# Guard against double-sourcing
[[ -n "${_CMUX_ID_MAP_LOADED:-}" ]] && return 0
_CMUX_ID_MAP_LOADED=1

set -euo pipefail

# Source core.sh if available (may not exist yet during parallel builds)
_IDMAP_DIR="${BASH_SOURCE[0]%/*}"
[[ -f "${_IDMAP_DIR}/core.sh" ]] && source "${_IDMAP_DIR}/core.sh"

# --- Internal storage ---
# Associative arrays: tmux_target -> cmux_surface and reverse
declare -gA _CMUX_ID_MAP=()
declare -gA _CMUX_ID_MAP_REVERSE=()

# --- Public functions ---

# register_mapping(tmux_target, cmux_surface)
#   Register a bidirectional tmux<->cmux identifier mapping.
#   Args:
#     $1 — tmux target string (e.g. "sess:0.1")
#     $2 — cmux surface identifier (e.g. "surface-abc")
#   Returns: 0 on success, 1 if arguments missing
register_mapping() {
  local tmux_target="${1:-}"
  local cmux_surface="${2:-}"

  if [[ -z "$tmux_target" || -z "$cmux_surface" ]]; then
    echo "register_mapping: requires tmux_target and cmux_surface arguments" >&2
    return 1
  fi

  _CMUX_ID_MAP["$tmux_target"]="$cmux_surface"
  _CMUX_ID_MAP_REVERSE["$cmux_surface"]="$tmux_target"
  return 0
}

# tmux_target_to_cmux(tmux_target)
#   Look up the cmux surface ID for a given tmux target.
#   Handles partial targets by searching for suffix matches if exact match fails.
#   Args:
#     $1 — tmux target string
#   Stdout: cmux surface identifier
#   Returns: 0 if found, 1 if not found or missing argument
tmux_target_to_cmux() {
  local target="${1:-}"

  if [[ -z "$target" ]]; then
    echo "tmux_target_to_cmux: requires target argument" >&2
    return 1
  fi

  # Exact match first
  if [[ -n "${_CMUX_ID_MAP[$target]+x}" ]]; then
    echo "${_CMUX_ID_MAP[$target]}"
    return 0
  fi

  # Try suffix match for partial targets (e.g. "0.1" matching "sess:0.1")
  local key
  for key in "${!_CMUX_ID_MAP[@]}"; do
    if [[ "$key" == *"$target" ]]; then
      echo "${_CMUX_ID_MAP[$key]}"
      return 0
    fi
  done

  echo "tmux_target_to_cmux: no mapping found for '$target'" >&2
  return 1
}

# cmux_to_tmux_target(cmux_surface)
#   Reverse lookup: cmux surface ID -> tmux target string.
#   Args:
#     $1 — cmux surface identifier
#   Stdout: tmux target string
#   Returns: 0 if found, 1 if not found or missing argument
cmux_to_tmux_target() {
  local surface="${1:-}"

  if [[ -z "$surface" ]]; then
    echo "cmux_to_tmux_target: requires surface argument" >&2
    return 1
  fi

  if [[ -n "${_CMUX_ID_MAP_REVERSE[$surface]+x}" ]]; then
    echo "${_CMUX_ID_MAP_REVERSE[$surface]}"
    return 0
  fi

  echo "cmux_to_tmux_target: no mapping found for '$surface'" >&2
  return 1
}

# clear_mappings()
#   Reset both mapping tables. Primarily used for testing.
#   Returns: 0 always
clear_mappings() {
  _CMUX_ID_MAP=()
  _CMUX_ID_MAP_REVERSE=()
  return 0
}
