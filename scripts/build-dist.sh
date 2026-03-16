#!/usr/bin/env bash
set -euo pipefail

# Build a clean plugin distribution in dist/
# Usage: bash scripts/build-dist.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist"

echo "Building dist/ from $REPO_ROOT..."

# Clean previous build
rm -rf "$DIST"
mkdir -p "$DIST/.claude-plugin" "$DIST/hooks" "$DIST/lib"

# Plugin manifest
cp "$REPO_ROOT/.claude-plugin/plugin.json" "$DIST/.claude-plugin/plugin.json"

# Library modules
cp "$REPO_ROOT"/lib/*.sh "$DIST/lib/"

# Hooks
cp "$REPO_ROOT/hooks/hooks.json" "$DIST/hooks/hooks.json"
cp "$REPO_ROOT"/hooks/*.sh "$DIST/hooks/"
chmod +x "$DIST"/hooks/*.sh

# Docs (optional but useful)
cp "$REPO_ROOT/README.md" "$DIST/README.md"
cp "$REPO_ROOT/LICENSE" "$DIST/LICENSE"

echo ""
echo "dist/ built successfully:"
find "$DIST" -type f | sort | sed "s|$DIST/|  |"
echo ""
echo "Test with:"
echo "  claude --plugin-dir $DIST"
