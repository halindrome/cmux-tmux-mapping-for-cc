#!/usr/bin/env bash
# =============================================================================
# test-session-start-shim.sh -- Tests for TMUX faking in SessionStart hook
#
# Verifies that the hook correctly fakes TMUX/TMUX_PANE/CMUX_SHIM_ACTIVE
# when cmux is detected, skips faking when real tmux is present, and
# handles edge cases gracefully.
# =============================================================================

# ---------------------------------------------------------------------------
# Setup: create temp dirs and a stub cmux binary
# ---------------------------------------------------------------------------
_SHIM_TEST_TMPDIR="$(mktemp -d)"
_SHIM_TEST_ENV_FILE="${_SHIM_TEST_TMPDIR}/env_file"
_SHIM_TEST_STUB_DIR="${_SHIM_TEST_TMPDIR}/stub-bin"
mkdir -p "$_SHIM_TEST_STUB_DIR"

# Create stub cmux that succeeds
cat > "${_SHIM_TEST_STUB_DIR}/cmux" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "identify" ]]; then
  echo '{"surface_id":"surface-main"}'
fi
exit 0
STUB
chmod +x "${_SHIM_TEST_STUB_DIR}/cmux"

# Helper: run the hook with controlled environment
_run_shim_hook() {
  local extra_env=("$@")
  local rc=0
  # Reset env file
  > "$_SHIM_TEST_ENV_FILE"
  echo '{}' | env \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    CLAUDE_ENV_FILE="${_SHIM_TEST_ENV_FILE}" \
    CMUX_FORCE_ENV="${CMUX_FORCE_ENV:-none}" \
    PATH="${_SHIM_TEST_STUB_DIR}:${PATH}" \
    "${extra_env[@]}" \
    bash "${PROJECT_ROOT}/hooks/tmux-session-start.sh" 2>/dev/null || rc=$?
  return $rc
}

# Helper: run hook and capture stdout
_run_shim_hook_stdout() {
  local extra_env=("$@")
  local rc=0
  > "$_SHIM_TEST_ENV_FILE"
  local out
  out=$(echo '{}' | env \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    CLAUDE_ENV_FILE="${_SHIM_TEST_ENV_FILE}" \
    CMUX_FORCE_ENV="${CMUX_FORCE_ENV:-none}" \
    PATH="${_SHIM_TEST_STUB_DIR}:${PATH}" \
    "${extra_env[@]}" \
    bash "${PROJECT_ROOT}/hooks/tmux-session-start.sh" 2>/dev/null) || rc=$?
  echo "$out"
  return $rc
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# test_hook_fakes_tmux_when_cmux
# When cmux is in PATH and TMUX is not set, hook should write fake TMUX vars
(
  unset TMUX
  unset TMUX_PANE
  unset CMUX_SHIM_ACTIVE
  _run_shim_hook
)
_env_content="$(cat "$_SHIM_TEST_ENV_FILE")"
assert_contains "$_env_content" 'export TMUX="' "hook writes TMUX to env file when cmux detected"
assert_contains "$_env_content" 'export TMUX_PANE="%0"' "hook writes TMUX_PANE=%0 to env file"
assert_contains "$_env_content" 'export CMUX_SHIM_ACTIVE=1' "hook writes CMUX_SHIM_ACTIVE=1 to env file"

# test_hook_noop_when_real_tmux
# When TMUX is already set, hook should NOT write CMUX_SHIM_ACTIVE
> "$_SHIM_TEST_ENV_FILE"
(
  _run_shim_hook TMUX="/tmp/tmux-1000/default,12345,0"
)
_env_content="$(cat "$_SHIM_TEST_ENV_FILE")"
# Should have CLAUDE_MUXER but NOT CMUX_SHIM_ACTIVE
assert_contains "$_env_content" 'CLAUDE_MUXER' "hook still writes CLAUDE_MUXER when real tmux"
# CMUX_SHIM_ACTIVE should NOT be present
if [[ "$_env_content" == *"CMUX_SHIM_ACTIVE"* ]]; then
  _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
  printf "  ${RED:-}FAIL${RESET:-} hook does NOT write CMUX_SHIM_ACTIVE when real tmux\n"
  printf "    env file contained CMUX_SHIM_ACTIVE but should not\n"
else
  _PASS_COUNT=$(( _PASS_COUNT + 1 ))
  printf "  ${GREEN:-}PASS${RESET:-} hook does NOT write CMUX_SHIM_ACTIVE when real tmux\n"
fi

# test_hook_noop_when_no_cmux
# When cmux is NOT in PATH and TMUX is not set, no faking should occur
> "$_SHIM_TEST_ENV_FILE"
(
  unset TMUX
  # Use a PATH that does NOT include our stub cmux
  echo '{}' | env \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    CLAUDE_ENV_FILE="${_SHIM_TEST_ENV_FILE}" \
    CMUX_FORCE_ENV="none" \
    PATH="/usr/bin:/bin" \
    bash "${PROJECT_ROOT}/hooks/tmux-session-start.sh" 2>/dev/null || true
)
_env_content="$(cat "$_SHIM_TEST_ENV_FILE")"
if [[ "$_env_content" == *"CMUX_SHIM_ACTIVE"* ]]; then
  _FAIL_COUNT=$(( _FAIL_COUNT + 1 ))
  printf "  ${RED:-}FAIL${RESET:-} hook does NOT fake tmux when no cmux available\n"
  printf "    env file contained CMUX_SHIM_ACTIVE but should not\n"
else
  _PASS_COUNT=$(( _PASS_COUNT + 1 ))
  printf "  ${GREEN:-}PASS${RESET:-} hook does NOT fake tmux when no cmux available\n"
fi

# test_hook_exits_zero_always
# Hook must exit 0 even with missing CLAUDE_ENV_FILE
_rc=0
(
  unset TMUX
  echo '{}' | env \
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    CMUX_FORCE_ENV="none" \
    PATH="${_SHIM_TEST_STUB_DIR}:${PATH}" \
    bash "${PROJECT_ROOT}/hooks/tmux-session-start.sh" 2>/dev/null
) || _rc=$?
assert_eq "0" "$_rc" "hook exits 0 even without CLAUDE_ENV_FILE"

# Run with bogus plugin root -- should still exit 0 due to trap
_rc=0
(
  echo '{}' | env \
    CLAUDE_PLUGIN_ROOT="/nonexistent" \
    CLAUDE_ENV_FILE="${_SHIM_TEST_ENV_FILE}" \
    CMUX_FORCE_ENV="none" \
    PATH="/usr/bin:/bin" \
    bash "${PROJECT_ROOT}/hooks/tmux-session-start.sh" 2>/dev/null
) || _rc=$?
assert_eq "0" "$_rc" "hook exits 0 with bogus CLAUDE_PLUGIN_ROOT"

# test_hook_sets_registry_dir
# Verify CMUX_REGISTRY_DIR is written to env file
> "$_SHIM_TEST_ENV_FILE"
(
  unset TMUX
  unset CMUX_SHIM_ACTIVE
  _run_shim_hook
)
_env_content="$(cat "$_SHIM_TEST_ENV_FILE")"
assert_contains "$_env_content" 'export CMUX_REGISTRY_DIR=' "hook writes CMUX_REGISTRY_DIR to env file"

# test_hook_prepends_bin_to_path
# Verify PATH in env file starts with bin/ directory
assert_contains "$_env_content" 'export PATH="' "hook writes PATH to env file"
assert_contains "$_env_content" '/bin:$PATH' "hook prepends bin/ directory to PATH"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$_SHIM_TEST_TMPDIR"
