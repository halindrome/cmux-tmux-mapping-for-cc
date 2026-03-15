#!/usr/bin/env bash
# ============================================================================
# isolation.sh — Agent Panel Isolation for Claude Code Agent Teams
# ============================================================================
#
# Purpose:
#   Manages the lifecycle of isolated agent panels for Claude Code Agent Teams.
#   Each agent gets a dedicated panel (pane/surface) tracked via an in-memory
#   registry. This module generates commands but does NOT execute them — the
#   actual execution is delegated to the environment-specific backend (tmux or
#   cmux) via mapper.sh.
#
# Design:
#   Abstract isolation layer. Functions return command strings and panel handles
#   on stdout. The caller (mapper.sh) is responsible for executing commands in
#   the detected environment. This decoupling lets the same isolation logic
#   work with both tmux and cmux backends.
#
# Lifecycle:
#   1. create_agent_panel  — allocate a panel, register in _AGENT_PANELS
#   2. get_agent_panel     — look up handle for subsequent operations
#   3. destroy_agent_panel — generate cleanup command, remove from registry
#
# Integration:
#   Will be wired to detect.sh and commands.sh via mapper.sh (Plan 04).
#   mapper.sh sources this file and calls these functions to manage agent
#   panel allocation before/after command translation.
#
# Limitations:
#   - In-memory state only — panel registry is NOT persisted across sessions
#   - Panel handles assume the backend is stable for the session lifetime
#   - No inter-process synchronization (single-process use only)
#
# Example Usage:
#   source lib/isolation.sh
#
#   # Create a panel for agent-1 (vertical split)
#   handle=$(create_agent_panel "agent-1" "v")
#   echo "Created panel: $handle"
#
#   # Look up the panel later
#   handle=$(get_agent_panel "agent-1")
#
#   # Get environment variables for the agent's panel
#   get_panel_env_vars "agent-1"
#
#   # List all active agent panels
#   list_agent_panels
#
#   # Destroy a specific agent's panel
#   destroy_agent_panel "agent-1"
#
#   # Cleanup everything at session end
#   cleanup_all_panels
#
# ============================================================================

# Guard against double-sourcing
[[ -n "${_ISOLATION_SH_LOADED:-}" ]] && return 0
_ISOLATION_SH_LOADED=1

# Internal registry: agent_id -> panel_handle
# Panel handle format: "{env}:{identifier}"
#   env        = cmux | tmux
#   identifier = surface ID (cmux) or session:window.pane (tmux)
declare -A _AGENT_PANELS=()

# Internal counter for generating panel identifiers
_PANEL_COUNTER=0

# Detect which environment to use for handle prefixes.
# Checks CMUX_FORCE_ENV first (for testing), then probes for cmux/tmux.
_isolation_detect_env() {
    if [[ -n "${CMUX_FORCE_ENV:-}" ]]; then
        echo "$CMUX_FORCE_ENV"
        return 0
    fi
    if command -v cmux &>/dev/null; then
        echo "cmux"
    elif [[ -n "${TMUX:-}" ]]; then
        echo "tmux"
    else
        echo "none"
    fi
}

# ---------------------------------------------------------------------------
# validate_agent_id — Check that an agent ID is well-formed
#
# Args:
#   $1  agent_id — the identifier to validate
#
# Returns:
#   0 if valid (non-empty, alphanumeric/dash/underscore only)
#   1 if invalid
#
# Stderr:
#   Prints a descriptive error message on failure
# ---------------------------------------------------------------------------
validate_agent_id() {
    local agent_id="${1:-}"

    if [[ -z "$agent_id" ]]; then
        echo "error: agent_id must not be empty" >&2
        return 1
    fi

    if [[ ! "$agent_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "error: agent_id contains invalid characters (allowed: a-z, A-Z, 0-9, -, _)" >&2
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# create_agent_panel — Allocate a new panel for the given agent
#
# Args:
#   $1  agent_id  — unique identifier for the agent
#   $2  direction — "v" (vertical, default) or "h" (horizontal)
#
# Stdout:
#   The panel handle (format: "{env}:{identifier}")
#
# Returns:
#   0 on success
#   1 if agent_id already has a panel (no duplicates) or is invalid
# ---------------------------------------------------------------------------
create_agent_panel() {
    local agent_id="${1:-}"
    local direction="${2:-v}"

    validate_agent_id "$agent_id" || return 1

    # Reject duplicates
    if [[ -n "${_AGENT_PANELS[$agent_id]+_}" ]]; then
        echo "error: agent '$agent_id' already has a panel: ${_AGENT_PANELS[$agent_id]}" >&2
        return 1
    fi

    local env
    env=$(_isolation_detect_env)

    # Generate a unique identifier
    (( _PANEL_COUNTER++ ))
    local identifier="panel-${_PANEL_COUNTER}"

    local handle="${env}:${identifier}"
    _AGENT_PANELS[$agent_id]="$handle"

    echo "$handle"
    return 0
}

# ---------------------------------------------------------------------------
# get_agent_panel — Look up the panel handle for a given agent
#
# Args:
#   $1  agent_id — the agent to look up
#
# Stdout:
#   The panel handle if found
#
# Returns:
#   0 if found
#   1 if not found
# ---------------------------------------------------------------------------
get_agent_panel() {
    local agent_id="${1:-}"

    if [[ -z "${_AGENT_PANELS[$agent_id]+_}" ]]; then
        return 1
    fi

    echo "${_AGENT_PANELS[$agent_id]}"
    return 0
}

# ---------------------------------------------------------------------------
# destroy_agent_panel — Remove an agent's panel from the registry
#
# Args:
#   $1  agent_id — the agent whose panel should be destroyed
#
# Stdout:
#   The panel handle that was destroyed (for command generation by caller)
#
# Returns:
#   0 on success
#   1 if agent not found
# ---------------------------------------------------------------------------
destroy_agent_panel() {
    local agent_id="${1:-}"

    if [[ -z "${_AGENT_PANELS[$agent_id]+_}" ]]; then
        echo "error: no panel found for agent '$agent_id'" >&2
        return 1
    fi

    local handle="${_AGENT_PANELS[$agent_id]}"
    unset '_AGENT_PANELS[$agent_id]'

    echo "$handle"
    return 0
}

# ---------------------------------------------------------------------------
# list_agent_panels — Print all registered agent_id -> panel_handle mappings
#
# Stdout:
#   One line per agent: "agent_id handle"
#
# Returns:
#   0 always
# ---------------------------------------------------------------------------
list_agent_panels() {
    local agent_id
    for agent_id in "${!_AGENT_PANELS[@]}"; do
        echo "$agent_id ${_AGENT_PANELS[$agent_id]}"
    done
    return 0
}

# ---------------------------------------------------------------------------
# cleanup_all_panels — Remove all panels from the registry
#
# Stdout:
#   One line per destroyed panel: the handle
#
# Returns:
#   0 always
# ---------------------------------------------------------------------------
cleanup_all_panels() {
    local agent_id
    for agent_id in "${!_AGENT_PANELS[@]}"; do
        echo "${_AGENT_PANELS[$agent_id]}"
    done
    _AGENT_PANELS=()
    return 0
}

# ---------------------------------------------------------------------------
# panel_count — Print the number of active panels
#
# Stdout:
#   Integer count of registered panels
#
# Returns:
#   0 always
# ---------------------------------------------------------------------------
panel_count() {
    echo "${#_AGENT_PANELS[@]}"
    return 0
}

# ---------------------------------------------------------------------------
# get_panel_env_vars — Return environment variable assignments for an agent
#
# Args:
#   $1  agent_id — the agent to get env vars for
#
# Stdout:
#   key=value lines:
#     CMUX_AGENT_ID={agent_id}
#     CMUX_PANEL_HANDLE={panel_handle}
#     CMUX_PANEL_ENV={cmux|tmux|none}
#
# Returns:
#   0 on success
#   1 if agent has no panel
# ---------------------------------------------------------------------------
get_panel_env_vars() {
    local agent_id="${1:-}"

    local handle
    handle=$(get_agent_panel "$agent_id") || {
        echo "error: no panel found for agent '$agent_id'" >&2
        return 1
    }

    # Extract env from handle (everything before the first colon)
    local panel_env="${handle%%:*}"

    echo "CMUX_AGENT_ID=${agent_id}"
    echo "CMUX_PANEL_HANDLE=${handle}"
    echo "CMUX_PANEL_ENV=${panel_env}"
    return 0
}
