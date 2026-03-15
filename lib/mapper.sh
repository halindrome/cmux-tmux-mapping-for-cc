#!/usr/bin/env bash
# =============================================================================
# mapper.sh -- Unified tmux-to-cmux mapping entry point
#
# Wires together detect.sh, commands.sh, and isolation.sh into a single public
# API that auto-detects the environment and routes operations accordingly.
#
# Usage:
#   source lib/mapper.sh
#   mux_command "split-window" "-v"
#   mux_create_panel "agent-1" "v"
#   mux_env
#
# Public API:
#   mux_command       subcmd ...args  -- Translate and return executable command
#   mux_create_panel  agent_id [dir]  -- Create isolated agent panel
#   mux_destroy_panel agent_id        -- Destroy agent panel
#   mux_send          agent_id text   -- Send text to agent's panel
#   mux_list                          -- List panels/panes
#   mux_env                           -- Print detected environment
# =============================================================================
set -euo pipefail

# Guard against double-sourcing
[[ -n "${_CMUX_MAPPER_LOADED:-}" ]] && return 0
_CMUX_MAPPER_LOADED=1

# Resolve lib directory relative to this script
_MAPPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all dependency modules
source "${_MAPPER_DIR}/core.sh"
source "${_MAPPER_DIR}/detect.sh"
source "${_MAPPER_DIR}/commands.sh"
source "${_MAPPER_DIR}/isolation.sh"

# -----------------------------------------------------------------------------
# mux_env -- Print the detected environment ("cmux", "tmux", or "none")
# -----------------------------------------------------------------------------
mux_env() {
  detect_environment
}

# -----------------------------------------------------------------------------
# mux_command -- Translate a tmux subcommand into the environment-appropriate
#                command string.
#
# Args:
#   $1      tmux subcommand (e.g. "split-window")
#   $2..$N  arguments to the subcommand
#
# Stdout:
#   The executable command string
#
# Returns:
#   0 on success, 1 on error
# -----------------------------------------------------------------------------
mux_command() {
  if [[ $# -eq 0 ]]; then
    log_error "mux_command: no subcommand provided"
    return 1
  fi

  local env
  env=$(detect_environment)

  case "$env" in
    cmux)
      # Translate tmux command to cmux equivalent
      map_command "$@"
      ;;
    tmux)
      # Pass through as native tmux command
      echo "tmux $*"
      ;;
    none)
      log_error "mux_command: no multiplexer detected (neither cmux nor tmux)"
      log_error "  Start a tmux session or run inside cmux to use panel operations."
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# mux_create_panel -- Create an isolated panel for an agent
#
# Args:
#   $1  agent_id   -- unique agent identifier
#   $2  direction  -- "v" (vertical, default) or "h" (horizontal)
#
# Stdout:
#   The panel handle
#
# Returns:
#   0 on success, 1 on error
# -----------------------------------------------------------------------------
mux_create_panel() {
  local agent_id="${1:-}"
  local direction="${2:-v}"

  if [[ -z "$agent_id" ]]; then
    log_error "mux_create_panel: agent_id required"
    return 1
  fi

  local env
  env=$(detect_environment)

  if [[ "$env" == "none" ]]; then
    log_error "mux_create_panel: no multiplexer detected"
    return 1
  fi

  # Create the panel in the isolation registry
  create_agent_panel "$agent_id" "$direction"
}

# -----------------------------------------------------------------------------
# mux_destroy_panel -- Destroy an agent's panel
#
# Args:
#   $1  agent_id -- the agent whose panel to destroy
#
# Stdout:
#   The destroyed panel handle
#
# Returns:
#   0 on success, 1 if not found
# -----------------------------------------------------------------------------
mux_destroy_panel() {
  local agent_id="${1:-}"

  if [[ -z "$agent_id" ]]; then
    log_error "mux_destroy_panel: agent_id required"
    return 1
  fi

  destroy_agent_panel "$agent_id"
}

# -----------------------------------------------------------------------------
# mux_send -- Send text to an agent's panel
#
# Args:
#   $1  agent_id -- target agent
#   $2  text     -- text to send
#
# Stdout:
#   The executable send command
#
# Returns:
#   0 on success, 1 on error
# -----------------------------------------------------------------------------
mux_send() {
  local agent_id="${1:-}"
  local text="${2:-}"

  if [[ -z "$agent_id" ]]; then
    log_error "mux_send: agent_id required"
    return 1
  fi

  local handle
  handle=$(get_agent_panel "$agent_id") || {
    log_error "mux_send: no panel found for agent '$agent_id'"
    return 1
  }

  local env
  env=$(detect_environment)

  case "$env" in
    cmux)
      # Extract identifier from handle (everything after first colon)
      local surface="${handle#*:}"
      echo "cmux send -s ${surface} ${text}"
      ;;
    tmux)
      local pane="${handle#*:}"
      echo "tmux send-keys -t ${pane} ${text}"
      ;;
    none)
      log_error "mux_send: no multiplexer detected"
      return 1
      ;;
  esac
}

# -----------------------------------------------------------------------------
# mux_list -- List all panels/panes in the current environment
#
# Stdout:
#   The executable list command, or agent panel listing
#
# Returns:
#   0 always
# -----------------------------------------------------------------------------
mux_list() {
  local env
  env=$(detect_environment)

  case "$env" in
    cmux)
      echo "cmux list-panes"
      ;;
    tmux)
      echo "tmux list-panes"
      ;;
    none)
      # Fall back to showing registered agent panels
      list_agent_panels
      ;;
  esac
}
