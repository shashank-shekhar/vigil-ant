#!/bin/bash
# Hook: UserPromptSubmit — injects active ticket state into Claude's context
# Exit 0 always (non-blocking)

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/current-ticket"

if [ -f "$STATE_FILE" ]; then
    TICKET_INFO=$(cat "$STATE_FILE")
    echo "ACTIVE_TICKET: ${TICKET_INFO}. Work is scoped to this ticket."
else
    echo "NO_ACTIVE_TICKET: If this prompt is a feature request or change, suggest using /ticket to create a GitHub issue first. If it's a question, debugging, or non-feature work, proceed normally."
fi

exit 0
