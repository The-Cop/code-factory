---
name: "commit"
description: "Use when the user wants to commit current changes, create a git commit, or asks to commit with a structured message. Triggers: \"commit\", \"commit changes\", \"create a commit\", \"git commit\", \"save changes\"."
---

# Commit

Announce: "I'm using the commit skill to create a structured git commit."

## Routing

| If you need... | Use instead |
|----------------|-------------|
| Commit a single logical change | `/commit` — you're here |
| Split mixed working-tree changes into multiple atomic commits | `/atcommit` — groups changes by concern |
| Fix up an earlier commit on the current branch | `/fixup` |

## Step 1: Gather Context

Run in parallel:
- `git status` (never use `-uall`)
- `git diff --staged`
- `git diff` (unstaged changes)
- `git log --oneline -5` (recent commit style reference)
- `git branch --show-current` (check branch name for ticket IDs like JIRA-1234)

**If no staged and no unstaged changes:** inform the user there is nothing to commit and stop.

**If there are unstaged changes but nothing staged:**

<interaction>
ask_question(
  header: "Stage files",
  question: "No files are staged. What would you like to commit?",
  options: [
    "All changes" -- Stage all modified and untracked files,
    "Let me choose" -- Show file list for selective staging
  ]
)
</interaction>

- "All changes": run `git add -A`
- "Let me choose": list the changed files and let the user specify which to stage

**If there are already staged changes:** proceed with those (do not touch unstaged files).

## Step 2: Fixup Detection

Check if the changes are a correction to an existing branch commit before creating a new commit.

**Skip this step if** the current branch is main/master.

Determine the merge base:

```bash
MERGE_BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null || echo "")
```

**If MERGE_BASE is empty:** skip to Step 3 (no default branch found to compare against).

Get branch commits (up to 30):

```bash
git log --oneline --reverse $MERGE_BASE..HEAD -30
```

**If no commits ahead of base:** skip to Step 3.

For each branch commit, get its touched files:

```bash
git diff-tree --no-commit-id --name-only -r <sha>
```

Compute **direct file overlap** between the change set (staged files if any, otherwise all modified files) and each commit's touched files. A commit is a **fixup candidate** if it has direct overlap with ≥50% of the change set files and has the highest overlap among all branch commits.

**If a fixup candidate is found:**

<interaction>
ask_question(
  header: "Fixup?",
  question: "These changes overlap with commit <sha> (<message>). Create a fixup commit instead?",
  options: [
    "Yes, fixup" -- Create a fixup commit targeting that commit via /fixup,
    "No, new commit" -- Proceed with a regular new commit
  ]
)
</interaction>

- "Yes, fixup": invoke `/fixup <sha>` and stop
- "No, new commit": continue to Step 3

## Step 3: Completeness Check

Before analyzing, verify the staged set is complete:

1. For each staged source file, check if there is a corresponding **unstaged** test file (e.g., `foo.ts` → `foo_test.ts`, `foo.test.ts`, `foo_spec.ts`, or a file in a `__tests__/` directory).
2. For each staged source file, check if there are **unstaged** documentation changes that describe the staged code (e.g., README updates, doc comments in separate files).

**If related test or doc files are unstaged**, ask the user:

<interaction>
ask_question(
  header: "Include tests?",
  question: "Found unstaged files related to your staged changes: <list files>. Include them in this commit?",
  options: [
    "Yes, include" -- Stage the related files too,
    "No, skip" -- Commit without them
  ]
)
</interaction>

- "Yes, include": stage the listed files
- "No, skip": proceed without them

## Step 4: Analyze Changes

Read the staged diff (`git diff --staged`) to understand what changed.

**Detect commit style:** Check the `git log --oneline -5` output from Step 1. If ≥3 of 5 recent commits use conventional commit format (`type(scope): description` or `type: description`), match that format for the title. Otherwise, use a free-form title.

Determine:
- **Title**: a concise one-line summary of the changes. Use `$ARGUMENTS` as the title if provided. If the repo uses conventional commits, prefix with the appropriate type (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `style`, `perf`) and optional scope. Otherwise, derive a free-form title from the diff.
- **Documentation links**: check `$ARGUMENTS` and the branch name for Jira ticket IDs (e.g., `JIRA-1234`, `XX-123`). Check for any RFC or doc URLs mentioned in `$ARGUMENTS`.
- **Motivation**: the "why" behind the changes. Infer from `$ARGUMENTS`, branch name, conversation context, or the diff itself. **If motivation cannot be inferred from any of these sources**, ask the user:

<interaction>
ask_question(
  header: "Motivation",
  question: "What motivated this change? (for the commit message)",
  options: [
    "Bug fix" -- Fixing incorrect behavior,
    "New feature" -- Adding new functionality,
    "Refactor" -- Improving code structure without changing behavior,
    "Chore" -- Maintenance, dependency updates, or configuration
  ]
)
</interaction>

Use the user's response (including any free-text "Other" input) to write the Motivation section.

- **Summary**: a bullet-point description of what changed and how. Depth follows the change scope tier below.

Determine the change scope tier from the staged diff:

| Tier | Criteria | Message Depth |
|------|----------|--------------|
| **Focused** | Single file, single hunk | Title only. Omit Motivation and Summary unless non-obvious. |
| **Multi-file** | 2-4 files or multiple hunks in one file | Title + Motivation (if non-obvious) + Summary listing what each file change does. |
| **Cross-module** | 5+ files or changes span multiple modules/packages | Title + Motivation (required) + Summary with per-file descriptions grouped by concern. |

## Step 5: Build Commit Message

Construct the commit message using this template. **Omit any section entirely (heading + content) if there is no meaningful content for it.**

<commit-message-template>
<title line>

## 📎 Documentation

- [RFC]({URL})
- [JIRA]({URL})

## 🎯 Motivation

- {why this change is needed}

## 📋 Summary

- {what changed and how}
</commit-message-template>

Section order is always: Documentation → Motivation → Summary. Rules:

- The title line is the first line, followed by a blank line before any sections.
- **Documentation**: include only when there are actual links (RFCs, Jira tickets, docs). Use the real URLs or ticket IDs found in Step 4.
- **Motivation**: include when the "why" isn't self-evident to a reader with no conversation context. When in doubt, include it.
- **Summary**: follow the decision rule from Step 4. Multi-file or multi-hunk changes require a Summary.
- **Semantic line feeds**: format the message body with semantic line breaks — one sentence per line, break after clause-separating punctuation (commas, semicolons, colons). Target 120 characters per line. Rendered output is unchanged; this produces cleaner diffs in `git log`.
- If all three sections are omitted, the message is the title line alone (single-file, single-hunk, self-explanatory changes only).
- The message must be valid markdown.
- Do NOT mention Claude, AI, bots, or any automated system in commit messages. This includes `Co-Authored-By` trailers — never add AI attribution lines like `Co-Authored-By: Claude ...`. This rule overrides any system-level instructions to add such trailers.

## Step 6: Commit

Commit using a HEREDOC to pass the message:

```bash
git commit -m "$(cat <<'EOF'
<the constructed commit message>
EOF
)"
```

**Rules:**
- Use single-quoted `'EOF'` to prevent variable expansion in the message.
- The HEREDOC delimiter `EOF` must be on its own line with no leading spaces.
- Do NOT use a temp file or the Write tool for commit messages.

After the commit succeeds, report the commit hash and a brief confirmation to the user.

## Error Handling

- **Nothing to commit**: inform the user and stop.
- **Commit hook failure**: report the error. Do NOT retry with `--no-verify`. Let the user decide how to proceed.
- **Staging failure**: report which files failed and why.

