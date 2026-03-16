# Contributing to cmux-tmux-mapping

Thanks for considering a contribution. This project is a Claude Code plugin that maps tmux operations into cmux commands for transparent panel management across multiplexer backends.

## Prerequisites

- Claude Code v1.0.33+
- Bash 4.0+ (required for associative arrays)
- tmux 2.0+ or cmux (at least one)
- Python 3 (used by hooks for JSON parsing)

## Project Structure

```text
lib/              Core library modules
  core.sh         Shared constants, logging, error codes
  detect.sh       Environment detection (cmux/tmux/none)
  commands.sh     tmux-to-cmux command mapping functions
  id-map.sh       Identifier translation (tmux targets <-> cmux surfaces)
  isolation.sh    Agent panel lifecycle management
  mapper.sh       Unified public API entry point
hooks/            Claude Code plugin hooks
  hooks.json      Hook event-to-script wiring
  tmux-session-start.sh    SessionStart: auto-detect multiplexer
  agent-tmux-panel.sh      PreToolUse:Agent: create agent panel
  agent-tmux-cleanup.sh    SubagentStop: destroy agent panel
tests/            Test suite (zero external dependencies)
  run-tests.sh    Test runner with assertion helpers
  test-*.sh       Test files (auto-discovered by runner)
.claude-plugin/   Plugin manifest
  plugin.json     Plugin metadata and hook registration
```

## Making Changes

1. **Fork the repo** and create a feature branch from `main` (e.g., `fix/detection-fallback` or `feat/disk-persistence`). **Never commit directly to `main`**.
2. **Test locally** by running `bash tests/run-tests.sh` — all tests must pass before submitting.
3. **Keep commits atomic** — one logical change per commit.
4. **Follow code style:**
   - Shell scripts: `#!/usr/bin/env bash` shebang, `set -euo pipefail`
   - No external dependencies beyond `jq` and `python3`
   - Exit codes in hooks: `exit 0` = allow (always), `exit 2` = block with message
   - All hooks must exit 0 under normal operation — never block agent execution
   - Commit format: `{type}({scope}): {description}` — types: feat, fix, docs, test, refactor, chore

## Pull Request Process

1. Open an issue first for non-trivial changes so we can discuss the approach.
2. Reference the issue in your PR.
3. Describe what changed and why. Include before/after behavior if relevant.
4. Test your changes against at least one real project with tmux or cmux active.
5. **Run QA review before marking ready.** Repeat this cycle at least 2-4 times:

   > **Docs-only PRs:** The QA round requirement only applies when the PR touches library modules (`lib/`), hooks (`hooks/`), or test infrastructure (`tests/run-tests.sh`). PRs that only change docs, README, or repo metadata skip the check automatically.

   **Step A — Run the QA prompt.** Open a **new** Claude Code (or other AI) session using a top-tier model — **Claude Opus 4.6** or equivalent. Smaller models don't produce thorough enough reviews. Paste the prompt below (fill in the placeholders):

   ````text
   You are a read-only QA reviewer. Do NOT modify files, make commits, or push fixes — report only.

   PR: #<number>
   Branch: <branch-name>

   1. Review the commits in the PR to understand the change narrative.
   2. Read all files changed in the PR for full context.
   3. Run `bash tests/run-tests.sh` and report any failures.
   4. Act as a devil's advocate — find edge cases, missed regressions, and untested
      paths the implementer didn't consider. Pay particular attention to:
      - Hook exit codes (must always be 0 in normal operation)
      - Environment detection edge cases (missing binaries, unset variables)
      - Panel registry state management (in-memory limitations)
      - Argument parsing robustness in mapping functions

   Do NOT prescribe what to test upfront. Discover what matters by reading the code.

   Report format (use a markdown code block):
   - Model used:
   - What was tested
   - Expected vs actual
   - Severity (critical / major / minor)
   - Confirmed vs hypothetical
   ````

   **Step B — Fix the findings.** Copy the QA report and paste it into your original working session (or a new session on the same branch). Each QA round's fixes must be a **separate commit** — do not amend previous commits. Use the format `fix(scope): address QA round N`.

   **Step C — Repeat.** Go back to Step A with a fresh session. Continue until a round comes back clean or only has hypothetical/minor findings.

   **Proving your work:** Paste each round's QA report as a separate comment on the PR. Reviewers will cross-reference the reports against the fix commits in the PR history.

## Reporting Bugs

Open an issue with:
- Claude Code version (`claude --version`)
- The hook that failed (SessionStart, PreToolUse:Agent, or SubagentStop)
- Whether you're running in tmux, cmux, or neither
- The full hook error output (check stderr or enable `CMUX_MAPPER_DEBUG=1`)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
