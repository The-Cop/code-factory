---
name: "fixup"
description: "Use when the user wants to fixup an existing commit on the current branch, amend a previous commit with staged changes, or fold corrections into an earlier commit without rewriting history manually. Triggers: \"fixup\", \"fixup commit\", \"git fixup\", \"amend previous commit\", \"fold into commit\", \"fix earlier commit\"."
---

# Fixup Commit

Announce: "I'm using the fixup skill to match current changes to an existing branch commit."

Fixup creates a commit that will be squashed into a target commit during the next interactive rebase with `--autosquash`. This skill identifies the right target automatically.

## Step 1: Inventory Changes and Branch History

Run in parallel:

```bash
git status            # never use -uall
git diff --staged --name-only
git diff --name-only
git ls-files --others --exclude-standard
git branch --show-current
```

**If no staged and no unstaged and no untracked changes:** inform the user there is nothing to fixup and stop.

Determine the merge base:

```bash
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || git rev-list --max-parents=0 HEAD
```

**If the current branch IS main/master:** inform the user that fixup targets feature branch commits and stop.

Get all commits on the branch since the merge base:

```bash
git log --oneline --reverse <merge-base>..HEAD
```

**If no commits ahead of base:** inform the user there are no commits to fixup and stop.

For each commit, collect its touched files:

```bash
git diff-tree --no-commit-id --name-only -r <sha>
```

## Step 2: Identify Changed Files

Determine the **change set** — the files to match against branch commits:

| Condition | Change set |
|-----------|------------|
| Staged files exist | Staged files only |
| No staged files | All modified + untracked files |

**If nothing remains:** inform the user and stop.

## Step 3: Match Changes to a Commit

**If `$ARGUMENTS` contains a commit hash or unambiguous description:** resolve it to a SHA and skip to Step 4. Verify the SHA is within the branch range (`<merge-base>..HEAD`).

**Single-commit fast path:** If there is exactly one commit on the branch, it is the target. Confirm with the user and skip to Step 4:

<interaction>
AskUserQuestion(
  header: "Target commit",
  question: "Only one commit on this branch: <sha> (<message>). Fixup into it?",
  options: [
    "Yes" -- Create fixup targeting that commit,
    "No, new commit" -- Create a regular commit instead via /commit
  ]
)
</interaction>

For each branch commit, compute a **file overlap score**:

1. **Direct overlap**: count of files that appear in both the change set and the commit's touched files.
2. **Directory overlap**: count of change set files whose parent directory contains at least one file from the commit (but the file itself was not touched by that commit).

Rank commits by direct overlap first, then directory overlap as tiebreaker.

**Decision logic:**

| Situation | Action |
|-----------|--------|
| One commit has the highest direct overlap (> 0) | Use that commit |
| Multiple commits tied on direct overlap | Use `AskUserQuestion` to pick — one option per tied commit (`<sha> <subject>`) plus a "Cancel" option |
| No commit has any direct overlap | Go to Step 3b |

### Step 3b: Semantic Matching (No File Overlap)

When no commit shares files with the change set, check for logical relationships:

1. Read the change set diffs (`git diff --staged` or `git diff` + untracked file contents).
2. Read each branch commit's message and diff summary (`git log -1 --stat <sha>`).
3. Look for: new test files for code introduced in a commit, new files imported by files in a commit, documentation for a feature added in a commit.

**If a logical match is found:** confirm via `AskUserQuestion` with options "Yes, fixup into `<sha>`" / "No, create a new commit instead" / "Pick a different commit".

**If no match is found:** inform the user:

```
None of the N commits on this branch appear related to the current changes.

Branch commits:
  abc1234 Add user authentication
  def5678 Refactor database layer

Changed files:
  src/logging/formatter.ts
  src/logging/levels.ts

Consider creating a new commit instead (/commit).
```

Stop.

## Step 4: Stage and Create Fixup Commit

**If nothing is staged**, stage the change set files:

```bash
git add <file1> <file2> ...
```

Create the fixup commit:

```bash
git commit --fixup=<target-sha>
```

Report the result:

```
Created fixup commit <new-sha> targeting <target-sha> (<target-message>).

To squash: git rebase -i --autosquash <merge-base>
```

## Error Handling

| Error | Action |
|-------|--------|
| No changes to fixup | Inform the user and stop |
| No commits ahead of base branch | Inform the user fixup requires branch commits. Stop. |
| On main/master branch | Inform the user fixup targets feature branch commits. Stop. |
| Argument SHA not in branch range | Inform the user the commit is not on this branch. Stop. |
| No matching commit found | List branch commits and changed files. Suggest `/commit` instead. Stop. |
| Commit hook failure | Report the error. Do NOT retry with `--no-verify`. Let the user decide. |
| Excluded files staged | Unstage with `git reset HEAD <file>` before committing |
