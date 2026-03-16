#!/usr/bin/env bash
# =============================================================================
# test-shim.sh -- Unit tests for bin/tmux shim
#
# Tests the shim binary using stub scripts for cmux and real tmux.
# All tests run with CMUX_SHIM_ACTIVE=1 (shim mode) unless testing passthrough.
# =============================================================================

# --- Setup: create temp dir with stub binaries --------------------------------

_SHIM_TEST_DIR="$(mktemp -d)"
_STUB_DIR="${_SHIM_TEST_DIR}/stubs"
mkdir -p "$_STUB_DIR"

# System PATH needed for bash, env, date, id, etc.
# Put homebrew first so bash 4+ (needed for declare -gA in lib/) is found
_SYS_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# Create a stub "real tmux" that logs its invocation
cat > "${_STUB_DIR}/real-tmux" <<'STUB'
#!/usr/bin/env bash
echo "REAL_TMUX_CALLED: $*"
exit 0
STUB
chmod +x "${_STUB_DIR}/real-tmux"

# Create a stub cmux that returns surface IDs
cat > "${_STUB_DIR}/cmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  new-split)
    echo "surface-test-001"
    ;;
  identify)
    echo '{"surface_id":"surface-main"}'
    ;;
  list-surfaces)
    echo "surface-main"
    echo "surface-test-001"
    ;;
  send|send-surface|send-key-surface)
    echo "OK"
    ;;
  close-surface)
    echo "OK"
    ;;
  *)
    echo "cmux-stub: $*"
    ;;
esac
exit 0
STUB
chmod +x "${_STUB_DIR}/cmux"

# Registry dir for tests
_SHIM_REGISTRY="${_SHIM_TEST_DIR}/registry"
mkdir -p "$_SHIM_REGISTRY"

# Shim path
_SHIM_BIN="${PROJECT_ROOT}/bin/tmux"

# --- Cleanup ------------------------------------------------------------------

_shim_cleanup() {
  rm -rf "$_SHIM_TEST_DIR"
}
trap _shim_cleanup EXIT

# --- Tests --------------------------------------------------------------------

# test_shim_version: CMUX_SHIM_ACTIVE=1 bin/tmux -V outputs "tmux"
test_shim_version() {
  local out
  out=$(CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" -V 2>/dev/null)
  local rc=$?
  assert_ok "$rc" "shim -V exits 0"
  assert_contains "$out" "tmux" "shim -V output contains 'tmux'"
}
test_shim_version

# test_shim_info: CMUX_SHIM_ACTIVE=1 bin/tmux info outputs server info
test_shim_info() {
  local out
  out=$(CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" info 2>/dev/null)
  local rc=$?
  assert_ok "$rc" "shim info exits 0"
  assert_contains "$out" "server started" "shim info contains server info"
}
test_shim_info

# test_shim_display_message_pane_id
test_shim_display_message_pane_id() {
  local out
  out=$(TMUX_PANE=%0 CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" display-message -p '#{pane_id}' 2>/dev/null)
  local rc=$?
  assert_ok "$rc" "shim display-message exits 0"
  assert_eq "%0" "$out" "shim display-message returns TMUX_PANE value"
}
test_shim_display_message_pane_id

# test_shim_display_message_session_name
test_shim_display_message_session_name() {
  local out
  out=$(CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" display-message -p '#{session_name}' 2>/dev/null)
  local rc=$?
  assert_ok "$rc" "shim display-message session_name exits 0"
  assert_eq "cmux-shim" "$out" "shim display-message returns session name"
}
test_shim_display_message_session_name

# test_shim_list_sessions
test_shim_list_sessions() {
  local out
  out=$(CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" list-sessions 2>/dev/null)
  local rc=$?
  assert_ok "$rc" "shim list-sessions exits 0"
  assert_contains "$out" "cmux-shim" "shim list-sessions contains session name"
}
test_shim_list_sessions

# test_shim_has_session: returns 0 for any session name
test_shim_has_session() {
  CMUX_SHIM_ACTIVE=1 "$_SHIM_BIN" has-session -t foo 2>/dev/null
  local rc=$?
  assert_ok "$rc" "shim has-session returns 0"
}
test_shim_has_session

# test_shim_passthrough_real_tmux: Without CMUX_SHIM_ACTIVE, shim passes to real tmux
test_shim_passthrough_real_tmux() {
  local passthrough_dir="${_SHIM_TEST_DIR}/passthrough-bin"
  mkdir -p "$passthrough_dir"
  cp "${_STUB_DIR}/real-tmux" "${passthrough_dir}/tmux"
  chmod +x "${passthrough_dir}/tmux"

  local out
  # TMUX set, no CMUX_SHIM_ACTIVE => passthrough
  # Include system paths so env/bash can be found by the exec'd stub
  out=$(TMUX="/tmp/fake,1234,0" PATH="${PROJECT_ROOT}/bin:${passthrough_dir}:${_SYS_PATH}" \
        "$_SHIM_BIN" list-sessions 2>/dev/null) || true
  assert_contains "$out" "REAL_TMUX_CALLED" "passthrough calls real tmux stub"
}
test_shim_passthrough_real_tmux

# test_shim_no_op_when_real_tmux: TMUX set + no CMUX_SHIM_ACTIVE = passthrough
test_shim_no_op_when_real_tmux() {
  local passthrough_dir="${_SHIM_TEST_DIR}/passthrough-bin2"
  mkdir -p "$passthrough_dir"
  cp "${_STUB_DIR}/real-tmux" "${passthrough_dir}/tmux"
  chmod +x "${passthrough_dir}/tmux"

  local out
  out=$(TMUX="/tmp/fake,5678,0" PATH="${PROJECT_ROOT}/bin:${passthrough_dir}:${_SYS_PATH}" \
        "$_SHIM_BIN" -V 2>/dev/null) || true
  assert_contains "$out" "REAL_TMUX_CALLED" "real tmux session passes -V to real binary"
}
test_shim_no_op_when_real_tmux

# test_shim_unrecognized_fallback: Unrecognized command with no real tmux exits 1
test_shim_unrecognized_fallback() {
  # PATH excludes real tmux; CMUX_SHIM_NO_FALLBACK disables hardcoded paths
  # Build a PATH with system utils but without any tmux binary
  local safe_dir="${_SHIM_TEST_DIR}/safe-bin"
  mkdir -p "$safe_dir"
  # Symlink essential system utils (bash, env, etc.) but not tmux
  for util in bash env id date mkdir cat dirname rm; do
    local util_path
    util_path="$(command -v "$util" 2>/dev/null)" || true
    [[ -n "$util_path" && -x "$util_path" ]] && ln -sf "$util_path" "${safe_dir}/$util" 2>/dev/null || true
  done

  local out rc=0
  out=$(CMUX_SHIM_ACTIVE=1 CMUX_SHIM_NO_FALLBACK=1 PATH="${PROJECT_ROOT}/bin:${safe_dir}" \
        "$_SHIM_BIN" some-unknown-command 2>&1) || rc=$?
  assert_fail "$rc" "unrecognized command exits non-zero when no real tmux"
  assert_contains "$out" "unrecognized" "error message mentions unrecognized command"
}
test_shim_unrecognized_fallback

# test_shim_split_window: split-window dispatches through commands.sh
test_shim_split_window() {
  local reg_dir="${_SHIM_TEST_DIR}/split-registry"
  mkdir -p "$reg_dir"
  local out
  out=$(CMUX_SHIM_ACTIVE=1 CMUX_REGISTRY_DIR="$reg_dir" \
        PATH="${_STUB_DIR}:${PROJECT_ROOT}/bin:${_SYS_PATH}" \
        "$_SHIM_BIN" split-window -h 2>/dev/null) || true
  # Should output a pane ID like %N
  assert_contains "$out" "%" "split-window returns pane ID"
}
test_shim_split_window

# test_shim_send_keys: send-keys dispatches through commands.sh
test_shim_send_keys() {
  local out rc=0
  out=$(CMUX_SHIM_ACTIVE=1 CMUX_FORCE_ENV=cmux \
        PATH="${_STUB_DIR}:${PROJECT_ROOT}/bin:${_SYS_PATH}" \
        "$_SHIM_BIN" send-keys -t "%0" "ls" Enter 2>/dev/null) || rc=$?
  assert_ok "$rc" "send-keys exits 0"
}
test_shim_send_keys

# test_shim_kill_pane: kill-pane dispatches and cleans registry
test_shim_kill_pane() {
  local reg_dir="${_SHIM_TEST_DIR}/kill-registry"
  mkdir -p "$reg_dir"
  # Pre-populate registry entry
  echo "surface-to-kill" > "${reg_dir}/%5"

  local out rc=0
  out=$(CMUX_SHIM_ACTIVE=1 CMUX_REGISTRY_DIR="$reg_dir" \
        PATH="${_STUB_DIR}:${PROJECT_ROOT}/bin:${_SYS_PATH}" \
        "$_SHIM_BIN" kill-pane -t "%5" 2>/dev/null) || rc=$?
  assert_ok "$rc" "kill-pane exits 0"

  if [[ ! -f "${reg_dir}/%5" ]]; then
    assert_ok 0 "kill-pane removes registry entry"
  else
    assert_ok 1 "kill-pane removes registry entry"
  fi
}
test_shim_kill_pane
