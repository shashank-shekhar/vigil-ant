#!/bin/bash
# Creates a GitHub issue with title, body, and labels
# Usage: ticket-create.sh --title "..." --body "..." [--label name ...]

set -eo pipefail

TITLE=""
BODY=""
LABELS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title)  TITLE="$2"; shift 2 ;;
        --body)   BODY="$2"; shift 2 ;;
        --label)  LABELS+=("--label" "$2"); shift 2 ;;
        *)        echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$TITLE" ]; then
    echo "Error: --title is required" >&2
    exit 1
fi

if [ ${#LABELS[@]} -gt 0 ]; then
    if ! RESULT=$(gh issue create --title "$TITLE" --body "$BODY" "${LABELS[@]}" 2>&1); then
        echo "Error creating issue: $RESULT" >&2
        exit 1
    fi
else
    if ! RESULT=$(gh issue create --title "$TITLE" --body "$BODY" 2>&1); then
        echo "Error creating issue: $RESULT" >&2
        exit 1
    fi
fi

# Extract issue number from URL (https://github.com/owner/repo/issues/N)
ISSUE_NUM=$(echo "$RESULT" | grep -oE '[0-9]+$')
echo "CREATED #${ISSUE_NUM} | ${TITLE} | ${RESULT}"
