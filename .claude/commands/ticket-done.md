---
description: Commit, push, and close the active ticket
argument-hint: none
tools: Bash(bash:*, git:*, gh:*)
model: haiku
---

Finalize work on the active ticket: commit, push, close issue, and clear state.

## Process

1. **Check active ticket** — run:
   ```bash
   cat .claude/current-ticket
   ```
   If no active ticket, inform the user and stop.
   Parse the issue number from the output (format: `#N | title | branch`).

2. **Check for changes** — run `git status` and `git diff --stat`.
   - If there are uncommitted changes, stage and commit them with a message referencing the issue number (e.g., `feat: add license attribution (#1)`)
   - If nothing to commit, skip to step 3

3. **Push** — run:
   ```bash
   git push -u origin HEAD
   ```

4. **Close the GitHub issue** — run:
   ```bash
   gh issue close <issue-number> --reason completed
   ```

5. **Clear state** — run:
   ```bash
   bash .claude/hooks/ticket-done.sh
   ```

6. Show confirmation with the branch name and suggest creating a PR if needed.
