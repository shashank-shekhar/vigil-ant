#!/bin/bash
# Lists open GitHub issues in a formatted table
# Usage: ticket-list.sh [--label filter]

set -euo pipefail

LABEL_FILTER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) LABEL_FILTER="--label $2"; shift 2 ;;
        *)       echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

# shellcheck disable=SC2086
ISSUES=$(gh issue list --state open --limit 30 $LABEL_FILTER --json number,title,labels,createdAt \
    --template '{{range .}}#{{.number}} | {{.title}} | {{range .labels}}[{{.name}}] {{end}}| {{timeago .createdAt}}
{{end}}' 2>&1)

if [ -z "$ISSUES" ]; then
    echo "No open issues found."
    exit 0
fi

echo "Open Issues:"
echo "---"
echo "$ISSUES"
