---
name: pr-fix
description: >
  Use when the user wants to address PR review feedback, fix PR comments, resolve review threads,
  or respond to code review suggestions on a pull request.
  Supports opt-out flags (--no-comments, --no-bot-reviews, --no-ci) and autonomous modes (--auto, --auto-human).
  Triggers: "fix pr feedback", "address pr comments", "resolve pr reviews", "pr fix",
  "address review feedback", "fix review comments", "handle pr feedback",
  "respond to pr review", "address pr feedback", "pr fix --auto".
argument-hint: "[PR number, URL, or comment URL, optional --reviewer <name>, optional --no-comments, --no-bot-reviews, --no-ci, --auto, --auto-human]"
user-invocable: true
allowed-tools: Bash(git:*), Bash(gh:*), Bash(get_ddci_logs.sh:*), Bash(./scripts/*), Read, Write, Edit, Grep, Glob, AskUserQuestion, Task
---

# Fix PR Feedback

Announce: "I'm using the pr-fix skill to address PR review feedback."

## Routing

| If you need... | Use instead |
|----------------|-------------|
| Review a PR and produce feedback | `/review` — read-only analysis with structured findings |
| Address existing PR review comments | `/pr-fix` — you're here |
| Fix CI failures not tied to review feedback | Use the CI validation loop directly (see references) |

## Step 1: Gather Context

Parse `$ARGUMENTS` for:

| Input | Pattern | Example |
|-------|---------|---------|
| PR number | Digits | `42`, `332190` |
| PR URL | `github.com/.*/pull/\d+` | `https://github.com/org/repo/pull/42` |
| Comment URL | `github.com/.*/pull/\d+#discussion_r\d+` | `https://github.com/org/repo/pull/42#discussion_r123` |
| Reviewer filter | `--reviewer <name>` | `--reviewer alice` |
| Skip comments | `--no-comments` | `--no-comments` |
| Skip bot reviews | `--no-bot-reviews` | `--no-bot-reviews` |
| Skip CI loop | `--no-ci` | `--no-ci` |
| Autonomous mode | `--auto` | `--auto` |
| Full autonomous mode | `--auto-human` | `--auto-human` |

### Flag Behavior

**Default (no flags):** All features enabled with interactive prompts. Address human review comments (Steps 2-7),
trigger bot reviews (Step 8a+8c), and monitor CI (Step 8b) -- each with a user prompt before proceeding.

**Opt-out flags** control which features run:

| Flag | Effect |
|------|--------|
| `--no-comments` | Skip human review comment addressing (Steps 2-7). Jump straight to Step 8. |
| `--no-bot-reviews` | Skip bot review trigger/fix loop (Steps 8a + 8c). |
| `--no-ci` | Skip CI validation loop (Step 8b). |

Opt-out flags compose freely: `--no-bot-reviews --no-ci` runs only comment addressing.
`--no-comments --no-ci` runs only the bot review loop.

**Autonomous modes** control prompting, composable with opt-out flags:

| Flag | Effect |
|------|--------|
| `--auto` | Skip interactive prompts for bot reviews and CI. Human review threads still prompt. |
| `--auto-human` | Implies `--auto`. Also skips prompts for human review threads. Defaults: "Fix all" for non-disagreements, "Explain and keep" for disagreements. |

Examples: `--auto --no-ci` = address comments interactively + auto bot review loop, no CI.
`--auto-human --no-bot-reviews` = fully autonomous comment addressing + CI loop, no bot reviews.

Run in parallel:

- `gh auth status 2>&1`
- `gh repo view --json nameWithOwner -q '.nameWithOwner'` (split on `/` to get `{owner}` and `{repo}` for API calls)
- `git branch --show-current`
- `git status --short`

**If `gh` is not authenticated:** inform the user to run `gh auth login`. Stop.

**If no PR number provided:** detect from current branch:

```bash
gh pr view --json number -q '.number' 2>/dev/null
```

**If still no PR:** ask the user for the PR number. Stop.

Once the PR is identified, capture context for failure classification and conflict detection:

```bash
# Run in parallel
gh pr view {number} --json baseRefName,mergeable,mergeStateStatus
git diff --name-only origin/{base}...HEAD
```

Save the changed-files list — it is used throughout for CI failure classification (PR-related vs pre-existing) and pattern scanning in Step 5.

**If `mergeable` is `CONFLICTING`:** resolve conflicts before proceeding. Invoke `/fix-conflicts`, then push the resolved merge commit. Re-fetch the changed-files list after resolution since the diff may have grown.

### Flag Routing

Determine which steps to execute based on parsed flags:

| Condition | Steps to execute |
|-----------|-----------------|
| `--no-comments` set | Skip Steps 2-7. Jump to Step 8. |
| `--no-bot-reviews` set | Skip Steps 8a + 8c. |
| `--no-ci` set | Skip Step 8b. |
| `--no-comments` + `--no-bot-reviews` + `--no-ci` | Nothing to do. Inform user and stop. |

If all of Step 8 is skipped (`--no-bot-reviews` + `--no-ci`), stop after Step 7 (commit and push).
If `--no-comments` is set and all of Step 8 is also skipped, inform the user that all features are disabled and stop.

## Step 2: Fetch Unresolved Review Threads

**If `--no-comments` is set:** skip to Step 8.

Fetch actionable review threads using the `get-pr-comments.sh` script. The script handles GraphQL pagination, structured output, and large-output fallback automatically.

```bash
./get-pr-comments.sh -a {number}
```

For comment URLs, pass the full URL instead of the PR number:

```bash
./get-pr-comments.sh -a "https://github.com/org/repo/pull/42#discussion_r123"
```

**If output exceeds 25KB:** the script writes to `/tmp/pr-comments-{owner}-{repo}-{pr}.json` and prints a message to stderr. Use the Read tool to load the data from that path.

The script returns a JSON array of threads. Each thread contains:

| Field | Usage |
|-------|-------|
| `thread_id` | GraphQL node ID — pass to `resolveReviewThread` mutation |
| `first_comment_id` | REST API comment ID — pass to reply endpoint |
| `resolved` | Always `false` when using `-a` flag |
| `outdated` | Always `false` when using `-a` flag |
| `path` | File path relative to repo root |
| `line` | End line number in the diff |
| `start_line` | Start line for multi-line comments (null = single line) |
| `comments[]` | Array of `{ comment_id, body, author, outdated, path, line, html_url }` |

**If `--reviewer` specified:** filter the output:

```bash
echo "$THREADS" | jq '[.[] | select(.comments[0].author == "{reviewer}")]'
```

**If no threads returned:** all review threads are resolved. Skip to Step 8 (unless Step 8 is also fully skipped by flags).

## Step 3: Categorize and Prioritize

Classify each thread into one of four categories:

| Category | Signals | Action |
|----------|---------|--------|
| **Suggestion** | Body contains `` ```suggestion `` block | Apply the suggested code change |
| **Code change** | Imperative language ("change X", "add Y", "remove Z"), bug report, missing handling | Edit the code as requested |
| **Question** | Ends with `?`, asks "why", requests clarification | Respond with explanation |
| **Disagreement** | Reviewer challenges a design decision, requests a revert or alternative approach | **NEVER auto-resolve.** Present to user for decision. |
| **Outdated** | Thread `outdated` is true or all comments have `outdated: true` | Read current code at `path`. If the concern is already addressed, resolve with a note. If not, reclassify as Code change or Question. |

Assign priority:

| Priority | Criteria |
|----------|----------|
| **P0** | Bugs, security issues, breaking changes, data integrity |
| **P1** | Refactoring with clear benefit, naming/clarity, type safety, missing error handling |
| **P2** | Nits, style preferences, minor optimizations, "for next time" suggestions |

## Step 4: Present Summary and Get Direction

Show the user a concise summary:

```
PR #{number}: {title}
{total} unresolved threads ({reviewer filter if applied})

P0 (Critical):  {count} — {brief descriptions}
P1 (Should fix): {count} — {brief descriptions}
P2 (Nice to have): {count} — {brief descriptions}

Proposed actions:
- Apply suggestions: {count}
- Code changes: {count}
- Respond with explanation: {count}
- Need your decision: {count} (disagreements)
```

**If `--auto-human` mode:** Skip all prompts. Default to "Fix all" for non-disagreements and "Explain and keep" for disagreements. Proceed to Step 5.

**For disagreements**, present each one explicitly:

<interaction>
AskUserQuestion(
  header: "Review disagreement",
  question: "Thread on {path}:{line} — Reviewer says: '{summary}'. How should we handle this?",
  options: [
    "Fix as requested" — Make the change the reviewer wants,
    "Explain and keep" — Respond with explanation, do not change code,
    "Discuss further" — Reply asking for more context, do not resolve
  ]
)
</interaction>

**For everything else**, ask:

<interaction>
AskUserQuestion(
  header: "Proceed?",
  question: "Ready to address {count} threads ({suggestions} suggestions, {changes} code changes, {questions} explanations)?",
  options: [
    "Fix all" — Address all threads as categorized,
    "Let me choose" — Review each thread individually before proceeding
  ]
)
</interaction>

If "Let me choose": present each thread with its category and proposed action. Let the user override categories or skip specific threads.

## Step 5: Execute Fixes

Process threads grouped by file. Within each file, sort by line number **descending** (bottom-to-top) to prevent line drift.

### Applying Suggestions

For threads with `` ```suggestion `` blocks:

1. Extract the suggested code from between `` ```suggestion `` and `` ``` `` markers. If a comment contains multiple suggestion blocks, apply the first one. If ambiguous, ask the user.
2. Read the file at `path`.
3. Replace the lines at `line` (or `start_line..line` for multi-line) with the suggested code.
4. Use the Edit tool to apply the change.

### Applying Code Changes

For threads requiring code changes:

1. Read the file at `path` to understand context around `line`.
2. Determine the fix based on the reviewer's comment.
3. Apply the change using the Edit tool.
4. If the fix is unclear, ask the user for clarification before proceeding.

### Pattern Scanning

After applying a code change, scan the other files in the changed-files list (from Step 1) for the same pattern. If the reviewer flagged missing error handling, a naming convention, or a structural issue — the same problem likely exists elsewhere in this PR.

1. Use Grep to search the changed files for the same pattern.
2. Fix all occurrences, not just the one the reviewer flagged.
3. Note the additional fixes in the Step 6 reply: "Fixed here and in {N} other locations: {file1}, {file2}."

Only scan for the **exact pattern** the reviewer identified. Do not generalize into a broad lint pass.

### Preparing Explanations

For threads requiring explanations:

1. Read the code context to understand the design decision.
2. Draft a technical explanation (not defensive — focus on reasoning, constraints, trade-offs).
3. Format the explanation with semantic line breaks: one sentence per line, break after clause-separating punctuation. Target 120 characters per line. Rendered output is unchanged; this keeps reply diffs clean.
4. Include links to relevant docs or code if applicable.

## Step 6: Reply and Resolve Threads

For each addressed thread, reply directly to the review comment and resolve the thread.

**Reply** with a three-tier approach. See [references/graphql-queries.md](references/graphql-queries.md) for full syntax.

**Tier 1 — GraphQL thread reply** (preferred).
Use the `addPullRequestReviewThreadReply` mutation with the thread's `thread_id`.
This is preferred because the REST reply endpoint returns 404 on some repositories.
Escape double quotes and newlines in the body since it's embedded in a GraphQL string.

```bash
ESCAPED_BODY=$(echo "$BODY" | sed 's/\\/\\\\/g; s/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')
gh api graphql -f query="
mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: \"${THREAD_ID}\"
    body: \"${ESCAPED_BODY}\"
  }) {
    comment { id }
  }
}
"
```

**Tier 2 — REST threaded reply.**
If Tier 1 fails (e.g., thread already resolved before reply), try the REST endpoint.
Skip this tier if `first_comment_id` is `0`, `null`, or missing.

```bash
gh api repos/{owner}/{repo}/pulls/comments/{first_comment_id}/replies \
  -X POST -f body="$(cat <<'EOF'
{response text}
EOF
)"
```

**Tier 3 — PR comment fallback.**
If both Tier 1 and Tier 2 fail,
post a top-level PR comment that references the original thread.
Build the reference from `comments[0].html_url`, `path`, `line`, and `comments[0].author`:

```bash
gh pr comment {number} --body "$(cat <<'EOF'
Re: [{path}:{line}]({html_url}) (@{author})

{response text}
EOF
)"
```

Track threads that used the Tier 3 fallback — they are reported in Step 9.

Response format by category:

| Category | Format |
|----------|--------|
| Suggestion applied | `Done — applied the suggestion.` |
| Code change | `Fixed — {brief description of what changed}.` |
| Explanation | `{technical explanation with reasoning}` |
| Disagreement (fix) | `Agreed — {brief description of the fix}.` |
| Disagreement (keep) | `{explanation of reasoning}. Let me know if you'd like to discuss further.` |
| Outdated (addressed) | `This has been addressed in a subsequent update.` |

**Bot attribution:** When replying to automated reviewer comments (Codex, etc.), prefix every reply with `*Automated response from Claude:*` to distinguish from human responses.

**Resolve** the thread using the GraphQL mutation from [references/graphql-queries.md](references/graphql-queries.md), passing the thread's `thread_id`.
Attempt resolution regardless of which reply tier was used — `thread_id` is independent of `first_comment_id`.
If `thread_id` is also missing (REST fallback data from error handling), skip resolution and note as "replied but not resolved" in Step 9.

**Do NOT resolve:**
- Threads where the user chose "Discuss further"
- Threads where the reply is a question back to the reviewer

## Step 7: Commit and Push

Group changes into logical commits. Strategy:

| Scenario | Commits |
|----------|---------|
| All changes in 1-2 files | Single commit |
| Changes span 3+ files, all related | Single commit |
| Changes span multiple unrelated concerns | One commit per concern |
| Mix of suggestions and code changes | Group by concern, not by category |

Commit message format — follow the repo's convention detected from `git log --oneline -5`. If the repo uses conventional commits:

```
fix(scope): address PR #{number} review feedback

- {description of change 1}
- {description of change 2}
```

Push to remote:

```bash
git push
```

**If push fails due to diverged branch:** inform the user. Do NOT force-push. Let the user decide.

## Step 8: CI Validation + Automated Reviews

**If both `--no-bot-reviews` and `--no-ci` are set:** skip this step entirely. Proceed to Step 9.

Run enabled substeps in order. Do NOT combine into a single question or write a summary until ALL have completed.

**POLLING RULE — NEVER use inline `sleep` loops, `sleep N && gh pr checks`, or any foreground sleep-based polling.**
All CI and review waiting MUST use the background scripts below with `run_in_background: true`.
Scripts check immediately on first poll (zero delay), so results already ready return instantly.

### 8a: Trigger Automated Reviews (if stale)

**If `--no-bot-reviews` is set:** skip to 8b.

Check if new commits exist since the last codex comments:

```bash
# Get the latest bot comment timestamp
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq '[.[] | select(.user.login | test("codex"; "i")) | .created_at] | sort | last'

# Get the latest commit timestamp on the PR branch
gh api repos/{owner}/{repo}/pulls/{number}/commits \
  --jq '[.[].commit.committer.date] | sort | last'
```

Compare timestamps. If the latest commit is **after** the latest bot comment (or no bot comments exist), reviews are stale.

**If reviews are current:** skip to 8b.
**If `--auto` mode:** trigger immediately and engage the wait+fix loop (equivalent to "Yes — review and fix" path;
8c will poll for comments and apply fixes — max 3 iterations).
**Interactive mode:**

<interaction>
AskUserQuestion(
  header: "Re-trigger automated reviews?",
  question: "There are new commits since the last Codex reviews. Re-trigger them?",
  options: [
    "Yes — review and fix" — Trigger reviewers, fix actionable feedback after CI (max 3 iterations),
    "Just trigger" — Post review comments but do not auto-fix,
    "No" — Skip automated reviews
  ]
)
</interaction>

If triggering: post `@codex` per [references/automated-review-loop.md](references/automated-review-loop.md) Phase 1. Do NOT wait — 8c will poll later. **Proceed to 8b.**

### 8b: CI Validation Loop

**If `--no-ci` is set:** skip to 8c.

**If `--auto` mode:** Proceed with "Yes — watch and fix" (no prompt).

**Interactive mode:**

<interaction>
AskUserQuestion(
  header: "Watch CI?",
  question: "Want me to watch CI and auto-fix any failures?",
  options: [
    "Yes — watch and fix" — Monitor CI, analyze failures, apply fixes, and loop until green (max 3 iterations),
    "Just watch" — Monitor CI and report results without auto-fixing,
    "No" — Skip CI monitoring
  ]
)
</interaction>

**If "No":** skip to 8c. Otherwise, start the CI poller in the background:

```bash
# MUST use run_in_background: true — NEVER sleep in foreground
./scripts/poll-ci.sh {number}
```

Handle the exit state per [references/ci-validation-loop.md](references/ci-validation-loop.md) Phase 1.
"Yes — watch and fix": on `FAILURES_DETECTED`, follow Phases 2-4 (analyze, fix, loop — max 3 iterations).
"Just watch": report results from script output. No fixes applied.

**After 8b completes → proceed to 8c if reviews were triggered in 8a.**

### 8c: Process Automated Review Feedback

**If `--no-bot-reviews` is set or no reviews were triggered in 8a:** skip to Step 9.

You MUST poll for bot responses — do NOT assume they are already complete. Start the review poller in the background:

```bash
# MUST use run_in_background: true — NEVER sleep in foreground
COMMENT_COUNT=$(gh api "repos/{owner}/{repo}/pulls/{number}/comments" --paginate 2>/dev/null | jq -s 'add | length')
REVIEW_COUNT=$(gh api "repos/{owner}/{repo}/pulls/{number}/reviews" --paginate 2>/dev/null | jq -s 'add | [.[] | select(.state != "COMMENTED")] | length')
./scripts/poll-reviews.sh {number} {owner}/{repo} "$COMMENT_COUNT" "$REVIEW_COUNT" "codex"
```

Handle the exit state per [references/automated-review-loop.md](references/automated-review-loop.md) Phase 2.
"Yes — review and fix": on `REVIEWS_READY`, follow Phases 3-7 (read, fix, push, reply, loop — max 3 iterations).
"Just trigger": report results. No fixes.

**After 8c completes → proceed to Step 9.** The summary is the ONLY place to report final status and next steps.

## Step 9: Summary

Present the final report:

```
## PR #{number} Review Feedback Addressed

### Resolved ({count}/{total})
- {path}:{line} — {category}: {brief description}
  Reply: "{response summary}"

### Replied via PR Comment ({count})
{if any threads used the Tier 3 fallback, list them here}
- {path}:{line} — threaded reply unavailable, posted as PR comment
{if none, omit this section}

### Unresolved ({count})
- {path}:{line} — {reason not resolved}

### Commits
- {hash} — {message}

### Files Modified
- {list}

### CI Validation
{if CI loop ran, include the report from references/ci-validation-loop.md Phase 5}
{if CI loop skipped, omit this section}

### Automated Review
{if review loop ran, include the report from references/automated-review-loop.md Phase 8}
{if review loop skipped, omit this section}

### Next Steps
- {if all resolved and CI green}: Ready for re-review
- {if unresolved remain}: {count} threads need follow-up
- {if CI failures remain}: {count} CI failures need investigation
```

**Offer to request re-review** if all threads are resolved. Determine reviewers from the `--reviewer` argument (if provided) or by deduplicating `comments[0].author` from addressed threads:

```bash
gh pr edit {number} --add-reviewer {reviewer1},{reviewer2}
```

## Error Handling

| Error | Action |
|-------|--------|
| `gh` not authenticated | Inform user to run `gh auth login`. Stop. |
| PR not found | Verify the PR number and repo. Report error. Stop. |
| No unresolved threads | Inform user all feedback is addressed. Skip to Step 8 (unless fully disabled by flags). |
| All features disabled | `--no-comments` + `--no-bot-reviews` + `--no-ci` — nothing to do. Inform user and stop. |
| `get-pr-comments.sh` fails | Fall back to REST: `gh api repos/{owner}/{repo}/pulls/{number}/comments`. Lose thread resolution data but can still categorize and fix. |
| Large output (>25KB) | Script auto-writes to `/tmp/pr-comments-{owner}-{repo}-{pr}.json`. Use the Read tool on that path. |
| Thread resolution fails | Report the error. The reply was still posted. Continue with remaining threads. |
| Reply fails | Try Tier 2 (REST), then Tier 3 (PR comment). If all tiers fail, report the error and log the intended response. Continue with remaining threads. |
| Edit fails (file not found) | The file may have been renamed or deleted. Report to user. Skip thread. |
| Push fails | Report the error. Do NOT force-push. Let user decide. |
| Merge conflict after edits | Report conflicting files. Let user resolve manually. |
| Line numbers outdated | If comment is marked `outdated`, inform user the code has changed since the review. Read the file and attempt to find the relevant code by context. |
| CI poller timeout | If `poll-ci.sh` reports TIMEOUT (20 min), report to user and ask how to proceed. |
| CI fix loop exceeds 3 iterations | Stop. Report remaining failures with log excerpts. Let user investigate. |
| Same CI failure recurs after fix | Mark as unfixable. Do NOT retry the same fix. Report to user. |
| DDCI logs unavailable | Skip log analysis. Report the Mosaic URL for manual investigation. |
| Codex not configured | If no review appears after 15-min timeout, skip that reviewer. Continue with others. |
| Automated review loop exceeds 3 iterations | Stop. Report remaining review comments. Let user investigate. |
