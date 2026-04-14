#!/bin/bash
# Sets active ticket state and creates a working branch from main
# Usage: ticket-start.sh <issue-number>

set -euo pipefail

ISSUE_NUM="${1:?Usage: ticket-start.sh <issue-number>}"
STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/current-ticket"

# Check if already working on a ticket
if [ -f "$STATE_FILE" ]; then
    CURRENT=$(cat "$STATE_FILE")
    echo "Error: Already working on: ${CURRENT}" >&2
    echo "Run /ticket-done first to commit, push, and close the current ticket." >&2
    exit 1
fi

# Check for dirty working tree
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    echo "Error: Working tree has uncommitted changes." >&2
    echo "Commit or stash changes before starting a new ticket." >&2
    exit 1
fi

# Fetch issue title
if ! TITLE=$(gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>&1); then
    echo "Error fetching issue #${ISSUE_NUM}: ${TITLE}" >&2
    exit 1
fi

# Slugify title for branch name
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//' | cut -c1-50)
BRANCH="issue-${ISSUE_NUM}-${SLUG}"

# Always branch from main
git checkout main 2>&1
git pull --ff-only 2>&1 || true
git checkout -b "$BRANCH" 2>&1 || {
    # Branch might already exist
    git checkout "$BRANCH" 2>&1
}

# Write state
echo "#${ISSUE_NUM} | ${TITLE} | ${BRANCH}" > "$STATE_FILE"

echo "Started work on issue #${ISSUE_NUM}: ${TITLE}"
echo "Branch: ${BRANCH}"
