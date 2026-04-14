#!/bin/bash
# Clears the active ticket state
# Safety: refuses to clear if there are uncommitted changes
# Usage: ticket-done.sh

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/current-ticket"

if [ ! -f "$STATE_FILE" ]; then
    echo "No active ticket to clear."
    exit 0
fi

# Guard: refuse to clear with uncommitted changes
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "Error: Working tree has uncommitted changes." >&2
    echo "Commit and push before closing the ticket." >&2
    exit 1
fi

# Guard: refuse to clear if branch has unpushed commits
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$BRANCH" ] && git rev-parse --verify "origin/${BRANCH}" >/dev/null 2>&1; then
    UNPUSHED=$(git log "origin/${BRANCH}..HEAD" --oneline 2>/dev/null)
    if [ -n "$UNPUSHED" ]; then
        echo "Error: Branch has unpushed commits." >&2
        echo "Push before closing the ticket." >&2
        exit 1
    fi
elif [ -n "$BRANCH" ] && [ "$BRANCH" != "main" ]; then
    echo "Error: Branch '${BRANCH}' has not been pushed to origin." >&2
    echo "Push before closing the ticket." >&2
    exit 1
fi

CURRENT=$(cat "$STATE_FILE")
rm "$STATE_FILE"
echo "Cleared active ticket: ${CURRENT}"
