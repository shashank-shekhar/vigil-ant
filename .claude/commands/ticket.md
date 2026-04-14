---
description: Create a GitHub issue from a feature request or change description
argument-hint: <description of the feature or change>
tools: Bash(bash:*)
model: haiku
---

Create a GitHub issue from the user's description.

## Process

1. **Parse** `$ARGUMENTS` — the feature/change description

2. **Classify and draft:**
   - Pick a type: `bug`, `enhancement`, or `documentation`
   - Pick labels from: `bug`, `enhancement`, `documentation`, `good first issue`, `help wanted`
   - Draft a concise title (< 80 chars, imperative mood)
   - Draft a body in this format:
     ```
     ## Description
     <what and why>

     ## Acceptance Criteria
     - [ ] <criterion 1>
     - [ ] <criterion 2>
     ```

3. **Show draft** to the user:
   ```
   Title: <title>
   Labels: <labels>
   Body:
   <body>
   ```
   Ask: "Create this issue? (or suggest changes)"

4. **Create** — once confirmed, run:
   ```bash
   bash .claude/hooks/ticket-create.sh --title "<title>" --body "<body>" --label <label1> [--label <label2>]
   ```
   Parse the issue number from output (format: `CREATED #N | title | url`).

5. **Ask next step:** "Start working on this now, or continue adding more tasks?"
   - If start: run:
     ```bash
     bash .claude/hooks/ticket-start.sh <issue-number>
     ```
   - If continue: done

## Important
- Do NOT create the issue without showing the draft first
- Do NOT start work without explicit confirmation
- Keep the title short and in imperative mood ("add X", "fix Y")
- The body should be actionable, not verbose
- If the hook reports ACTIVE_TICKET, warn the user they must close the current ticket first
