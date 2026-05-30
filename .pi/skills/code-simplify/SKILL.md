---
name: "code-simplify"
description: "Use when the user wants to simplify, clean up, or refactor code for clarity and maintainability without changing behavior. Supports any scope: a single file, directory, package, branch diff, staged changes, or an entire repository. Also use when the user says \"simplify code\", \"clean up this file\", \"reduce complexity\", \"refactor for readability\", \"simplify repo\", \"code cleanup\", or asks to make code simpler, cleaner, or more maintainable."
---

# Code Simplification

Announce: "I'm using the /code-simplify skill to simplify code for clarity and maintainability."

## Hard Rules

- **Never change behavior.** Simplification preserves exact functionality. If a change might alter behavior, skip it.
- **Verify after every batch.** Run project-specific checks (linters, type checkers, tests) after each batch of files.
  Never mark a batch complete if checks fail.
- **One file per agent.** Each file gets its own `productivity:code-simplifier` subagent.
  Agents must not modify files outside their assignment.
- **Track everything.** The tracking file is the source of truth for progress.
  Always update it after each batch completes.

## Step 1: Detect Scope

Parse `$ARGUMENTS` to determine what to simplify.

| Argument | Scope | File enumeration |
|-|-|-|
| File path (e.g., `src/auth.ts`) | Single file | That file only |
| Directory path (e.g., `src/auth/`) | Directory | All source files in that directory (non-recursive) |
| Directory path with `**` (e.g., `src/auth/**`) | Directory recursive | All source files recursively |
| `--branch` or no arguments | Branch diff | Files changed on current branch vs default branch |
| `--staged` | Staged files | Files in the git staging area |
| `--repo` | Entire repo | All source files in the repo |
| `--package <name>` | Package/module | Files in the named package, module, or workspace member |
| `--diff <ref>` | Diff since ref | Files changed since the given git ref |

### Scope resolution

**Default branch detection** (for `--branch` scope):

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"
```

**File enumeration by scope:**

```bash
# --branch (default)
git diff --name-only --diff-filter=ACMR "$(git merge-base HEAD origin/<default-branch>)"..HEAD

# --staged
git diff --cached --name-only --diff-filter=ACMR

# --diff <ref>
git diff --name-only --diff-filter=ACMR "<ref>"..HEAD

# --repo
git ls-files --cached --others --exclude-standard

# --package <name> — resolve package root, then enumerate
# Language-specific: look for package.json, Cargo.toml, go.mod, pyproject.toml, etc.
```

**Filter to source files only.** Exclude:
- Binary files, images, fonts
- Generated files (`*.gen.*`, `*.pb.go`, `*_generated.*`, vendor/, node_modules/, dist/, build/)
- Lock files (`package-lock.json`, `Cargo.lock`, `go.sum`, `poetry.lock`)
- Configuration files (`*.json`, `*.yaml`, `*.yml`, `*.toml`, `*.xml`) unless they contain logic
- Markdown, documentation, and license files
- Test fixtures and snapshots (`__fixtures__/`, `__snapshots__/`, `testdata/`)

**If no source files found for the given scope:** inform the user and stop.

## Step 2: Detect Tech Stack

Auto-detect the project's language and verification commands.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
```

Run these detection checks in parallel:

| Indicator | Language | Checks to add |
|-|-|-|
| `Cargo.toml` at root | Rust | `cargo clippy -- -D warnings`, `cargo check` |
| `go.mod` at root | Go | `go vet ./...`, `go build ./...` |
| `package.json` with `tsc` dep | TypeScript | `npx tsc --noEmit` |
| `package.json` with `eslint` script | JS/TS | `npm run lint` or the eslint command |
| `pyproject.toml` or `setup.py` | Python | `ruff check .` (or `flake8`) |
| `Makefile` with `lint` target | Any | `make lint` |
| `Makefile` with `check` target | Any | `make check` |
| `Makefile` with `test` target | Any | `make test` |

**If `$ARGUMENTS` contains `--checks "<cmd1>,<cmd2>"`:** use those commands instead of auto-detected ones.

**If no checks detected and none specified:** warn the user that no verification checks were found.
Ask whether to proceed without checks or provide check commands.

Store the check list for Step 5.

## Step 3: Initialize or Resume Tracking

The tracking file enables resuming across sessions and loop compatibility.

```bash
REPO_NAME=$(basename "$REPO_ROOT")
TRACKING_FILE="/tmp/code-simplify-${REPO_NAME}.md"
```

### Resume: tracking file exists and `--reset` not in arguments

Read the tracking file. Count pending files (`- [ ]`).

| State | Action |
|-|-|
| Pending files exist | Resume from pending files (Step 4) |
| All files marked `[x]` or `[-]` | Output `ALL COMPLETE` message and stop |
| Scope mismatch (different scope than current arguments) | Warn user and ask: resume existing or start fresh? |

### Fresh start: no tracking file or `--reset`

Create the tracking file:

```markdown
# Code Simplification: <repo-name>

**Scope:** <scope description>
**Created:** <ISO timestamp>
**Tech stack:** <detected language(s)>
**Checks:** <comma-separated check commands>

## Files

- [ ] path/to/file1.ext
- [ ] path/to/file2.ext
...
```

**Sort files by directory** so related files are processed together,
increasing the chance that convention context is warm in each agent's exploration.

## Step 4: Batch Process

Pick the next batch of pending files from the tracking file — up to 10 files at once.

For each file in the batch, launch a `productivity:code-simplifier` agent in the background:

```
subagent(
  agent = "code-simplifier",
  description = "Simplify: <filename>",
  run_in_background = true,
  task = "
<assignment>
Simplify this file: <absolute-file-path>
Repository root: <REPO_ROOT>
</assignment>

<context>
Language: <detected language>
Project conventions: Read CLAUDE.md and .claude/rules/ at the repo root.
Compare with 2-3 sibling files in the same directory before making changes.
</context>

<constraints>
- Modify ONLY the assigned file — no other files.
- Preserve all functionality — no behavior changes.
- Do not commit changes.
- Do not add comments, docstrings, or type annotations to unchanged code.
- Return a structured report listing every change applied.
</constraints>
"
)
```

Wait for all agents in the batch to complete.
As each agent completes, record its report (changes applied, skipped, metrics).

**If an agent fails (timeout or error):** log the failure against that file,
mark it as `[!]` in the tracking file, and continue with the rest of the batch.

## Step 5: Verify

After the entire batch completes, run ALL verification checks from Step 2:

```bash
# Run each check command sequentially
<check-command-1>
<check-command-2>
...
```

### If all checks pass

Proceed to Step 6.

### If any check fails

1. Read the error output to identify which files and what broke.
2. Fix the issues inline — targeted edits only, no broad rewrites.
3. Re-run the failing checks.
4. Maximum 3 fix iterations per batch. If still failing after 3 attempts:
   - Revert the problematic file(s) with `git checkout -- <file>`.
   - Mark those files as `[!] <filename> -- reverted: <reason>` in the tracking file.
   - Continue with the next batch.

## Step 6: Update Tracking

For each file in the completed batch, update the tracking file:

| Outcome | Marker | Format |
|-|-|-|
| Changes applied | `[x]` | `- [x] path/to/file.ext -- <brief summary of changes> (N changes)` |
| No changes needed | `[-]` | `- [-] path/to/file.ext -- no changes needed` |
| Failed/reverted | `[!]` | `- [!] path/to/file.ext -- reverted: <reason>` |

### Check completion

Count remaining `- [ ]` entries.

| Remaining | Action |
|-|-|
| More pending files | Return to Step 4 for the next batch |
| None remaining | Proceed to Step 7 |

## Step 7: Report

Present a summary of all simplification work:

```markdown
## Code Simplification Complete

**Scope:** <scope description>
**Files processed:** N total (M simplified, K unchanged, J failed)
**Tracking file:** /tmp/code-simplify-<repo-name>.md

### Changes by Category
| Category | Count |
|-|-|
| Dead code removal | N |
| Complexity reduction | N |
| Naming improvements | N |
| Control flow | N |
| Magic values | N |
| ... | ... |

### Files Simplified
1. `path/to/file.ext` -- <summary> (N changes)
2. ...

### Files Unchanged
- `path/to/file.ext` -- no changes needed

### Files Failed
- `path/to/file.ext` -- reverted: <reason>

### Verification
All checks passed: <yes/no>
```

Omit any section with no entries.

**If running in a loop** (invoked via the loop skill):
output `ALL COMPLETE -- cancel this loop with CronDelete` as the final line.

## Error Handling

| Error | Action |
|-|-|
| No source files found for scope | Inform user with the scope used and suggest alternatives |
| File path does not exist | Report the exact path and stop |
| Package/module not found | List available packages and ask user to pick one |
| No verification checks detected | Warn and ask: proceed without checks or provide commands? |
| Agent timeout on a file | Mark file as `[!]` with timeout reason, continue with batch |
| Verification fails after 3 fix attempts | Revert problematic files, mark as `[!]`, continue |
| Tracking file exists with different scope | Ask user: resume existing scope or `--reset` for fresh start |
| Git not available | Inform user that git is required for branch/staged/diff scopes |
| `--repo` on large codebase (>500 files) | Warn user about the scale, ask for confirmation before proceeding |
