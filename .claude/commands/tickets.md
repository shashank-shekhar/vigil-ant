---
description: List open GitHub issues and pick one to work on
argument-hint: [--label filter]
tools: Bash(bash:*, git:*)
model: haiku
---

List open GitHub issues and let the user pick one to start working on.

## Process

1. **List issues** — run:
   ```bash
   bash .claude/hooks/ticket-list.sh
   ```
   Show the output to the user.

2. **Ask** which issue number they want to work on. If they say none, stop.

3. **Start work** — run:
   ```bash
   bash .claude/hooks/ticket-start.sh <issue-number>
   ```

4. **Read the full issue** for context:
   ```bash
   gh issue view <issue-number>
   ```

5. Show the issue details and confirm ready to begin implementation.

## If $ARGUMENTS contains --label
Pass it through: `bash .claude/hooks/ticket-list.sh --label <filter>`
