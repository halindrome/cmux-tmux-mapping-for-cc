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
#   Supports both in-memory (associative arrays) and file-based persistence.
#   The file-based registry under CMUX_REGISTRY_DIR survives across separate
#   process invocations, which is required for the tmux shim (bin/tmux) since
#   each shim call runs as an independent bash process.
#
# Relationship:
#   Sourced by lib/commands.sh. Does NOT execute any tmux or cmux commands —
#   it only translates identifiers.
#
# Public API (in-memory):
#   register_mapping    tmux_target cmux_surface  — Register a tmux<->cmux pair
#   tmux_target_to_cmux tmux_target               — Look up cmux surface for tmux target
#   cmux_to_tmux_target cmux_surface              — Reverse: cmux surface -> tmux target
#   clear_mappings                                — Reset the ID map (useful for testing)
#
# Public API (file-based registry):
#   registry_init                                 — Create registry dirs if missing
#   registry_register    pane_id surface_id       — Write both mapping files atomically
#   registry_lookup_surface pane_id               — Read surface ID for a pane
#   registry_lookup_pane    surface_id            — Reverse lookup
#   registry_remove      pane_id                  — Remove both mapping files
#   registry_list                                 — List all pane->surface mappings
#   registry_clear                                — Remove all mappings
#   next_pane_id                                  — Atomic counter returning next %N
#
# Identifier Scheme:
#   tmux targets: "session:window.pane" (e.g. "my-sess:0.1")
#     Partial forms: "0.1" (pane only), "sess:0" (session:window), "sess:0.1" (full)
#     Pane IDs: "%N" format (e.g. "%0", "%1")
#   cmux surfaces: opaque string IDs (e.g. "surface-abc-123")
#
# Example:
#   source lib/id-map.sh
#   register_mapping "%0" "surface-abc"
#   tmux_target_to_cmux "%0"  # prints: surface-abc (in-memory + file fallback)
# ==============================================================================

# Guard against double-sourcing
[[ -n "${_CMUX_ID_MAP_LOADED:-}" ]] && return 0
_CMUX_ID_MAP_LOADED=1

set -euo pipefail

# Source core.sh if available (may not exist yet during parallel builds)
_IDMAP_DIR="${BASH_SOURCE[0]%/*}"
[[ -f "${_IDMAP_DIR}/core.sh" ]] && source "${_IDMAP_DIR}/core.sh"

# --- In-memory storage ---
declare -gA _CMUX_ID_MAP=()
declare -gA _CMUX_ID_MAP_REVERSE=()

# --- File-based registry ---
# Default registry directory; override via CMUX_REGISTRY_DIR env var
: "${CMUX_REGISTRY_DIR:=/tmp/cmux-shim-${UID:-$(id -u)}}"

# registry_init()
#   Create the registry directory structure if it doesn't exist.
#   Returns: 0 on success
registry_init() {
  mkdir -p "${CMUX_REGISTRY_DIR}/pane-to-surface" \
           "${CMUX_REGISTRY_DIR}/surface-to-pane"
  return 0
}

# registry_register(pane_id, surface_id)
#   Write both mapping files atomically (write to .tmp then mv).
#   Args:
#     $1 — pane ID (e.g. "%0")
#     $2 — cmux surface identifier
#   Returns: 0 on success, 1 if arguments missing
registry_register() {
  local pane_id="${1:-}"
  local surface_id="${2:-}"

  if [[ -z "$pane_id" || -z "$surface_id" ]]; then
    echo "registry_register: requires pane_id and surface_id arguments" >&2
    return 1
  fi

  registry_init

  # Sanitize pane_id for filename (replace % with _pct_)
  local safe_pane="${pane_id//%/_pct_}"

  # Atomic write: tmp file then mv
  printf '%s' "$surface_id" > "${CMUX_REGISTRY_DIR}/pane-to-surface/${safe_pane}.tmp"
  mv "${CMUX_REGISTRY_DIR}/pane-to-surface/${safe_pane}.tmp" \
     "${CMUX_REGISTRY_DIR}/pane-to-surface/${safe_pane}"

  printf '%s' "$pane_id" > "${CMUX_REGISTRY_DIR}/surface-to-pane/${surface_id}.tmp"
  mv "${CMUX_REGISTRY_DIR}/surface-to-pane/${surface_id}.tmp" \
     "${CMUX_REGISTRY_DIR}/surface-to-pane/${surface_id}"

  return 0
}

# registry_lookup_surface(pane_id)
#   Read surface ID for a given pane from the file-based registry.
#   Args:
#     $1 — pane ID (e.g. "%0")
#   Stdout: surface identifier
#   Returns: 0 if found, 1 if not found
registry_lookup_surface() {
  local pane_id="${1:-}"
  if [[ -z "$pane_id" ]]; then
    return 1
  fi

  local safe_pane="${pane_id//%/_pct_}"
  local file="${CMUX_REGISTRY_DIR}/pane-to-surface/${safe_pane}"

  if [[ -f "$file" ]]; then
    cat "$file"
    return 0
  fi
  return 1
}

# registry_lookup_pane(surface_id)
#   Reverse lookup: surface ID -> pane ID from file-based registry.
#   Args:
#     $1 — cmux surface identifier
#   Stdout: pane ID
#   Returns: 0 if found, 1 if not found
registry_lookup_pane() {
  local surface_id="${1:-}"
  if [[ -z "$surface_id" ]]; then
    return 1
  fi

  local file="${CMUX_REGISTRY_DIR}/surface-to-pane/${surface_id}"

  if [[ -f "$file" ]]; then
    cat "$file"
    return 0
  fi
  return 1
}

# registry_remove(pane_id)
#   Remove both mapping files for a pane.
#   Args:
#     $1 — pane ID (e.g. "%0")
#   Returns: 0 always
registry_remove() {
  local pane_id="${1:-}"
  if [[ -z "$pane_id" ]]; then
    return 0
  fi

  local safe_pane="${pane_id//%/_pct_}"
  local pane_file="${CMUX_REGISTRY_DIR}/pane-to-surface/${safe_pane}"

  # Read surface ID before removing so we can clean up reverse mapping
  if [[ -f "$pane_file" ]]; then
    local surface_id
    surface_id="$(cat "$pane_file")"
    rm -f "$pane_file"
    rm -f "${CMUX_REGISTRY_DIR}/surface-to-pane/${surface_id}"
  fi

  return 0
}

# registry_list()
#   List all pane->surface mappings, one per line as "pane_id surface_id".
#   Stdout: lines of "pane_id surface_id"
#   Returns: 0 always
registry_list() {
  local pane_dir="${CMUX_REGISTRY_DIR}/pane-to-surface"
  if [[ ! -d "$pane_dir" ]]; then
    return 0
  fi

  local f safe_pane pane_id surface_id
  for f in "${pane_dir}"/*; do
    [[ -f "$f" ]] || continue
    safe_pane="$(basename "$f")"
    # Skip tmp files
    [[ "$safe_pane" == *.tmp ]] && continue
    # Restore pane_id from safe name
    pane_id="${safe_pane//_pct_/%}"
    surface_id="$(cat "$f")"
    printf '%s %s\n' "$pane_id" "$surface_id"
  done
  return 0
}

# registry_clear()
#   Remove all mappings from the file-based registry.
#   Returns: 0 always
registry_clear() {
  if [[ -d "${CMUX_REGISTRY_DIR}/pane-to-surface" ]]; then
    rm -f "${CMUX_REGISTRY_DIR}/pane-to-surface"/*
  fi
  if [[ -d "${CMUX_REGISTRY_DIR}/surface-to-pane" ]]; then
    rm -f "${CMUX_REGISTRY_DIR}/surface-to-pane"/*
  fi
  # Also reset the pane counter
  rm -f "${CMUX_REGISTRY_DIR}/next-pane-id"
  return 0
}

# --- Atomic pane counter ---

# next_pane_id()
#   Return the next pane ID in %N format. Uses file-based counter with
#   mkdir-based locking for concurrent access safety.
#   Stdout: pane ID (e.g. "%0", "%1", "%2")
#   Returns: 0 on success
next_pane_id() {
  registry_init

  local counter_file="${CMUX_REGISTRY_DIR}/next-pane-id"
  local lock_dir="${CMUX_REGISTRY_DIR}/.pane-counter.lock"
  local current=0

  # Acquire lock (mkdir is atomic on all POSIX systems)
  local retries=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    retries=$(( retries + 1 ))
    if [[ $retries -gt 100 ]]; then
      echo "next_pane_id: failed to acquire lock" >&2
      return 1
    fi
    # Brief sleep to avoid busy-wait (0.01s)
    sleep 0.01
  done

  # Read current value
  if [[ -f "$counter_file" ]]; then
    current="$(cat "$counter_file")"
  fi

  # Increment and write back
  local next=$(( current + 1 ))
  printf '%s' "$next" > "$counter_file"

  # Release lock
  rmdir "$lock_dir"

  # Return pane ID in %N format
  printf '%%%d\n' "$current"
  return 0
}

# --- Public functions (in-memory with file-based fallback) ---

# register_mapping(tmux_target, cmux_surface)
#   Register a bidirectional tmux<->cmux identifier mapping.
#   Writes to both in-memory maps and file-based registry.
#   Args:
#     $1 — tmux target string (e.g. "%0", "sess:0.1")
#     $2 — cmux surface identifier (e.g. "surface-abc")
#   Returns: 0 on success, 1 if arguments missing
register_mapping() {
  local tmux_target="${1:-}"
  local cmux_surface="${2:-}"

  if [[ -z "$tmux_target" || -z "$cmux_surface" ]]; then
    echo "register_mapping: requires tmux_target and cmux_surface arguments" >&2
    return 1
  fi

  # In-memory
  _CMUX_ID_MAP["$tmux_target"]="$cmux_surface"
  _CMUX_ID_MAP_REVERSE["$cmux_surface"]="$tmux_target"

  # File-based (best-effort; don't fail if registry dir issues)
  registry_register "$tmux_target" "$cmux_surface" 2>/dev/null || true

  return 0
}

# tmux_target_to_cmux(tmux_target)
#   Look up the cmux surface ID for a given tmux target.
#   Tries in-memory first, then falls back to file-based registry.
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

  # Exact match in memory
  if [[ -n "${_CMUX_ID_MAP[$target]+x}" ]]; then
    echo "${_CMUX_ID_MAP[$target]}"
    return 0
  fi

  # Suffix match in memory for partial targets
  local key
  for key in "${!_CMUX_ID_MAP[@]}"; do
    if [[ "$key" == *"$target" ]]; then
      echo "${_CMUX_ID_MAP[$key]}"
      return 0
    fi
  done

  # Fall back to file-based registry
  local surface
  if surface="$(registry_lookup_surface "$target" 2>/dev/null)"; then
    echo "$surface"
    return 0
  fi

  echo "tmux_target_to_cmux: no mapping found for '$target'" >&2
  return 1
}

# cmux_to_tmux_target(cmux_surface)
#   Reverse lookup: cmux surface ID -> tmux target string.
#   Tries in-memory first, then falls back to file-based registry.
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

  # In-memory lookup
  if [[ -n "${_CMUX_ID_MAP_REVERSE[$surface]+x}" ]]; then
    echo "${_CMUX_ID_MAP_REVERSE[$surface]}"
    return 0
  fi

  # Fall back to file-based registry
  local pane
  if pane="$(registry_lookup_pane "$surface" 2>/dev/null)"; then
    echo "$pane"
    return 0
  fi

  echo "cmux_to_tmux_target: no mapping found for '$surface'" >&2
  return 1
}

# clear_mappings()
#   Reset both in-memory mapping tables and file-based registry.
#   Returns: 0 always
clear_mappings() {
  _CMUX_ID_MAP=()
  _CMUX_ID_MAP_REVERSE=()
  registry_clear 2>/dev/null || true
  return 0
}
