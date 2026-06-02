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
allowed-tools: Bash(git:*), Bash(gh:*), Bash(jq:*), Bash(bash:*), Bash(make:*), Bash(bzl:*), Bash(env:*), Bash(curl:*), Bash(ddtool:*), Bash(get_ddci_logs.sh:*), Bash(retry_ddci_job.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/get-pr-comments.sh:*), Bash(${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/*), Read, Write, Edit, Grep, Glob, AskUserQuestion, Task, Skill
---

# Fix PR Feedback

Announce: "I'm using the pr-fix skill to address PR review feedback."

## Routing

| If you need... | Use instead |
|----------------|-------------|
| Review a PR and produce feedback | `review` skill — read-only analysis with structured findings |
| Address existing PR review comments | `pr-fix` skill — you're here |
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

Run in parallel:

- `gh auth status 2>&1`
- `gh repo view --json nameWithOwner -q '.nameWithOwner'` (split on `/` to get `{owner}` and `{repo}` for API calls)
- `git branch --show-current`
- `git status --porcelain=v1 --branch --untracked-files=no | sed -n '1,80p'`

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

**If `mergeable` is `CONFLICTING`:** resolve conflicts before proceeding.
Use the `fix-conflicts` skill, push the resolved merge commit, then re-fetch changed files since the diff may have grown.

### Flag Routing

Determine which steps to execute based on parsed flags:

| Condition | Steps to execute |
|-----------|-----------------|
| `--no-comments` set | Skip Steps 2-7. Jump to Step 8. |
| `--no-bot-reviews` set | Skip Steps 8a + 8c. |
| `--no-ci` set | Skip Step 8b. |
| `--no-comments` + `--no-bot-reviews` + `--no-ci` | Nothing to do. Inform user and stop. |

If all of Step 8 is skipped, stop after Step 7; if all features are disabled, inform the user and stop.

## Step 2: Fetch Review Feedback

**If `--no-comments` is set:** skip to Step 8.

Fetch unresolved threads and non-empty review bodies in parallel.
Use `-p` so large outputs return small pointer objects instead of dumping every comment into context.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/get-pr-comments.sh -a -p {number}
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/get-pr-review-summaries.sh -p {number}
```

For a comment URL, pass it to `get-pr-comments.sh`; skip summaries only when the user gave one exact comment URL.

**If stdout is an object with `output_file`:** read that path; do not re-run without `-p`.

`get-pr-comments.sh` returns `THREADS` with `thread_id`, `first_comment_id`, `path`, `line`, `start_line`, and `comments[]`.
For `#discussion_r...` URLs that GraphQL misses, it falls back to REST and returns the same shape with `thread_id: null`; reply via REST/Tier 3 and report "replied but not resolved".
`get-pr-review-summaries.sh` returns `REVIEWS`: top-level review bodies that do not create inline threads.

**If `--reviewer` specified:** pass `-r "{reviewer}"` to both scripts.

**If no threads and no review summaries are returned:** all review feedback is addressed. Skip to Step 8.

## Step 3: Categorize and Prioritize

Classify each thread and review summary into one category:

| Category | Signals | Action |
|----------|---------|--------|
| **Suggestion** | Body contains `` ```suggestion `` block | Apply the suggested code change |
| **Code change** | Imperative language ("change X", "add Y", "remove Z"), bug report, missing handling | Edit the code as requested |
| **Question** | Ends with `?`, asks "why", requests clarification | Respond with explanation |
| **Disagreement** | Reviewer challenges a design decision, requests a revert or alternative approach | **NEVER auto-resolve.** Present to user for decision. |
| **Outdated** | Thread `outdated` is true or all comments have `outdated: true` | Read current code at `path`. If the concern is already addressed, resolve with a note. If not, reclassify as Code change or Question. |
| **Review summary** | Non-empty review body without inline thread | Inspect current code; implement concrete improvements or mark informational. |

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
{review_summary_count} review summaries with non-empty body

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

For review-summary code changes, search changed files for the named topic; search broader only for named symbols absent from changed files.

### Pattern Scanning

After applying a code change, scan the other files in the changed-files list (from Step 1) for the same pattern. If the reviewer flagged missing error handling, a naming convention, or a structural issue — the same problem likely exists elsewhere in this PR.

1. Use Grep to search the changed files for the same pattern.
2. Fix all matching occurrences, not only the one the reviewer flagged.
3. Note the additional fixes in the Step 6 reply: "Fixed here and in {N} other locations: {file1}, {file2}."

Only scan for the **exact pattern** the reviewer identified. Do not generalize into a broad lint pass.

### Preparing Explanations

For threads requiring explanations:

1. Read the code context to understand the design decision.
2. Draft a technical explanation (not defensive — focus on reasoning, constraints, trade-offs).
3. Format the explanation with semantic line breaks: one sentence per line, break after clause-separating punctuation. Target 120 characters per line. Rendered output is unchanged; this keeps reply diffs clean.
4. Include links to relevant docs or code if applicable.

## Step 6: Reply and Resolve Threads

For each addressed human review thread, reply directly to the review comment and resolve the thread.
Prefer the helper script; it tries GraphQL thread reply, REST threaded reply, then top-level PR comment fallback.
Track threads that used the Tier 3 fallback; report them in Step 9.

```bash
printf '%s\n' "{response text}" \
  | ${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/reply-review-thread.sh \
      --thread-id "{thread_id}" --first-comment-id "{first_comment_id}" --repo "{owner}/{repo}" --pr "{number}" \
      --path "{path}" --line "{line}" --url "{html_url}" --author "{author}"
```

If the helper fails, then load [references/graphql-queries.md](references/graphql-queries.md) and use the manual tiered flow.

Response format by category:

| Category | Format |
|----------|--------|
| Suggestion applied | `Done - applied the suggestion.` |
| Code change | `Fixed - {brief description of what changed}.` |
| Explanation | `{technical explanation with reasoning}` |
| Disagreement (fix) | `Agreed - {brief description of the fix}.` |
| Disagreement (keep) | `{explanation of reasoning}. Let me know if you'd like to discuss further.` |
| Outdated (addressed) | `This has been addressed in a subsequent update.` |

**Automated reviewer comments:** follow [references/automated-review-loop.md](references/automated-review-loop.md) Phase 6.
Prefix replies with `*Automated response from {agent}:*`, where `{agent}` is the current agent name or `pr-fix`.
Do not resolve automated reviewer threads.

The helper resolves the thread unless `--no-resolve` is passed; if `thread_id` is missing, note "replied but not resolved" in Step 9.

**Do NOT resolve:**
- Threads where the user chose "Discuss further"
- Threads where the reply is a question back to the reviewer
- Threads from automated reviewers

For addressed review summaries, there is no thread to resolve; post a top-level PR comment only when code changed or the reviewer asked a direct question.

## Step 7: Commit and Push

Group changes into logical commits: one concern per commit, even when it spans multiple files.

Before committing, run independent local validations in parallel.
Choose checks from the changed file types and repo guidance, for example:

```bash
git diff --check -- {changed-files}          # whitespace and conflict markers
git diff --name-only --diff-filter=U         # unresolved merge conflicts
bash -n {changed-shell-files}                # shell syntax
```

Do not serialize independent syntax, formatting, and lightweight test checks; launch them in one parallel tool call, keep output scoped to changed files, and record blockers in Step 9.
After Go, Python, or proto import changes, run the repo-required dependency generator before tests; if blocked, compare imports to nearby BUILD deps and report the blocker in Step 9.

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

Run enabled validation waiters in parallel after any automated review trigger.
Do not wait for CI before polling reviews; both waiters are read-only until they report an actionable state.
Do not write a final summary until all enabled waiters and any fix loops have completed.

**POLLING RULE — NEVER use inline `sleep` loops, `sleep N && gh pr checks`, or any foreground sleep-based polling.**
All CI and review waiting MUST use the background scripts below with `run_in_background: true` or the equivalent parallel exec/session mechanism.
Pass `0` as `log-every` unless the user asked for live progress; scripts check immediately and return only actionable state changes plus final output.

### 8a: Trigger Automated Reviews (if stale)

**If `--no-bot-reviews` is set:** skip to 8b.

Before triggering new bot reviews, audit unreplied automated root file comments:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/list-unreplied-bot-comments.sh {number} {owner}/{repo} codex
```

If non-empty, handle them first. In `--auto`, read only listed IDs, inspect current code, fix clear issues, and reply per
[references/automated-review-loop.md](references/automated-review-loop.md) Phase 6.

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
    "Yes — review and fix" — Trigger reviewers, fix actionable feedback from the review poller (max 3 iterations),
    "Just trigger" — Post review comments but do not auto-fix,
    "No" — Skip automated reviews
  ]
)
</interaction>

If triggering, first capture the review baseline and carry it into 8c:

```bash
BOT_PATTERN="codex"
REVIEW_BASELINE_COMMENTS=$(gh api "repos/{owner}/{repo}/pulls/{number}/comments" --paginate 2>/dev/null | jq -s --arg bp "$BOT_PATTERN" 'add | [.[] | select((.user.login // "") | test($bp; "i")) | select((.in_reply_to_id // null) == null) | select(.path != null)] | length')
REVIEW_BASELINE_REVIEWS=$(gh api "repos/{owner}/{repo}/pulls/{number}/reviews" --paginate 2>/dev/null | jq -s --arg bp "$BOT_PATTERN" 'add | [.[] | select((.user.login // "") | test($bp; "i")) | select(.state != "COMMENTED")] | length')
REVIEW_BASELINE_ISSUE_COMMENTS=$(gh api "repos/{owner}/{repo}/issues/{number}/comments" --paginate 2>/dev/null | jq -s --arg bp "$BOT_PATTERN" 'add | [.[] | select((.user.login // "") | test($bp; "i"))] | length')
```

Never capture this baseline after waiting for CI; comments posted during that wait would be missed.

Then post `@codex` per [references/automated-review-loop.md](references/automated-review-loop.md) Phase 1.
Do not wait here; 8c starts the review poller. **Proceed to 8b.**

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

**If "No":** skip the CI waiter. Otherwise, start the CI poller in the background:

```bash
# MUST use run_in_background: true — NEVER sleep in foreground
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/poll-ci.sh {number} 30 40 0
```

Handle the exit state per [references/ci-validation-loop.md](references/ci-validation-loop.md) Phase 1.
"Yes — watch and fix": on `FAILURES_DETECTED`, follow Phases 2-4; "Just watch": report script output with no fixes.

If the review waiter is also enabled, launch it in the same parallel tool call/session group.
Keep both waiters running independently and process whichever returns an actionable state first.
After pushing a fix from either loop, the other waiter's result is stale; restart all enabled waiters from the new head.

### 8c: Process Automated Review Feedback

**If `--no-bot-reviews` is set or no reviews were triggered in 8a:** skip to Step 9.

You MUST poll for bot responses — do NOT assume they are already complete. Start the review poller in the background:

```bash
# MUST use run_in_background: true — NEVER sleep in foreground
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/poll-reviews.sh {number} {owner}/{repo} "$REVIEW_BASELINE_COMMENTS" "$REVIEW_BASELINE_REVIEWS" "$BOT_PATTERN" 30 30 0 "$REVIEW_BASELINE_ISSUE_COMMENTS"
```

Handle the exit state per [references/automated-review-loop.md](references/automated-review-loop.md) Phase 2.
"Yes — review and fix": on `REVIEWS_READY`, follow Phases 3-7; "Just trigger": report results with no fixes.
On `REVIEWS_CLEAN`, read `NEW_ISSUE_COMMENTS_FILE` if present and report the clean bot result from that file.

**After 8c completes → proceed to Step 9.** The summary is the ONLY place to report final status and next steps.

## Step 9: Summary

Before the final report, capture current PR state in parallel:

```bash
gh pr checks {number} --json name,state,bucket,description,link
gh pr view {number} --json mergeable,mergeStateStatus
gh api repos/{owner}/{repo}/issues/{number}/comments --paginate --jq '[.[] | select(.user.login | test("codex"; "i")) | {created_at, body, html_url}] | sort_by(.created_at) | last'
```

Present only relevant sections:

| Section | Include |
|---------|---------|
| Resolved / Replied via PR Comment / Review Summaries / Unresolved | Counts, paths, categories, and reply summaries. |
| Commits / Files Modified | Hashes and filenames changed by this run; omit if no code changed. |
| CI Validation | If watched, use the CI loop report; if skipped by `--no-ci`, include the current pass/fail/pending snapshot. |
| Automated Review | Include new actionable comments, skipped comments, or clean top-level bot comments. |
| Next Steps | Say ready for re-review only when comments are addressed and current checks are green. |

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
| Review summaries only | Inspect non-empty review bodies. Implement clear improvements or reply/explain; do not skip solely because threads are resolved. |
| All features disabled | `--no-comments` + `--no-bot-reviews` + `--no-ci` — nothing to do. Inform user and stop. |
| `get-pr-comments.sh` fails | Fall back to REST: `gh api repos/{owner}/{repo}/pulls/{number}/comments`. Lose thread resolution data but can still categorize and fix. |
| `get-pr-review-summaries.sh` fails | Fall back to REST reviews: `gh api repos/{owner}/{repo}/pulls/{number}/reviews --paginate`. Keep non-empty `body` fields. |
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
| DDCI logs unavailable | Diagnose GitLab auth, read Datadog CI PR comments, then report Mosaic/GitLab URLs if no exact failure detail is available. |
| Codex not configured | If no review appears after 15-min timeout, skip that reviewer. Continue with others. |
| Automated review loop exceeds 3 iterations | Stop. Report remaining review comments. Let user investigate. |
