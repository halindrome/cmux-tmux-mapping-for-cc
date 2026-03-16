#!/usr/bin/env bash
# =============================================================================
# test-shim-integration.sh -- End-to-end integration tests
#
# Full workflow tests: hook -> shim -> cmux translation -> registry tracking.
# Uses a stub cmux binary and the real shim + library code.
# =============================================================================

# --- Setup -------------------------------------------------------------------

_E2E_DIR="$(mktemp -d)"
_E2E_STUB_DIR="${_E2E_DIR}/stubs"
_E2E_LOG="${_E2E_DIR}/cmux-calls.log"
mkdir -p "$_E2E_STUB_DIR"

# System PATH for bash, env, id, date, etc.
_E2E_SYS_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Stub cmux that logs calls and returns predictable surface IDs
# Uses a counter file to generate unique surface IDs per new-split call
cat > "${_E2E_STUB_DIR}/cmux" <<'STUB'
#!/usr/bin/env bash
_LOG="${CMUX_CALL_LOG:-/dev/null}"
_COUNTER_FILE="${CMUX_SURFACE_COUNTER:-/tmp/cmux-stub-counter}"

_next_surface() {
  local n=0
  if [[ -f "$_COUNTER_FILE" ]]; then
    n=$(<"$_COUNTER_FILE")
  fi
  n=$((n + 1))
  echo "$n" > "$_COUNTER_FILE"
  printf 'surface-test-%03d' "$n"
}

echo "CMUX_CALL: $*" >> "$_LOG"
case "$1" in
  new-split)
    _next_surface
    ;;
  send|send-surface)
    echo "OK"
    ;;
  send-key-surface)
    echo "OK"
    ;;
  close-surface)
    echo "OK"
    ;;
  identify)
    echo '{"surface_id":"surface-main"}'
    ;;
  list-surfaces)
    echo "surface-main"
    ;;
  *)
    echo "cmux-stub: $*"
    ;;
esac
exit 0
STUB
chmod +x "${_E2E_STUB_DIR}/cmux"

# Common env for all e2e tests
_e2e_env() {
  local reg_dir="$1"
  # Reset the stub surface counter for each test
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  rm -f "$counter_file"
  echo "CMUX_SHIM_ACTIVE=1"
  echo "CMUX_REGISTRY_DIR=$reg_dir"
  echo "CMUX_SHIM_NO_FALLBACK=1"
  echo "CMUX_CALL_LOG=$_E2E_LOG"
  echo "CMUX_SURFACE_COUNTER=$counter_file"
  echo "PATH=${_E2E_STUB_DIR}:${PROJECT_ROOT}/bin:${_E2E_SYS_PATH}"
}

_run_shim() {
  local reg_dir="$1"
  shift
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  CMUX_SHIM_ACTIVE=1 \
  CMUX_REGISTRY_DIR="$reg_dir" \
  CMUX_SHIM_NO_FALLBACK=1 \
  CMUX_CALL_LOG="$_E2E_LOG" \
  CMUX_SURFACE_COUNTER="$counter_file" \
  PATH="${_E2E_STUB_DIR}:${PROJECT_ROOT}/bin:${_E2E_SYS_PATH}" \
  "$PROJECT_ROOT/bin/tmux" "$@" 2>/dev/null
}

# --- Cleanup -----------------------------------------------------------------

_e2e_cleanup() {
  rm -rf "$_E2E_DIR"
}
trap _e2e_cleanup EXIT

# --- Test: split-window creates surface and registers mapping ----------------

test_e2e_split_creates_surface() {
  local reg_dir="${_E2E_DIR}/reg-split"
  mkdir -p "$reg_dir"
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  rm -f "$counter_file"

  local out
  out=$(_run_shim "$reg_dir" split-window -h)
  local rc=$?
  assert_ok "$rc" "e2e split-window exits 0"
  assert_contains "$out" "%" "e2e split-window returns pane ID"

  # Verify registry entry exists (shim uses flat file: reg_dir/pane_id)
  local pane_id
  pane_id="$(echo "$out" | tr -d '[:space:]')"
  if [[ -f "${reg_dir}/${pane_id}" ]]; then
    local surface
    surface="$(<"${reg_dir}/${pane_id}")"
    assert_contains "$surface" "surface-test-" "e2e split-window registers surface in registry"
  else
    assert_ok 1 "e2e split-window creates registry entry for ${pane_id}"
  fi
}
test_e2e_split_creates_surface

# --- Test: send-keys routes to correct surface via registry ------------------

test_e2e_send_keys_routes_to_surface() {
  local reg_dir="${_E2E_DIR}/reg-send"
  mkdir -p "$reg_dir"
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  rm -f "$counter_file"
  > "$_E2E_LOG"

  # First split to create a pane
  local pane_id
  pane_id=$(_run_shim "$reg_dir" split-window -h)
  pane_id="$(echo "$pane_id" | tr -d '[:space:]')"

  # Now send keys to that pane
  > "$_E2E_LOG"
  _run_shim "$reg_dir" send-keys -t "$pane_id" "ls" Enter
  local rc=$?
  assert_ok "$rc" "e2e send-keys exits 0"

  # Verify cmux was called with send command
  local log_content
  log_content="$(<"$_E2E_LOG")"
  assert_contains "$log_content" "CMUX_CALL:" "e2e send-keys invokes cmux stub"
}
test_e2e_send_keys_routes_to_surface

# --- Test: kill-pane cleans up registry --------------------------------------

test_e2e_kill_pane_cleans_registry() {
  local reg_dir="${_E2E_DIR}/reg-kill"
  mkdir -p "$reg_dir"
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  rm -f "$counter_file"

  # Split to create a pane
  local pane_id
  pane_id=$(_run_shim "$reg_dir" split-window -h)
  pane_id="$(echo "$pane_id" | tr -d '[:space:]')"

  # Verify registry entry exists
  if [[ -f "${reg_dir}/${pane_id}" ]]; then
    assert_ok 0 "e2e kill-pane: registry entry exists before kill"
  else
    assert_ok 1 "e2e kill-pane: registry entry exists before kill"
  fi

  # Kill the pane
  _run_shim "$reg_dir" kill-pane -t "$pane_id"
  local rc=$?
  assert_ok "$rc" "e2e kill-pane exits 0"

  # Verify registry entry removed
  if [[ ! -f "${reg_dir}/${pane_id}" ]]; then
    assert_ok 0 "e2e kill-pane removes registry entry"
  else
    assert_ok 1 "e2e kill-pane removes registry entry"
  fi
}
test_e2e_kill_pane_cleans_registry

# --- Test: display-message returns pane ID -----------------------------------

test_e2e_display_message_returns_pane() {
  local reg_dir="${_E2E_DIR}/reg-dm"
  mkdir -p "$reg_dir"

  local out
  out=$(TMUX_PANE=%0 _run_shim "$reg_dir" display-message -p '#{pane_id}')
  local rc=$?
  assert_ok "$rc" "e2e display-message exits 0"
  assert_eq "%0" "$out" "e2e display-message returns correct pane ID"
}
test_e2e_display_message_returns_pane

# --- Test: full agent workflow (split 3, send to each, kill all) -------------

test_e2e_full_agent_workflow() {
  local reg_dir="${_E2E_DIR}/reg-full"
  mkdir -p "$reg_dir"
  local counter_file="${_E2E_DIR}/surface-counter-$$"
  rm -f "$counter_file"
  > "$_E2E_LOG"

  # Split 3 panes
  local pane1 pane2 pane3
  pane1=$(_run_shim "$reg_dir" split-window -h)
  pane1="$(echo "$pane1" | tr -d '[:space:]')"
  pane2=$(_run_shim "$reg_dir" split-window -v)
  pane2="$(echo "$pane2" | tr -d '[:space:]')"
  pane3=$(_run_shim "$reg_dir" split-window -h)
  pane3="$(echo "$pane3" | tr -d '[:space:]')"

  # Verify all 3 panes are registered
  local count=0
  [[ -f "${reg_dir}/${pane1}" ]] && count=$((count + 1))
  [[ -f "${reg_dir}/${pane2}" ]] && count=$((count + 1))
  [[ -f "${reg_dir}/${pane3}" ]] && count=$((count + 1))
  assert_eq "3" "$count" "e2e full workflow: 3 panes registered"

  # Send keys to each pane
  > "$_E2E_LOG"
  _run_shim "$reg_dir" send-keys -t "$pane1" "echo hello1" Enter
  _run_shim "$reg_dir" send-keys -t "$pane2" "echo hello2" Enter
  _run_shim "$reg_dir" send-keys -t "$pane3" "echo hello3" Enter

  local log_content
  log_content="$(<"$_E2E_LOG")"
  # Count cmux send calls (each send-keys produces at least one CMUX_CALL)
  local send_count
  send_count=$(echo "$log_content" | grep -c "CMUX_CALL:" || true)
  if [[ "$send_count" -ge 3 ]]; then
    assert_ok 0 "e2e full workflow: 3 send-keys dispatched to cmux"
  else
    assert_ok 1 "e2e full workflow: 3 send-keys dispatched to cmux (got $send_count)"
  fi

  # Kill all panes
  _run_shim "$reg_dir" kill-pane -t "$pane1"
  _run_shim "$reg_dir" kill-pane -t "$pane2"
  _run_shim "$reg_dir" kill-pane -t "$pane3"

  # Verify registry is empty
  local remaining=0
  [[ -f "${reg_dir}/${pane1}" ]] && remaining=$((remaining + 1))
  [[ -f "${reg_dir}/${pane2}" ]] && remaining=$((remaining + 1))
  [[ -f "${reg_dir}/${pane3}" ]] && remaining=$((remaining + 1))
  assert_eq "0" "$remaining" "e2e full workflow: all registry entries cleaned"
}
test_e2e_full_agent_workflow

# --- Test: resolve_target uses registry for %N targets -----------------------

test_e2e_resolve_target_registry() {
  local reg_dir="${_E2E_DIR}/reg-resolve"
  mkdir -p "$reg_dir"

  # Source id-map with this registry
  _CMUX_ID_MAP_LOADED=""
  CMUX_REGISTRY_DIR="$reg_dir"
  source "${PROJECT_ROOT}/lib/id-map.sh"

  # Also re-source commands.sh to pick up updated _resolve_target
  _CMUX_COMMANDS_LOADED=""
  source "${PROJECT_ROOT}/lib/commands.sh"

  # Register a mapping in the file-based registry
  registry_register "%7" "surface-resolve-test"

  # Clear in-memory maps so _resolve_target must use file-based fallback
  _CMUX_ID_MAP=()
  _CMUX_ID_MAP_REVERSE=()

  local resolved
  resolved="$(_resolve_target "%7")"
  assert_eq "surface-resolve-test" "$resolved" "e2e _resolve_target resolves %N via file registry"

  # Cleanup
  registry_clear
}
test_e2e_resolve_target_registry
