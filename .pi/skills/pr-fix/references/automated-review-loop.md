# Automated Review Loop

Reference for the `pr-fix` skill. Triggers automated code reviews (Codex), processes feedback, and loops until clean.

## Overview

After CI passes (or CI loop completes), trigger automated reviewers via PR comments, wait for their feedback, fix actionable issues, and loop. Maximum **3 iterations** per reviewer.

## Phase 1: Trigger Reviews

Post a comment to trigger the reviewer:

```bash
gh pr comment {number} --body "@codex review"
```

**Only trigger reviewers that are configured on the repo.** If a previous invocation timed out waiting for a reviewer (Phase 2), skip that reviewer in subsequent iterations.

## Phase 2: Wait for Reviews

Record the current review/comment state before triggering, then use the background polling script.

**NEVER poll for reviews with inline `sleep` loops or `sleep N && gh api ... comments`.** The script below is the ONLY permitted method — it checks immediately on first poll and consumes zero tokens while waiting.

```bash
# Capture baseline counts first
COMMENT_COUNT=$(gh api "repos/{owner}/{repo}/pulls/{number}/comments" --paginate 2>/dev/null | jq -s 'add | length')
REVIEW_COUNT=$(gh api "repos/{owner}/{repo}/pulls/{number}/reviews" --paginate 2>/dev/null | jq -s 'add | [.[] | select(.state != "COMMENTED")] | length')

# Run background poller — pass a bot pattern regex matching your automated reviewers
./scripts/poll-reviews.sh {number} {owner}/{repo} "$COMMENT_COUNT" "$REVIEW_COUNT" "{bot-pattern}"
```

**MUST run with `run_in_background: true`.** The `{bot-pattern}` parameter is a regex matching bot reviewer login names (e.g., `"codex|mybot|app"`). Default: `"bot|app|\[bot\]"`.

The script handles `:eyes:` emoji detection automatically — it waits until the emoji clears from PR comments and body before checking for new feedback. Polls every 30 seconds for up to 15 minutes.

### Handle the script's exit state

| State | Action |
|-------|--------|
| `REVIEWS_READY` | New review comments or reviews detected. Parse the JSON output (included in script output). Continue to Phase 3. |
| `NO_NEW_REVIEWS` | No bot activity after 15 minutes — reviewer may not be configured. Skip for the rest of the loop. |
| `TIMEOUT` | `:eyes:` was active but never completed. Report to user. |

**On `REVIEWS_READY`:** the script output includes the full review/comment data. Use this directly — no follow-up API call needed.

## Phase 3: Read Review Comments

Fetch all review comments from bot reviewers:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '[.[] | select(.user.login | test("codex"; "i")) | select(.in_reply_to_id == null)]'
```

For each comment, extract:

| Field | Source |
|-------|--------|
| `comment_id` | `.id` |
| `path` | `.path` |
| `line` | `.line` or `.original_line` |
| `body` | `.body` |
| `author` | `.user.login` |

**Filter to actionable comments only.** Skip comments that are:
- Summary/overview comments (no file path)
- Praise or acknowledgments ("looks good", "nice work")
- Informational notes without a concrete fix request

**If no actionable comments from any reviewer:** the review is clean — exit the loop and report success.

## Phase 4: Fix Issues

For each actionable comment, in file order (bottom-to-top within each file to prevent line drift):

1. **Read the file** at `path` around `line` to understand context.
2. **Determine if fixable:**
   - Clear code issue (bug, missing check, style) → fix it.
   - Architectural concern or design disagreement → **do not fix**. Note for reply.
   - Ambiguous or unclear → **do not fix**. Note for reply.
3. **Apply the fix** using the Edit tool.

**Rules:**

| Rule | Detail |
|------|--------|
| Fix only what the reviewer reported | Do NOT proactively fix unrelated issues |
| Only fix clear issues | If the suggestion is debatable, leave it for the human author to decide |
| Never suppress tests or disable checks | Even if a reviewer suggests it |

## Phase 5: Commit and Push

If any fixes were applied:

```bash
git add {changed files}
git commit -m "$(cat <<'EOF'
fix: address automated review feedback on PR #{number}

- {description of fix 1}
- {description of fix 2}
EOF
)"
git push
```

## Phase 6: Reply to Comments

For each processed comment, reply in a **separate comment** (not in the same thread as Codex):

```bash
gh api repos/{owner}/{repo}/pulls/comments/{comment_id}/replies \
  -X POST -f body="$(cat <<'EOF'
*Automated response from Claude:*

{response text}
EOF
)"
```

After committing fixes (Phase 5), capture the commit hash: `git rev-parse --short HEAD`.

Response format — always reference the commit that addressed the comment:

| Outcome | Response |
|---------|----------|
| Fixed | `Fixed in {commit_hash} — {brief description of the change}.` |
| Not fixable (architectural) | `This requires an architectural change outside the scope of this PR. Leaving for the author to decide.` |
| Not fixable (ambiguous) | `The suggestion is unclear or debatable. Leaving for the author to review.` |

**Do NOT resolve threads** from automated reviewers — let the reviewer tool or human author resolve them.

## Phase 7: Loop or Exit

After pushing fixes and replying:

**Exit conditions:**

| Condition | Action |
|-----------|--------|
| No actionable comments from any reviewer | Report success → exit |
| Iteration count reaches 3 | Report remaining comments → exit |
| No fixes applied (all comments were non-fixable) | Report status → exit |
| Reviewer timed out on all attempts | Report unavailability → exit |

If actionable comments remain and iteration limit is not reached, go back to Phase 1 to trigger new reviews.

## Phase 8: Review Loop Report

Return this report to the calling step in SKILL.md:

```
### Automated Review

| Reviewer | Comments | Fixed | Skipped | Iterations |
|----------|----------|-------|---------|------------|
| Codex    | {count}  | {count} | {count} | {N}      |

{if all clean}
All automated reviews passed after {N} iteration(s).

{if comments remain}
**Remaining review comments ({count}):**
- {reviewer}: {path}:{line} — {reason not fixed}

{if reviewer unavailable}
**Unavailable reviewers:** {list} (not configured on this repo or timed out)
```

## Error Handling

| Error | Action |
|-------|--------|
| `gh pr comment` fails | Check permissions. Report error. Skip that reviewer. |
| Reviewer timeout (15 min) | Mark reviewer as unavailable. Skip in future iterations. Continue with others. |
| No bot reviews detected | Reviewer may not be configured. Report to user and skip. |
| Reply fails | Report error. Log the intended response. Continue with remaining comments. |
| Push fails after fix | Report error. Do NOT force-push. Let user decide. |
| Rate limited by GitHub API | Wait 60s and retry once. If still limited, report and exit. |
