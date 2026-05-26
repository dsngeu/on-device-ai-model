#!/bin/bash
# Installs git hooks for Debrief.
# Run once after cloning: bash scripts/setup-hooks.sh

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_HOOKS="$REPO_ROOT/.git/hooks"
SCRIPT_HOOKS="$REPO_ROOT/scripts/hooks"

install_hook() {
    local NAME=$1
    local SRC="$SCRIPT_HOOKS/$NAME"
    local DEST="$GIT_HOOKS/$NAME"

    if [ ! -f "$SRC" ]; then
        echo "⚠  No source hook found at $SRC — skipping"
        return
    fi

    cp "$SRC" "$DEST"
    chmod +x "$DEST"
    echo "✓  $NAME hook installed"
}

install_hook "pre-commit"

echo ""
echo "Hooks installed. Run 'git commit' as normal — hooks fire automatically."
