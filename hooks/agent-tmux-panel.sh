#!/usr/bin/env bash
# agent-tmux-panel.sh — PreToolUse:Agent hook for auto-creating agent panels
#
# Creates a cmux panel for each spawned agent, mirroring CC's native tmux layout:
#   - First agent:      splits RIGHT from the CC parent surface
#   - Subsequent ones:  split DOWN from the previous agent surface
#
# Each panel runs a transcript watcher that streams the agent's actual output.
# Panel surface refs are stored in a session-scoped FIFO queue for cleanup.
# The parent surface (read from /tmp/cmux-session-{SESSION_ID}) is never queued.
# Always exits 0 — panel creation failure must never block agent spawn.
#
# Hook event: PreToolUse (matcher: Agent)
# Input: JSON on stdin with session_id, cwd, tool_input.name
# Output: JSON with permissionDecision "allow"
set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id','unknown'))" 2>/dev/null || echo "unknown")
AGENT_NAME=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('name','unknown'))" 2>/dev/null || echo "unknown")
CWD=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('cwd',''))" 2>/dev/null || true)

QUEUE_FILE="/tmp/cmux-agent-surfaces-${SESSION_ID}"
PARENT_FILE="/tmp/cmux-session-${SESSION_ID}"

if command -v cmux >/dev/null 2>&1; then
  PARENT_SURFACE=$(cat "$PARENT_FILE" 2>/dev/null || true)

  if [[ -z "$PARENT_SURFACE" ]]; then
    echo "cmux-mapper: no parent surface recorded for session '$SESSION_ID', skipping panel" >&2
  else
    # First agent → split right from CC parent; subsequent → split down from last agent
    if [[ -s "$QUEUE_FILE" ]]; then
      LAST_SURFACE=$(tail -1 "$QUEUE_FILE")
      SPLIT_OUTPUT=$(cmux new-split down --surface "$LAST_SURFACE" 2>/dev/null) || true
    else
      SPLIT_OUTPUT=$(cmux new-split right --surface "$PARENT_SURFACE" 2>/dev/null) || true
    fi

    SURFACE_REF=$(echo "$SPLIT_OUTPUT" | grep -oE 'surface:[0-9]+' | head -1)

    if [[ -n "$SURFACE_REF" ]]; then
      if [[ "$SURFACE_REF" == "$PARENT_SURFACE" ]]; then
        echo "cmux-mapper: split returned parent surface '$SURFACE_REF' — skipping queue" >&2
      else
        echo "$SURFACE_REF" >> "$QUEUE_FILE"
        echo "Panel created for agent '$AGENT_NAME': $SURFACE_REF" >&2

        # Build the subagents directory path from cwd + session_id
        # CC stores transcripts at: ~/.config/claude-code/projects/{cwd-slug}/{session-id}/subagents/
        CWD_SLUG=$(echo "$CWD" | sed 's|/|-|g')
        SUBAGENTS_DIR="$HOME/.config/claude-code/projects/${CWD_SLUG}/${SESSION_ID}/subagents"

        # Write a watcher script for this agent into a temp file
        WATCH_SCRIPT="/tmp/cmux-watch-${SESSION_ID}-${SURFACE_REF//:/}.sh"
        cat > "$WATCH_SCRIPT" <<WATCHEOF
#!/usr/bin/env bash
# Find the agent JSONL file newer than this script itself.
# The script is written before the agent starts, so any JSONL with a newer
# mtime must belong to this agent invocation.
SUBDIR="${SUBAGENTS_DIR}"
SELF="${WATCH_SCRIPT}"
mkdir -p "\$SUBDIR"
clear
printf '\033[1mAgent: ${AGENT_NAME}\033[0m\n\n'

# Wait up to 30s for a new agent JSONL to appear
WAITED=0
NEW_FILE=""
while [[ \$WAITED -lt 150 ]]; do
  for f in "\$SUBDIR"/agent-*.jsonl; do
    [[ -f "\$f" ]] || continue
    [[ "\$f" -nt "\$SELF" ]] || continue
    # Atomically claim this file (noclobber prevents two watchers from taking the same one)
    LOCK="\${f}.wlock"
    ( set -C; echo \$\$ > "\$LOCK" ) 2>/dev/null || continue
    NEW_FILE="\$f"
    break 2
  done
  sleep 0.2
  WAITED=\$((WAITED + 1))
done

if [[ -z "\$NEW_FILE" ]]; then
  echo "[cmux-mapper] no transcript found after 30s"
  exit 0
fi

printf '\033[2m%s\033[0m\n\n' "\$NEW_FILE"

# Stream and format the transcript
tail -f "\$NEW_FILE" | python3 -u -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        d = json.loads(line)
        msg = d.get('message', d)
        role = msg.get('role', '')
        if role == 'assistant':
            for c in msg.get('content', []):
                if not isinstance(c, dict): continue
                if c.get('type') == 'text':
                    txt = c['text'].strip()
                    if txt:
                        print(txt, flush=True)
                elif c.get('type') == 'tool_use':
                    print(f'[{c.get(\"name\",\"tool\")}]', flush=True)
    except Exception:
        pass
"
WATCHEOF
        chmod +x "$WATCH_SCRIPT"

        # Launch the watcher in the panel
        cmux send --surface "$SURFACE_REF" "bash ${WATCH_SCRIPT}\n" 2>/dev/null || true
      fi
    else
      echo "Warning: panel creation failed for agent '$AGENT_NAME' (cmux output: $SPLIT_OUTPUT)" >&2
    fi
  fi
else
  echo "No cmux detected — skipping panel creation for agent '$AGENT_NAME'" >&2
fi

# Always allow agent spawn
cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","additionalContext":"Panel created for agent: $AGENT_NAME"}}
EOF

exit 0
