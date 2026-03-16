#!/usr/bin/env bash
# ==============================================================================
# commands.sh — tmux-to-cmux command translation functions
#
# Purpose:
#   Provides mapping functions that translate tmux operations into equivalent
#   cmux command strings. Each function parses tmux-style arguments and returns
#   (via stdout) the equivalent cmux command. Functions do NOT execute commands —
#   they return the translated command string for the caller to execute.
#
# Relationship:
#   Sources lib/id-map.sh for identifier translation.
#   Consumed by lib/mapper.sh (the unified entry point).
#
# Public API:
#   map_split_window  [...args]  — tmux split-window -> cmux new-split
#   map_send_keys     [...args]  — tmux send-keys    -> cmux send
#   map_select_pane   [...args]  — tmux select-pane  -> cmux select-surface
#   map_kill_pane     [...args]  — tmux kill-pane     -> cmux close-surface
#   map_list_panes    [...args]  — tmux list-panes    -> cmux list-panes
#   map_new_session   [...args]  — tmux new-session   -> cmux new-workspace
#   map_kill_session  [...args]  — tmux kill-session  -> cmux close-workspace
#   map_command       cmd_string — Dispatcher: full tmux command -> appropriate mapper
#
# All functions:
#   - Print the cmux command string to stdout
#   - Return 0 on success, 1 on error
#   - Log warnings to stderr for unsupported flags (do not fail)
#
# Example:
#   source lib/commands.sh
#   map_split_window -v                    # prints: cmux new-split -v
#   map_send_keys -t "sess:0.1" "ls" Enter # prints: cmux send -s surface-id ls Enter
#   map_command "split-window -h"          # prints: cmux new-split -h
# ==============================================================================

# Guard against double-sourcing
[[ -n "${_CMUX_COMMANDS_LOADED:-}" ]] && return 0
_CMUX_COMMANDS_LOADED=1

set -euo pipefail

# Source core.sh if available (may not exist yet during parallel builds)
_COMMANDS_DIR="${BASH_SOURCE[0]%/*}"
[[ -f "${_COMMANDS_DIR}/core.sh" ]] && source "${_COMMANDS_DIR}/core.sh"

# Source id-map.sh for target translation
if [[ -f "${_COMMANDS_DIR}/id-map.sh" ]]; then
  source "${_COMMANDS_DIR}/id-map.sh"
fi

# --- Internal helpers ---

# _cmux_warn(message)
#   Log a warning to stderr. Uses log_warn from core.sh if available.
_cmux_warn() {
  if declare -f log_warn &>/dev/null; then
    log_warn "$1"
  else
    echo "[warn] $1" >&2
  fi
}

# _resolve_target(tmux_target)
#   Resolve a tmux target to a cmux surface ID via id-map.
#   Resolution chain: in-memory map -> file-based registry -> raw passthrough.
#   Handles %N format targets for registry lookup.
_resolve_target() {
  local target="${1:-}"
  if [[ -z "$target" ]]; then
    return 0
  fi

  # 1. Try in-memory lookup (tmux_target_to_cmux includes file fallback)
  if declare -f tmux_target_to_cmux &>/dev/null; then
    local surface
    if surface="$(tmux_target_to_cmux "$target" 2>/dev/null)"; then
      echo "$surface"
      return 0
    fi
  fi

  # 2. Try file-based registry directly (for shim use where in-memory may be empty)
  if declare -f registry_lookup_surface &>/dev/null && [[ -n "${CMUX_REGISTRY_DIR:-}" ]]; then
    local surface
    if surface="$(registry_lookup_surface "$target" 2>/dev/null)" && [[ -n "$surface" ]]; then
      echo "$surface"
      return 0
    fi
  fi

  # 3. Fall back to raw target string
  echo "$target"
}

# --- Public mapping functions ---

# map_split_window(...args)
#   Parse tmux split-window args and return cmux new-split command.
#   Supported flags: -v (vertical), -h (horizontal), -p N (percentage),
#                    -t target, -c /path (working directory)
map_split_window() {
  local direction=""
  local target=""
  local percentage=""
  local directory=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v) direction="-v"; shift ;;
      -h) direction="-h"; shift ;;
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "split-window: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      -p)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "split-window: -p requires a percentage argument"
          shift; continue
        fi
        percentage="$2"; shift 2 ;;
      -c)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "split-window: -c requires a directory argument"
          shift; continue
        fi
        directory="$2"; shift 2 ;;
      *)
        _cmux_warn "split-window: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  # Map tmux -v/-h flags to cmux positional direction (down/right)
  local cmux_dir="down"
  if [[ "$direction" == "-h" ]]; then
    cmux_dir="right"
  fi

  local cmd="cmux new-split $cmux_dir"
  if [[ -n "$percentage" ]]; then
    _cmux_warn "split-window: -p (percentage) may not be supported by cmux, passing as hint"
    cmd+=" -p $percentage"
  fi
  if [[ -n "$directory" ]]; then
    cmd+=" -c $directory"
  fi

  echo "$cmd"
  return 0
}

# map_send_keys(...args)
#   Parse tmux send-keys args and return cmux send command.
#   Supported: -t target, -l (literal flag), text arguments, special keys (Enter, C-c)
map_send_keys() {
  local target=""
  local literal=false
  local -a text_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "send-keys: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      -l)
        literal=true; shift ;;
      *)
        text_args+=("$1"); shift ;;
    esac
  done

  if [[ ${#text_args[@]} -eq 0 ]]; then
    echo "map_send_keys: no text or keys provided" >&2
    return 1
  fi

  local surface=""
  if [[ -n "$target" ]]; then
    surface="$(_resolve_target "$target")"
  fi

  local cmd="cmux send"
  [[ -n "$surface" ]] && cmd+=" -s $surface"
  if [[ "$literal" == true ]]; then
    _cmux_warn "send-keys: -l (literal) flag noted; cmux send may handle escaping differently"
  fi

  # Append all text/key arguments
  local arg
  for arg in "${text_args[@]}"; do
    cmd+=" $arg"
  done

  echo "$cmd"
  return 0
}

# map_select_pane(...args)
#   Parse tmux select-pane args and return cmux select-surface command.
#   Supported: -t target. Directional flags (-U/-D/-L/-R) produce warnings.
map_select_pane() {
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "select-pane: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      -U|-D|-L|-R)
        _cmux_warn "select-pane: directional flag '$1' not supported in cmux, ignoring"
        shift ;;
      -e)
        # tmux enable-input flag, not applicable to cmux
        shift ;;
      *)
        _cmux_warn "select-pane: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  if [[ -z "$target" ]]; then
    echo "map_select_pane: no target specified (use -t)" >&2
    return 1
  fi

  local surface
  surface="$(_resolve_target "$target")"

  echo "cmux select-surface $surface"
  return 0
}

# map_kill_pane(...args)
#   Parse tmux kill-pane args and return cmux close-surface command.
#   Supported: -t target
map_kill_pane() {
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "kill-pane: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      *)
        _cmux_warn "kill-pane: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  if [[ -z "$target" ]]; then
    echo "map_kill_pane: no target specified (use -t)" >&2
    return 1
  fi

  local surface
  surface="$(_resolve_target "$target")"

  echo "cmux close-surface $surface"
  return 0
}

# map_list_panes(...args)
#   Parse tmux list-panes args and return cmux list-panes command.
#   Supported: -t target, -F format (warns that cmux format differs)
map_list_panes() {
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "list-panes: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      -F)
        if [[ $# -lt 2 ]]; then
          shift; continue
        fi
        _cmux_warn "list-panes: -F (format) not supported in cmux; cmux list-panes uses its own output format"
        shift 2 ;;
      *)
        _cmux_warn "list-panes: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  echo "cmux list-panes"
  return 0
}

# map_new_session(...args)
#   Parse tmux new-session args and return cmux new-workspace command.
#   Supported: -d (detach), -s name, -c directory
map_new_session() {
  local name=""
  local directory=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d)
        # tmux detach flag; cmux workspaces are always "detached" in the tmux sense
        shift ;;
      -s)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "new-session: -s requires a session name"
          shift; continue
        fi
        name="$2"; shift 2 ;;
      -c)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "new-session: -c requires a directory argument"
          shift; continue
        fi
        directory="$2"; shift 2 ;;
      *)
        _cmux_warn "new-session: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  local cmd="cmux new-workspace"
  [[ -n "$name" ]] && cmd+=" --name $name"
  [[ -n "$directory" ]] && cmd+=" -c $directory"

  echo "$cmd"
  return 0
}

# map_kill_session(...args)
#   Parse tmux kill-session args and return cmux close-workspace command.
#   Supported: -t name
map_kill_session() {
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t)
        if [[ $# -lt 2 ]]; then
          _cmux_warn "kill-session: -t requires a target argument"
          shift; continue
        fi
        target="$2"; shift 2 ;;
      *)
        _cmux_warn "kill-session: unrecognized flag '$1', ignoring"
        shift ;;
    esac
  done

  if [[ -z "$target" ]]; then
    echo "map_kill_session: no target specified (use -t)" >&2
    return 1
  fi

  echo "cmux close-workspace $target"
  return 0
}

# map_command(tmux_command_string)
#   Dispatcher: takes a full tmux command string (subcommand + args),
#   identifies the subcommand, and delegates to the appropriate map_* function.
#   Args:
#     $1..$N — the tmux subcommand and its arguments (either as a single string
#              or as separate arguments)
#   Returns: 0 on success, 1 on unrecognized command
map_command() {
  # If called with a single string, split it into words
  local -a args
  if [[ $# -eq 1 ]]; then
    read -ra args <<< "$1"
  else
    args=("$@")
  fi

  if [[ ${#args[@]} -eq 0 ]]; then
    echo "map_command: no command provided" >&2
    return 1
  fi

  local subcmd="${args[0]}"
  local -a rest=("${args[@]:1}")

  case "$subcmd" in
    split-window)   map_split_window "${rest[@]+"${rest[@]}"}" ;;
    send-keys)      map_send_keys "${rest[@]+"${rest[@]}"}" ;;
    select-pane)    map_select_pane "${rest[@]+"${rest[@]}"}" ;;
    kill-pane)      map_kill_pane "${rest[@]+"${rest[@]}"}" ;;
    list-panes)     map_list_panes "${rest[@]+"${rest[@]}"}" ;;
    new-session)    map_new_session "${rest[@]+"${rest[@]}"}" ;;
    kill-session)   map_kill_session "${rest[@]+"${rest[@]}"}" ;;
    new-window)     map_new_window    "${rest[@]+\"${rest[@]}\"}" ;;
    list-windows)   map_list_windows  "${rest[@]+\"${rest[@]}\"}" ;;
    select-layout)  map_select_layout "${rest[@]+\"${rest[@]}\"}" ;;
    resize-pane)    map_resize_pane   "${rest[@]+\"${rest[@]}\"}" ;;
    *)
      echo "map_command: unrecognized tmux command '$subcmd'" >&2
      return 1
      ;;
  esac
}

# map_new_window(...args)
map_new_window() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n) name="${2:-}"; shift 2 ;;
      -t|-F) shift 2 ;;
      -P) shift ;;
      *) shift ;;
    esac
  done
  local cmd="cmux new-split down"
  [[ -n "$name" ]] && cmd+=" --name $name"
  echo "$cmd"
  return 0
}

# map_list_windows(...args)
map_list_windows() {
  echo "claude"
  return 0
}

# map_select_layout(...args)
map_select_layout() {
  return 0
}

# map_resize_pane(...args)
map_resize_pane() {
  return 0
}
