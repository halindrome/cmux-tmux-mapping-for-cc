#!/usr/bin/env bash
# =============================================================================
# test-id-map-registry.sh -- Tests for file-based pane-to-surface registry
#
# Tests registry persistence, atomic pane counter, and fallback from in-memory
# to file-based lookups.
# =============================================================================

# Each test gets its own temp registry dir.
# Sets CMUX_REGISTRY_DIR in the caller's scope and re-sources id-map.sh.
_setup_registry_test() {
  CMUX_REGISTRY_DIR="$(mktemp -d)"
  export CMUX_REGISTRY_DIR
  _CMUX_ID_MAP_LOADED=""
  source "${PROJECT_ROOT}/lib/id-map.sh"
}

_cleanup_registry() {
  [[ -n "${CMUX_REGISTRY_DIR:-}" && -d "$CMUX_REGISTRY_DIR" ]] && rm -rf "$CMUX_REGISTRY_DIR"
}

# --- Test: registry_init creates dirs ---
test_registry_init_creates_dirs() {
  _setup_registry_test

  registry_init

  local rc=0
  [[ -d "${CMUX_REGISTRY_DIR}/pane-to-surface" && -d "${CMUX_REGISTRY_DIR}/surface-to-pane" ]] || rc=1
  assert_ok "$rc" "test_registry_init_creates_dirs"

  _cleanup_registry
}
test_registry_init_creates_dirs

# --- Test: registry_register and lookup both directions ---
test_registry_register_and_lookup() {
  _setup_registry_test

  registry_register "%0" "surface-abc" 2>/dev/null
  local rc=$?
  assert_ok "$rc" "test_registry_register_and_lookup (register)"

  local surface
  surface="$(registry_lookup_surface "%0")"
  assert_eq "surface-abc" "$surface" "test_registry_register_and_lookup (forward)"

  local pane
  pane="$(registry_lookup_pane "surface-abc")"
  assert_eq "%0" "$pane" "test_registry_register_and_lookup (reverse)"

  _cleanup_registry
}
test_registry_register_and_lookup

# --- Test: registry_remove ---
test_registry_remove() {
  _setup_registry_test

  registry_register "%0" "surface-abc"

  registry_remove "%0"

  local rc=0
  registry_lookup_surface "%0" 2>/dev/null || rc=$?
  assert_fail "$rc" "test_registry_remove (forward lookup fails)"

  rc=0
  registry_lookup_pane "surface-abc" 2>/dev/null || rc=$?
  assert_fail "$rc" "test_registry_remove (reverse lookup fails)"

  _cleanup_registry
}
test_registry_remove

# --- Test: registry_list ---
test_registry_list() {
  _setup_registry_test

  registry_register "%0" "surface-aaa"
  registry_register "%1" "surface-bbb"
  registry_register "%2" "surface-ccc"

  local output
  output="$(registry_list | sort)"

  assert_contains "$output" "%0 surface-aaa" "test_registry_list (entry 0)"
  assert_contains "$output" "%1 surface-bbb" "test_registry_list (entry 1)"
  assert_contains "$output" "%2 surface-ccc" "test_registry_list (entry 2)"

  _cleanup_registry
}
test_registry_list

# --- Test: registry_clear ---
test_registry_clear() {
  _setup_registry_test

  registry_register "%0" "surface-aaa"
  registry_register "%1" "surface-bbb"

  registry_clear

  local output
  output="$(registry_list)"
  assert_eq "" "$output" "test_registry_clear (list empty after clear)"

  _cleanup_registry
}
test_registry_clear

# --- Test: next_pane_id sequential ---
test_next_pane_id_sequential() {
  _setup_registry_test

  local id1 id2 id3
  id1="$(next_pane_id)"
  id2="$(next_pane_id)"
  id3="$(next_pane_id)"

  assert_eq "%0" "$id1" "test_next_pane_id_sequential (%0)"
  assert_eq "%1" "$id2" "test_next_pane_id_sequential (%1)"
  assert_eq "%2" "$id3" "test_next_pane_id_sequential (%2)"

  _cleanup_registry
}
test_next_pane_id_sequential

# --- Test: next_pane_id persists across subshells ---
test_next_pane_id_persists() {
  local dir
  dir="$(mktemp -d)"

  # Call next_pane_id in a subshell (separate process)
  local id1
  id1="$(CMUX_REGISTRY_DIR="$dir" bash -c '
    source "'"${PROJECT_ROOT}"'/lib/id-map.sh"
    next_pane_id
  ')"

  # Call again in another subshell — counter should persist
  local id2
  id2="$(CMUX_REGISTRY_DIR="$dir" bash -c '
    source "'"${PROJECT_ROOT}"'/lib/id-map.sh"
    next_pane_id
  ')"

  assert_eq "%0" "$id1" "test_next_pane_id_persists (first subshell %0)"
  assert_eq "%1" "$id2" "test_next_pane_id_persists (second subshell %1)"

  rm -rf "$dir"
}
test_next_pane_id_persists

# --- Test: fallback to file when not in memory ---
test_fallback_to_file() {
  _setup_registry_test

  # Register directly via file-based registry (not through register_mapping)
  registry_register "%5" "surface-file-only"

  # Clear in-memory maps to ensure they're empty
  _CMUX_ID_MAP=()
  _CMUX_ID_MAP_REVERSE=()

  # tmux_target_to_cmux should fall back to file registry
  local surface
  surface="$(tmux_target_to_cmux "%5" 2>/dev/null)"
  assert_eq "surface-file-only" "$surface" "test_fallback_to_file (forward via file)"

  # cmux_to_tmux_target should also fall back
  local pane
  pane="$(cmux_to_tmux_target "surface-file-only" 2>/dev/null)"
  assert_eq "%5" "$pane" "test_fallback_to_file (reverse via file)"

  _cleanup_registry
}
test_fallback_to_file
