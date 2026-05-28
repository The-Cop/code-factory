---
name: "branch"
description: "Use when the user wants to create a well-named feature branch from a ticket ID, description, or task summary. Triggers: \"create branch\", \"new branch\", \"branch for\", \"start working on\"."
---

# Create Branch

Announce: "I'm using the branch skill to create a well-named feature branch."

## Step 1: Gather Context

Run in parallel:
- `git status --short` (check for uncommitted changes)
- `git branch --show-current` (current branch)
- `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` (detect default branch)

**If this is not a git repository:** inform the user and stop.

## Step 2: Parse Input

Extract from the user's invocation prompt:

1. **Ticket ID**: Look for patterns like `[A-Z]+-[0-9]+` (e.g., `PROJ-1234`, `JIRA-567`).
2. **Description**: The remaining text after removing the ticket ID, or the entire argument if no ticket ID is found.

**If no arguments are provided:**

**Pause and ask the user. Wait for their answer before proceeding.**

> **Branch name** -- What should the branch be for? Provide a ticket ID and/or short description.

## Step 3: Build Branch Name

Determine the branch prefix from `git config user.name` (lowercase, first token, e.g., "Rodrigo Fernandes" becomes `rodrigo`). Fall back to `feature` if git config is not set.

Construct the branch name using this pattern:

- If ticket ID and description: `<prefix>/<slug>-<TICKET-ID>`
- If ticket ID only (no description): `<prefix>/<TICKET-ID>`
- If description only (no ticket ID): `<prefix>/<slug>`

Where:
- `<prefix>` is the user prefix derived above
- `<slug>` is the description converted to lowercase, with spaces replaced by hyphens, non-alphanumeric characters removed, and truncated to 50 characters.

Examples (assuming prefix `rodrigo`):
- `add user authentication PROJ-1234` -> `rodrigo/add-user-authentication-PROJ-1234`
- `PROJ-1234` -> `rodrigo/PROJ-1234`
- `fix login timeout bug` -> `rodrigo/fix-login-timeout-bug`
- `refactor database layer CORE-99` -> `rodrigo/refactor-database-layer-CORE-99`

## Step 4: Create the Branch

Determine the base branch:

1. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` — extract branch name (e.g. `origin/main` → `main`).
2. If that fails: `git remote set-head origin --auto 2>/dev/null` and retry step 1.
3. If still unresolved: fall back to `main` if `origin/main` exists, then `master` if `origin/master` exists.
4. If nothing works: ask the user.

**If there are uncommitted changes:** warn the user but proceed (the changes will carry over to the new branch).

Run:
1. `git fetch origin <base>` (fetch latest)
2. `git checkout -b <branch-name> origin/<base>`

Report the created branch name and base to the user:
```
Created branch: <branch-name> (from origin/<base>)
```

## Error Handling

- **Not a git repository**: inform the user and stop.
- **Branch already exists**: report the conflict. Offer to switch to the existing branch or suggest an alternative name.
- **Fetch failure**: report the error. Suggest checking network connectivity or remote configuration.
- **Default branch not detected**: follow the Default Branch Detection procedure in Step 4, then ask the user if all fallbacks fail.
- **No description provided**: prompt for one before proceeding.
