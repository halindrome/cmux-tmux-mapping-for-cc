#!/usr/bin/env bash
# agent-tmux-cleanup.sh — SubagentStop hook for panel teardown
#
# Pops the oldest surface ref from the session-scoped queue and closes it.
# Best-effort cleanup — always exits 0.
#
# Hook event: SubagentStop
# Input: JSON on stdin with session_id, agent_id
set -euo pipefail

trap 'exit 0' ERR

# Read JSON input from stdin
INPUT=$(cat)

# Parse session_id — this is the shared key between creation and cleanup
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null || echo "unknown")
AGENT_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('agent_id','unknown'))" 2>/dev/null || echo "unknown")

QUEUE_FILE="/tmp/cmux-agent-surfaces-${SESSION_ID}"
PARENT_FILE="/tmp/cmux-session-${SESSION_ID}"
PARENT_SURFACE=$(cat "$PARENT_FILE" 2>/dev/null || true)

if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "cmux-mapper: no surface queue for session '$SESSION_ID', skipping cleanup" >&2
  exit 0
fi

# Pop the first surface ref from the queue (FIFO)
SURFACE_REF=$(head -1 "$QUEUE_FILE" 2>/dev/null || true)

if [[ -z "$SURFACE_REF" ]]; then
  echo "cmux-mapper: surface queue empty for session '$SESSION_ID'" >&2
  exit 0
fi

# Remove the first line from the queue
tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

# Safety guard: never close the CC parent surface
if [[ -n "$PARENT_SURFACE" && "$SURFACE_REF" == "$PARENT_SURFACE" ]]; then
  echo "cmux-mapper: ERROR: surface '$SURFACE_REF' is the CC parent — refusing to close" >&2
  exit 0
fi

# Close the surface
if command -v cmux >/dev/null 2>&1; then
  cmux close-surface --surface "$SURFACE_REF" 2>/dev/null || true
  echo "Panel closed for agent '$AGENT_ID': $SURFACE_REF" >&2
fi

exit 0
