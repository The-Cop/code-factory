---
name: "worktree"
description: "Use when the user wants to start a new feature in an isolated git worktree. Triggers: \"worktree\", \"new worktree\", \"start feature in worktree\", \"isolated workspace\", \"isolated branch\", \"work in a separate directory\"."
---

# Create Worktree

Announce: "I'm using the worktree skill to create an isolated workspace for feature development."

## Step 1: Gather Context

Run in parallel:
- `git rev-parse --show-toplevel` (repo root)
- `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` (default branch)
- `git worktree list` (existing worktrees)

**If not a git repository:** inform the user and stop.

Set `REPO_ROOT` to the repo root path and `REPO_NAME` to its basename.

## Step 2: Determine Worktree Location

Resolve the worktrees directory in order:

1. If `$REPO_ROOT/../worktrees/` exists, use it.
2. Otherwise, create `$REPO_ROOT/../worktrees/`.

Build the worktree slug from the user's invocation prompt:
- If arguments provided: lowercase, spaces to hyphens, strip non-alphanumeric (except hyphens), truncate to 50 chars.
- If no arguments provided:

**Pause and ask the user. Wait for their answer before proceeding.**

> **Worktree name** -- What is this worktree for? Provide a short description or ticket ID.

The worktree path is: `<worktrees-dir>/<REPO_NAME>-<slug>`

**If that path already exists:**

**Pause and ask the user. Wait for their answer before proceeding.**

> **Worktree exists** -- A worktree already exists at <path>. What would you like to do?
>
> - **Reuse existing** -- Use the existing worktree as-is
> - **Replace** -- Remove the existing worktree and create a fresh one
> - **Choose different name** -- Provide a different name for the new worktree

- "Reuse existing": report the existing path and skip creation
- "Replace": run `git worktree remove <path>` then proceed with creation
- "Choose different name": prompt for a new name and rebuild the path

## Step 3: Fetch and Create Worktree

Determine the base branch:

1. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` — extract branch name (e.g. `origin/main` → `main`).
2. If that fails: `git remote set-head origin --auto 2>/dev/null` and retry step 1.
3. If still unresolved: fall back to `main` if `origin/main` exists, then `master` if `origin/master` exists.
4. If nothing works: ask the user.

Run:
1. `git fetch origin <base>`
2. `git worktree add --detach <worktree-path> origin/<base>`

## Step 4: Stale Worktree Check

If `git worktree list` showed 10 or more worktrees, warn:

```
Note: You have <N> worktrees. Consider cleaning up old ones:
  git worktree list
  git worktree remove <path>
  git worktree prune
```

## Step 5: Report and Next Steps

Report to the user:

```
Worktree created at: <worktree-path>
Base: origin/<base>

Next step: cd into the worktree and run /branch to create your feature branch.
```

## Error Handling

- **Not a git repository**: inform the user and stop.
- **Path already exists**: offer to reuse, replace, or choose a different name (see Step 2).
- **Fetch failure**: report the error. Suggest checking network connectivity or remote configuration.
- **Worktree add failure**: report the full git error. Common cause: branch already checked out in another worktree.
- **Worktree removal failure**: if replacing an existing worktree, report the removal error. Suggest manual cleanup with `git worktree prune`.
