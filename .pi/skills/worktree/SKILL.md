---
name: "worktree"
description: "Use when the user wants to start a new feature in an isolated git worktree, remove an existing worktree, or create a worktree from a PR, commit, or branch. Triggers: \"worktree\", \"new worktree\", \"start feature in worktree\", \"isolated workspace\", \"isolated branch\", \"work in a separate directory\", \"remove worktree\", \"clean up worktree\", \"checkout PR in worktree\", \"worktree for PR\", \"worktree --remove\", \"worktree --source\"."
---

# Worktree

Announce: "I'm using the worktree skill to manage an isolated workspace."

## Step 1: Parse Arguments

Parse `$ARGUMENTS` for flags:

| Flag | Format | Action |
|------|--------|--------|
| `--remove` | `--remove [path-or-slug]` | Route to REMOVE mode |
| `--source` | `--source <value>` | Route to SOURCE mode |
| none | `[slug]` | Route to CREATE mode (default) |

Extract:
- `REMOVE_TARGET` — value after `--remove` (may be empty)
- `SOURCE_VALUE` — value after `--source`
- `SLUG` — remaining text after stripping flags and their values

Run in parallel:
- `git rev-parse --show-toplevel` (repo root)
- `git worktree list --porcelain` (existing worktrees)

**If not a git repository:** inform the user and stop.

Set `REPO_ROOT` and `REPO_NAME` (basename of repo root).

---

## REMOVE Mode

*Entered when `--remove` flag is present.*

### Step R1: Identify Target Worktree

Parse `git worktree list --porcelain` into a list of `{path, branch, HEAD}` entries.
Exclude the main worktree (first entry).

If `REMOVE_TARGET` is provided:
- Find the worktree whose path or basename contains `REMOVE_TARGET` (case-insensitive substring match).
- If no match: report "No worktree matching '<REMOVE_TARGET>' found" and show the full list.

If `REMOVE_TARGET` is empty or no match found, ask:

```
ask_question(
  header: "Remove which?",
  question: "Which worktree do you want to remove?\n<list of worktree paths with their current branch>",
  options: [one entry per worktree]
)
```

### Step R2: Remove

Run:
1. `git worktree remove --force <path>`
2. `git worktree prune`

Report: `Removed worktree at <path> and pruned stale refs.`

Stop here.

---

## SOURCE Mode

*Entered when `--source` flag is present.*

### Step S1: Detect Source Type

Classify `SOURCE_VALUE`:

| Pattern | Type |
|---------|------|
| Contains `github.com` and `/pull/` | PR URL |
| Matches `#?[0-9]+` (digits only, optional `#`) | PR ID |
| Matches `[0-9a-f]{7,40}` (hex only) | Commit SHA |
| Anything else | Branch name |

### Step S2: Resolve Slug

Build the worktree slug:
- PR URL/ID: run `gh pr view <number-or-url> --json number,headRefName,title` to get branch and title. Use the PR number as slug prefix: `pr-<number>-<branch-slug>` (truncated to 50 chars).
- Branch: use branch name, replacing `/` with `-`, truncated to 50 chars.
- Commit SHA: use first 8 chars of SHA as slug.
- Override slug with `SLUG` if provided.

### Step S3: Determine Worktree Location

Resolve the worktrees directory in order:
1. If `$REPO_ROOT/../worktrees/` exists, use it.
2. Otherwise, create `$REPO_ROOT/../worktrees/`.

Worktree path: `<worktrees-dir>/<REPO_NAME>-<slug>`

If path already exists, ask:

```
ask_question(
  header: "Worktree exists",
  question: "A worktree already exists at <path>. What would you like to do?",
  options: [
    "Reuse existing" -- Use the existing worktree as-is,
    "Replace" -- Remove the existing worktree and create a fresh one
  ]
)
```

- "Reuse existing": skip to Step S5.
- "Replace": run `git worktree remove --force <path>` then continue.

### Step S4: Create and Checkout

**PR URL or PR ID:**
1. Extract the PR number from URL or strip `#` prefix from ID.
2. `git fetch origin` (fetch all remotes)
3. `git worktree add <worktree-path>` (creates worktree with detached HEAD)
4. In the worktree: `gh pr checkout <number> --force` — this checks out the PR branch inside the worktree. Run as: `git -C <worktree-path> ... ` or `(cd <worktree-path> && gh pr checkout <number> --force)`.

**Branch:**
1. `git fetch origin <branch>`
2. `git worktree add <worktree-path> origin/<branch>`

**Commit SHA:**
1. `git fetch origin`
2. `git worktree add --detach <worktree-path> <sha>`

### Step S5: Report and cd

Report:

```
Worktree ready at: <worktree-path>
Source: <PR #N / branch / commit>

Run to enter:
  cd <worktree-path>
```

Stop here.

---

## CREATE Mode (default)

*Entered when no `--remove` or `--source` flag is present.*

### Step C1: Determine Worktree Location

Resolve the worktrees directory in order:
1. If `$REPO_ROOT/../worktrees/` exists, use it.
2. Otherwise, create `$REPO_ROOT/../worktrees/`.

Build the worktree slug from `$ARGUMENTS` (the full remaining text after stripping flags):
- If arguments provided: lowercase, spaces to hyphens, strip non-alphanumeric (except hyphens), truncate to 50 chars.
- If no arguments provided:

```
ask_question(
  header: "Worktree name",
  question: "What is this worktree for? Provide a short description or ticket ID.",
  options: []
)
```

Worktree path: `<worktrees-dir>/<REPO_NAME>-<slug>`

If path already exists:

```
ask_question(
  header: "Worktree exists",
  question: "A worktree already exists at <path>. What would you like to do?",
  options: [
    "Reuse existing" -- Use the existing worktree as-is,
    "Replace" -- Remove the existing worktree and create a fresh one,
    "Choose different name" -- Provide a different name for the new worktree
  ]
)
```

- "Reuse existing": skip to Step C3.
- "Replace": run `git worktree remove --force <path>` then continue.
- "Choose different name": prompt for a new name and rebuild the path.

### Step C2: Fetch and Create Worktree

Determine the base branch:
1. `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` — extract branch name (e.g. `origin/main` → `main`).
2. If that fails: `git remote set-head origin --auto 2>/dev/null` and retry step 1.
3. If still unresolved: fall back to `main` if `origin/main` exists, then `master` if `origin/master` exists.
4. If nothing works: ask the user.

Run:
1. `git fetch origin <base>`
2. `git worktree add --detach <worktree-path> origin/<base>`

### Step C3: Stale Worktree Check

If `git worktree list` showed 10 or more worktrees, warn:

```
Note: You have <N> worktrees. Consider cleaning up old ones:
  git worktree list
  /worktree --remove <slug>
  git worktree prune
```

### Step C4: Report and Next Steps

Report:

```
Worktree created at: <worktree-path>
Base: origin/<base>

Run to enter:
  cd <worktree-path>

Then run /branch to create your feature branch.
```

## Error Handling

| Error | Action |
|-------|--------|
| Not a git repository | Inform the user and stop. |
| `--source` PR fetch fails (no `gh` auth) | Report the gh error. Suggest `gh auth login`. |
| `--source` branch not found on remote | Report "Branch '<name>' not found on origin". Suggest `git fetch --all`. |
| `--source` commit SHA not found | Report "Commit '<sha>' not found". Suggest running `git fetch origin` first. |
| `--remove` with no worktrees | Report "No removable worktrees found" and stop. |
| `--remove` target not found | List all worktrees and ask the user to pick one. |
| Worktree add failure | Report the full git error. Common cause: branch already checked out in another worktree. |
| Worktree removal failure | Report the git error. Suggest manual cleanup with `git worktree prune`. |
| Path already exists | Offer to reuse, replace, or (in CREATE mode) choose a different name. |
