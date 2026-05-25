---
name: "review"
description: "Use when user says \"review pr\", \"review pull request\", \"pr review\", \"review #123\", or provides a PR number, URL, or branch name to review. Supports --codex and --claude-codex to delegate or cross-check with Codex, --parallel to fan out one sub-agent per review dimension, and --extended to review every line of changed files instead of just the diff hunks."
---

# Review PR

Announce: "I'm using the review skill to review a GitHub pull request."

## Context

- Current branch: !`git branch --show-current`
- Repository: !`basename $(git rev-parse --show-toplevel)`
- Remote URL: !`git remote get-url origin 2>/dev/null || echo "no remote"`

## Routing

| If you need... | Use instead |
|----------------|-------------|
| Address PR review feedback | `/pr-fix` |
| Run Codex review against local working tree only | `/codex:review` |
| Delegate an arbitrary task to Codex | `/codex:rescue` |

## Step 1: Parse Arguments

Tokenize `$ARGUMENTS` on whitespace and classify each token:

| Token | Bucket |
|-------|--------|
| `--codex` | `MODE=codex` |
| `--claude-codex` or `--dual` | `MODE=claude-codex` |
| `--parallel` | `PARALLEL=true` (fan out one sub-agent per level in the Claude review) |
| `--extended` | `SCOPE=extended` (review every line of every changed file, not just diff hunks) |
| `--no-worktree` | `WORKTREE=false` (diff-only fallback) |
| Pure digits | `PR_REF=<digits>` |
| Matches `github.com/.*/pull/(\d+)` | `PR_REF=$1` |
| Anything else, non-flag | candidate branch name → `PR_REF` |

Rules:
- Default `MODE=claude`, `WORKTREE=true`, `PARALLEL=false`, `SCOPE=diff` (changed hunks plus immediate context).
- `--codex` and `--claude-codex` are mutually exclusive — error and ask the user to pick one if both appear.
- `--parallel` applies to the Claude branch only.
  In `MODE=codex` it is a no-op and the skill warns the user.
  In `MODE=claude-codex` only the Claude half fans out.
- `--extended` applies to both Claude and Codex paths.
  In `WORKTREE=false` mode it is a no-op (no file access) and the skill warns the user.
- If multiple non-flag tokens appear, treat the first as `PR_REF` and warn about the rest.
- If `PR_REF` is empty after parsing, fall through to current-branch detection in Step 3.

## Step 2: Verify Prerequisites

Run in parallel:
- `gh auth status 2>&1`
- `git rev-parse --show-toplevel 2>&1`
- If `MODE` is `codex` or `claude-codex`: `command -v codex 2>&1`

**If `gh` is not installed or not authenticated:** inform the user (`gh auth login`). Stop.

**If not a git repository:** inform the user. Stop.

**If `codex` CLI is unavailable in a Codex mode:**
- `MODE=codex` → warn: "Codex CLI not installed. Falling back to Claude review." Set `MODE=claude`.
- `MODE=claude-codex` → warn: "Codex CLI not installed. Running Claude-only." Set `MODE=claude`.

## Step 3: Identify the PR

Determine the PR from `PR_REF`:

| Input | Action |
|-------|--------|
| Number | Use directly |
| URL extracted in Step 1 | Already a number |
| Branch name | `gh pr list --head <branch> --json number --jq '.[0].number'` |
| Empty | `gh pr view --json number --jq '.number' 2>/dev/null` |

**If no PR found:** use `AskUserQuestion` to request a PR number, URL, or branch name. List recent PRs with `gh pr list --limit 5` as suggestions.

Bind the resolved number to `PR_NUMBER`.

## Step 4: Fetch PR Metadata and Diff

Run in parallel:

```bash
gh pr view "$PR_NUMBER" --json title,body,baseRefName,headRefName,headRefOid,author,additions,deletions,changedFiles,url,labels,closingIssuesReferences,files
gh pr diff "$PR_NUMBER"
```

Bind:
- `PR_TITLE`, `PR_BODY`, `BASE_REF`, `HEAD_REF`, `PR_HEAD_SHA` from the JSON.
- `CHANGED_FILES` from `.files[].path`.
- `LINKED_ISSUES` from `.closingIssuesReferences[].number` (if present).

If the diff is empty or binary-only, report and stop after listing the binary files.

## Step 5: Create Isolated Worktree

If `WORKTREE=false` (explicit `--no-worktree`), skip this step and operate on the diff only.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
WT_DIR="$REPO_ROOT/../worktrees"
mkdir -p "$WT_DIR"
WT_PATH="$WT_DIR/${REPO_NAME}-review-pr-${PR_NUMBER}"

# Idempotent: remove any stale worktree from a previous run
git worktree remove --force "$WT_PATH" 2>/dev/null || true

# Fetch the exact head SHA so the worktree is pinned even if the PR updates mid-review
git fetch origin "pull/${PR_NUMBER}/head"
git worktree add --detach "$WT_PATH" "$PR_HEAD_SHA"
```

The worktree lives in `$REPO_ROOT/../worktrees/`, parallel to the repo, matching the convention used by `/worktree`.
The user's main checkout is untouched — uncommitted changes in their working tree are independent of the worktree.

**If `git worktree add` fails:** warn the user, set `WORKTREE=false`, and continue in diff-only mode. Codex will receive `Worktree: diff-only fallback` in its prompt.

All `Read`, `Grep`, and `Glob` calls during review must anchor on `$WT_PATH` when the worktree exists.

## Step 6: Extract PR Intent

Read in this order:
1. `PR_TITLE`
2. `PR_BODY`
3. Linked issues: `gh issue view <num>` for each entry in `LINKED_ISSUES`
4. Test files in the diff (added or modified `*_test.*`, `*.test.*`, `tests/`)
5. The diff itself as a signal of last resort

State the intent in 2-4 sentences. End with one of:
- "Stated explicitly in the PR body."
- "Inferred from diff — see Uncertainty below."

If inferred, add an **Uncertainty** block listing the signals used and any alternative interpretations rejected.

Keep this intent visible throughout the review.
Judge every change against it.

## Step 7: Build File Inventory

Initialize a coverage checklist from `CHANGED_FILES`:

| # | File | Module | Reviewed |
|---|------|--------|----------|
| 1 | `path/a.go` | <pending> | ☐ |
| 2 | `path/b.go` | <pending> | ☐ |

Every changed file must end the review with `Reviewed: ✓`.
A file is not reviewed until it appears under a Module section in the output.

## Step 8: Infer Logical Modules

Group `CHANGED_FILES` into modules by:
1. Package or import cohesion (e.g., all files importing the same internal package).
2. Naming and directory locality (files under `internal/auth/` typically form one module).
3. Functional intent (e.g., "session handling" may span `auth/`, `middleware/`, and `tests/`).

A module may span directories.
A directory may split into multiple modules if it contains unrelated changes.

Record `(module-name → [files])` and update the coverage table's Module column.

## Step 9: Mode Dispatch

| Mode | Action |
|------|--------|
| `claude` (default) | Step 10a only |
| `codex` | Step 10b only |
| `claude-codex` | Step 10a and Step 10b in parallel; merge in Step 10c |

## Step 10a: Claude Review

Apply the three-level framework (see `references/three-level-framework.md`) module by module.
The review runs in two passes per module followed by a single global self-audit.
Read the enumeration discipline section in `references/three-level-framework.md` before starting.

Determine the review scope from `SCOPE`:

| Scope | Read budget |
|-------|-------------|
| `diff` (default) | Changed hunks plus surrounding context needed to evaluate them. Typical: the function or block enclosing each hunk, plus any function the hunk calls into within the module. |
| `extended` | Every line of every changed file in the module. Pre-existing issues outside the hunks are reportable. |

### Step 10a.1: Per-module Pass 1 (Enumerate)

When `PARALLEL=false` (default), for each module, in a single agent:

1. Read the files in the module from `$WT_PATH` (or from the diff if `WORKTREE=false`),
   honoring the scope budget above.
2. For each check in the three-level framework, in order:
   - Scan the module's read budget for that check.
   - Append every instance found as a row in the module's findings table.
   - If no instance is found, do not skip — mark the check as `✓ scanned` in the per-check audit table.
3. Do not merge similar findings.
   Do not cap.
   Do not produce a "top issues" digest.
4. Record findings with Level, Severity (Critical/Major/Minor), Confidence (HIGH/MEDIUM/LOW),
   Location, Issue, Why, Impact, Best Fix.
5. Identify missing or insufficient tests and follow-up cleanup needed before merge.
6. Tick the file coverage checklist for each file reviewed.

When `PARALLEL=true`, replace the per-module loop with one `Task` call per level,
launched in a single message (all three sub-agents run concurrently):

```
Task(
  subagent_type = "general-purpose",
  description = "Review module <module-name>: Level <N>",
  prompt = <prompt including module files, scope budget, the specific level's
            checks from three-level-framework.md, and the required findings
            table format from output-format.md>
)
```

The three sub-agents per module are:

| Sub-agent | Checks |
|-----------|--------|
| Level 1 (Intent) | Alignment, Scope creep, Missing pieces, Surprise, Test alignment |
| Level 2 (Logic) | Control flow, Nil/null/zero, Error paths, Invariants, Concurrency, Ordering, Edge cases, Backward compatibility, Old/new interactions, Idempotency |
| Level 3 (Quality) | Duplication, Magic values, Dead code, Abstractions, Naming, Patterns, Error handling, Security, Performance, Test quality, Test seams |

Each sub-agent returns a partial findings table and a partial per-check audit table.
Merge them into the module's single findings table and per-check audit table.
Preserve every row — do not collapse, do not deduplicate by line.

### Step 10a.2: Pass 2 (Self-audit)

After Pass 1 completes for every module, run a single self-audit sweep in the main agent.

For each module:

1. Re-open every changed file in the module within the same scope budget.
2. Re-read each file with Pass 1's findings in mind.
3. Specifically scan for the categories most often missed in Pass 1:
   - Cross-file issues: the same defect repeated across sibling files in the module.
   - Old/new code interactions: defects exposed by the diff that live on lines the diff did not modify.
   - Test gaps: behavior added without an assertion, or assertions that only check presence.
   - Error wrapping and propagation: errors returned without context, dropped at a boundary, or logged and swallowed.
   - Dead code, magic values, and stale comments left behind by the diff.
4. Append new findings to the same module findings table.
5. Re-tick any per-check audit row that flipped from `✓ scanned` to `✓ findings`.

Pass 2 may produce zero new findings; that is the desired outcome.
Do not pad.

### Step 10a.3: Render

Render output using the single-reviewer template in `references/output-format.md`.
Include the per-check audit table for every module.
A module is not complete in the output until every row in its audit table is ticked.

## Step 10b: Codex Review

Delegate to the `codex:codex-rescue` subagent in background mode, then poll for completion.
The exact prompt template lives in `references/codex-delegation.md`.

A foreground Codex call dies at the default 120s Bash timeout because real PRs take 3-15+ minutes.
Background mode forks a detached worker and returns in seconds, so the Bash timeout never fires.

### Step 10b.1: Delegate (background)

```
Task(
  subagent = "codex-rescue",
  description = "Codex PR review: #<PR_NUMBER>",
  prompt = "--background\n\n" + <template with PR_TITLE, PR Intent, refs, worktree path, framework, output format, and full PR diff>
)
```

The literal first line `--background` followed by a blank line is a routing flag the rescue subagent strips before forwarding to `codex-companion task --background`.
The Task returns within ~5-15 seconds with stdout matching:

```
<title> started in the background as <jobId>. Check /codex:status <jobId> for progress.
```

### Step 10b.2: Parse jobId

Match the regex `started in the background as ([a-zA-Z0-9_-]+)\b` against the rescue stdout.
Bind the captured group to `JOB_ID`.

If no match (or the rescue returns empty stdout), apply the Codex empty-stdout fallback below and skip Steps 10b.3 and 10b.4.

### Step 10b.3: Poll for terminal state

Loop until terminal state. Each iteration:

1. `Skill(skill="codex:status", args="<JOB_ID> --wait --timeout-ms 100000")`.
   Server-side `--wait` blocks until terminal or 100s elapse, safely under the 120s Bash kill.
2. Parse `Status:` with the regex `/Status:\s+(queued|running|completed|failed|cancelled)\b/i`.
3. Branch on the captured status:

| Status | Action |
|--------|--------|
| `completed` | Exit loop. Proceed to Step 10b.4. |
| `failed` | Apply Codex empty-stdout fallback. Stop. |
| `cancelled` | Apply Codex empty-stdout fallback. Stop. |
| `queued` | Continue loop. Increment a `queued_streak` counter. |
| `running` | Continue loop. Reset `queued_streak` to 0. |
| Unparseable | Apply Codex empty-stdout fallback. Stop. |

Watchdog: if `queued_streak` reaches 6 (the job never started running), report `Codex job <JOB_ID> never started` and apply the fallback.

Progress note: every 6 iterations (~10 min elapsed), emit a single line to the user:
`Codex job <JOB_ID> still running after ~N minutes; continuing to poll`.

There is no upper iteration bound — the loop exits only on a terminal state, the queued watchdog, or a parse failure.
The job is never auto-cancelled; the user can recover the result later via `/codex:result <JOB_ID>`.

### Step 10b.4: Fetch result

`Skill(skill="codex:result", args="<JOB_ID>")`

Pass Codex's stdout through verbatim.
Do not paraphrase, summarize, or add commentary before or after.

### Codex empty-stdout fallback

Shared by Steps 10b.2, 10b.3, and 10b.4:
- `MODE=codex` → ask the user via `AskUserQuestion` whether to retry with Claude.
- `MODE=claude-codex` → continue with Claude-only output, prefixed with `Codex unavailable; Claude-only`.

## Step 10c: Merge Dual Reviews

When `MODE=claude-codex` and both reviews succeed, render the dual-reviewer template from `references/output-format.md`:

1. Single PR Intent section (Claude's extraction is the source of truth).
2. Single File Coverage Checklist (each row ✓ only if both reviewers covered it).
3. Reviewer Comparison table (verdict, finding counts, unique findings, agreed findings).
4. Reconciliation section if reviewers disagree (1-3 sentences tied to PR Intent).
5. Combined Verdict line: `Claude: <verdict> | Codex: <verdict>`.
6. Full reviews under collapsible `<details>` blocks.

## Step 11: Cleanup Worktree

Always run, even on error:

```bash
git worktree remove --force "$WT_PATH" 2>/dev/null || true
git worktree prune
```

Verify with `git worktree list` — `$WT_PATH` must not appear.

## Step 12: Present Output

Render the review to the user.
Do NOT post it as a GitHub comment automatically.
Apply semantic line breaks: one sentence per line, break after clause-separating punctuation, target 120 characters per line.

If no findings exist at any level, state that and recommend approval.

## Rules

- Reference exact file paths and line numbers.
- Cite findings from the worktree contents when available, not from the diff alone.
- Be constructive: every issue includes a concrete fix.
- Every changed file must end the review marked `Reviewed: ✓`.
- The three-level framework applies to every PR uniformly — depth does not scale down for small PRs.
- Do not cap findings.
  If a module has 30 minor issues, list 30 minor issues.
- Do not collapse repeated instances.
  If the same defect appears at five locations, write five rows with five locations.
- Do not produce a "top issues" or "key findings" view.
  The findings table is the report, not a digest of it.
- Every check in the three-level framework must show a tick in the per-check audit table
  for every module — either `✓ findings` or `✓ scanned`.
- Re-running `/review` on the same PR with no edits must produce the same finding list.
  If the second run surfaces a new finding, the first run violated the enumeration discipline.

## Error Handling

| Error | Action |
|-------|--------|
| `gh` not installed/authenticated | Inform user to run `gh auth login`. Stop. |
| Both `--codex` and `--claude-codex` present | Ask user to pick one. Stop. |
| `--parallel` with `MODE=codex` | Warn that `--parallel` is a no-op in Codex-only mode. Continue without fanout. |
| `--extended` with `WORKTREE=false` | Warn that `--extended` is a no-op without a worktree. Continue with diff-only scope. |
| A `--parallel` sub-agent fails | Re-run that level inline in the main agent. Do not drop the level. |
| PR not found | Report. List recent PRs with `gh pr list --limit 5`. |
| Empty or binary-only diff | Report "no reviewable text changes". List binary files. Cleanup worktree if created. |
| `git worktree add` fails | Warn, fall back to diff-only mode, continue. |
| `codex` CLI missing in Codex mode | Warn and fall back to Claude (see Step 2). |
| Codex rescue returns empty stdout (delegate step) | Report failure. Apply Codex empty-stdout fallback. |
| Rescue stdout missing jobId pattern | Report "Codex review failed (no jobId)". Apply Codex empty-stdout fallback. |
| `/codex:status` output cannot be parsed | Treat as failure. Apply Codex empty-stdout fallback. |
| Codex job status `failed` or `cancelled` | Report `Codex job <id> <status>`. Apply Codex empty-stdout fallback. |
| Codex job remains `queued` for 6 consecutive polls | Report worker-launch failure. Apply Codex empty-stdout fallback. |
| Stale worktree from prior run | `git worktree remove --force` then retry (built into Step 5). |
| Network/API failure | Report `gh` error. Cleanup worktree. Let user retry. |
