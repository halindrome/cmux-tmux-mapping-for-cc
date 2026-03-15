# cmux-tmux-mapping

A Claude Code plugin that automatically enables tmux support for agents and maps tmux operations into cmux commands for panel management.

## Overview

cmux-tmux-mapping detects whether your session is running inside tmux or cmux, then transparently routes panel operations through the correct backend. When Claude Code spawns agents, the plugin automatically creates isolated panels for each agent and cleans them up when the agent finishes. No manual configuration required -- just install and go.

## Prerequisites

- **Bash 4.0+** (required for associative arrays)
- **tmux 2.0+** or **cmux** (at least one must be installed and active)
- **Python 3** (used by hooks for JSON input parsing)

## Installation

Install from a local directory:

```bash
claude plugin install --path ./cmux-tmux-mapping-for-cc
```

Once available on the Claude Code plugin marketplace, install with:

```bash
/plugin install cmux-tmux-mapping
```

## Quick Start

**Automatic mode** -- the plugin works out of the box. On session start, the `SessionStart` hook detects your multiplexer environment and exports `CLAUDE_MUXER`. When Claude spawns an agent, the `PreToolUse:Agent` hook creates a panel automatically. When the agent finishes, `SubagentStop` cleans it up.

**Manual API usage** -- source the library directly in your scripts:

```bash
source lib/mapper.sh

# Check which environment is active
mux_env          # prints "cmux", "tmux", or "none"

# Create a panel for an agent
mux_create_panel "my-agent" "v"

# Send text to the agent's panel
mux_send "my-agent" "echo hello"

# Destroy the panel when done
mux_destroy_panel "my-agent"
```

**Command translation** -- translate tmux commands to the active backend:

```bash
source lib/mapper.sh

mux_command "split-window" "-v"
# In cmux: outputs "cmux split -d vertical"
# In tmux: outputs "tmux split-window -v"
```

## Features

### Hooks

The plugin registers three hooks that run automatically:

| Hook | Event | Script | Purpose |
|------|-------|--------|---------|
| Session init | `SessionStart` | `hooks/tmux-session-start.sh` | Detects tmux/cmux, exports `CLAUDE_MUXER` |
| Panel create | `PreToolUse` (Agent) | `hooks/agent-tmux-panel.sh` | Creates isolated panel when agent spawns |
| Panel cleanup | `SubagentStop` | `hooks/agent-tmux-cleanup.sh` | Destroys agent panel on completion |

All hooks are best-effort and always exit 0 -- they never block agent operations.

### Public API

Six functions are exported by `lib/mapper.sh`:

- `mux_env` -- detect the active multiplexer
- `mux_command` -- translate a tmux subcommand
- `mux_create_panel` -- create an isolated agent panel
- `mux_destroy_panel` -- destroy an agent panel
- `mux_send` -- send text to an agent's panel
- `mux_list` -- list panels/panes

## API Reference

### `mux_env`

Print the detected environment.

```bash
env=$(mux_env)
# Returns: "cmux", "tmux", or "none"
```

**Arguments:** none
**Returns:** 0 always
**Stdout:** environment string

---

### `mux_command subcmd [args...]`

Translate a tmux subcommand into the environment-appropriate command string.

```bash
cmd=$(mux_command "split-window" "-v")
eval "$cmd"
```

**Arguments:**
- `subcmd` -- tmux subcommand (e.g., `split-window`, `send-keys`, `list-panes`)
- `args` -- additional arguments passed to the subcommand

**Returns:** 0 on success, 1 if no subcommand provided or no multiplexer detected
**Stdout:** executable command string

---

### `mux_create_panel agent_id [direction]`

Create an isolated panel for an agent.

```bash
handle=$(mux_create_panel "agent-1" "v")
```

**Arguments:**
- `agent_id` -- unique identifier (alphanumeric, dash, underscore)
- `direction` -- `"v"` for vertical (default), `"h"` for horizontal

**Returns:** 0 on success, 1 if agent_id is empty/invalid, already exists, or no multiplexer detected
**Stdout:** panel handle (format: `{env}:{identifier}`)

---

### `mux_destroy_panel agent_id`

Destroy an agent's panel and remove it from the registry.

```bash
mux_destroy_panel "agent-1"
```

**Arguments:**
- `agent_id` -- the agent whose panel to destroy

**Returns:** 0 on success, 1 if agent not found
**Stdout:** the destroyed panel handle

---

### `mux_send agent_id text`

Send text to an agent's panel.

```bash
cmd=$(mux_send "agent-1" "ls -la")
eval "$cmd"
```

**Arguments:**
- `agent_id` -- target agent
- `text` -- text to send

**Returns:** 0 on success, 1 if agent_id is empty or no panel found
**Stdout:** executable send command

---

### `mux_list`

List all panels/panes in the current environment.

```bash
mux_list
```

**Arguments:** none
**Returns:** 0 always
**Stdout:** executable list command, or agent panel listing if no multiplexer detected

## Configuration

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `CMUX_FORCE_ENV` | Override environment detection. Set to `"cmux"`, `"tmux"`, or `"none"`. Useful for testing. | _(auto-detect)_ |
| `CMUX_MAPPER_DEBUG` | Enable debug logging. Set to `1` for verbose output to stderr. | `0` |
| `CLAUDE_MUXER` | Set by the `SessionStart` hook. Contains the detected environment. | _(set automatically)_ |
| `CLAUDE_ENV_FILE` | Path where the `SessionStart` hook writes environment exports. Provided by Claude Code. | _(set by Claude Code)_ |

### Detection Precedence

Environment detection follows this order:

1. `CMUX_FORCE_ENV` -- if set, use this value directly
2. `cmux identify --json` -- if cmux CLI is available and responds, use cmux
3. `$TMUX` variable -- if set and non-empty, use tmux
4. Fall through to `"none"`

## Troubleshooting

### Common Errors

| Error Message | Cause | Fix |
|---------------|-------|-----|
| `no multiplexer detected (neither cmux nor tmux)` | Neither tmux nor cmux is running | Start a tmux session (`tmux new-session`) or run inside cmux |
| `could not parse agent name` | Hook received malformed JSON or Python 3 is missing | Ensure Python 3 is installed: `python3 --version` |
| `no panel found for agent 'X'` | Panel was never created, or was created in a different shell process | See Limitations below about in-memory registry |
| `agent 'X' already has a panel` | Duplicate `mux_create_panel` call for the same agent_id | Destroy the existing panel first, or use a unique agent_id |

### Enabling Debug Mode

Set `CMUX_MAPPER_DEBUG=1` to see detailed detection and routing information:

```bash
CMUX_MAPPER_DEBUG=1 claude
```

Debug output goes to stderr and includes environment detection results, panel creation events, and command translation details.

### Verifying the Plugin is Active

After starting a Claude Code session, the `SessionStart` hook prints a status line:

```
cmux-tmux-mapping plugin active. Multiplexer: tmux. Panel API available via lib/mapper.sh.
```

If you see `Multiplexer: none`, check that you're running inside a tmux or cmux session.

## Limitations

- **In-memory panel registry** -- the panel registry (`_AGENT_PANELS`) is stored in memory within the current shell process. It is not shared across subshells or persisted to disk. If the shell exits, panel state is lost. A future release (v1.1) will add disk-based persistence.
- **Python 3 required** -- hooks use Python 3 for JSON parsing. If Python 3 is unavailable, agent names default to `"unknown"` and panel operations may be mismatched.
- **Single-process state** -- panel create and destroy operations must run in the same shell process to share state. Hook invocations each run in their own subprocess.

## License

MIT
