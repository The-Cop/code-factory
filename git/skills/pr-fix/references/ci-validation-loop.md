# CI Validation Loop

Reference for the `pr-fix` skill. Implements an automated check-fix-recheck cycle after pushing PR feedback fixes.

## Overview

After pushing fixes, monitor CI status. If checks fail, analyze failures, apply fixes, commit, push, and recheck. Maximum **3 iterations** to prevent infinite loops.

## Phase 1: Wait for CI

After the push from Step 7, wait for CI to start and complete using the background polling script.

**NEVER poll CI with inline `sleep` loops or `sleep N && gh pr checks`.** The script below is the ONLY permitted method — it checks immediately on first poll and consumes zero tokens while waiting.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/pr-fix/scripts/poll-ci.sh {number} 30 40 0
```

**MUST run with `run_in_background: true`.** The script automatically filters out approval-gated checks (merge gate, peer review, manual approval, codeowner, devflow/mergegate) and polls every 30 seconds for up to 20 minutes.
The final `0` keeps unchanged progress quiet; pass a positive `log-every` only when the user asked for live progress.
For `DataDog/dd-source`, the poller waits for DDCI checks to register before accepting an all-passing state; this prevents early success while downstream `dd-gitlab/*` jobs are still attaching.

### Handle the script's exit state

| State | Action |
|-------|--------|
| `ALL_PASSING` | Skip to Phase 5 (report success) |
| `FAILURES_DETECTED` | Read `STATUS_FILE` from the output. Continue to Phase 2. |
| `CONFLICTS_DETECTED` | PR has merge conflicts from base branch movement. Invoke `/fix-conflicts`, push the resolution, then restart the poller. |
| `TIMEOUT` | Use the `LAST_SUMMARY` and `PENDING_CHECKS` output to report the current state. Do not keep foreground polling. |

**On `FAILURES_DETECTED`:** the script writes the full compact check table to `STATUS_FILE`.
Read that file; do not call `gh pr checks` again unless the file is missing or malformed.

## Phase 2: Identify Failures

Use the `STATUS_FILE` JSON from Phase 1. Only refetch if that file is missing or malformed:

```bash
gh pr checks {number} --json name,state,bucket,link
```

Parse into a structured list of failed checks, excluding approval-gated checks (same patterns as Phase 1). For each failed check, determine the CI system:

| Link pattern | CI system |
|-------------|-----------|
| `gitlab.ddbuild.io/*` or `mosaic.us1.ddbuild.io/*` | DDCI (GitLab) |
| `github.com/*/actions/*` | GitHub Actions |
| Other | Unknown — report link to user |

### DDCI Failures

1. Extract the DDCI `request_id` from the "DDCI Task Sourcing" check's Mosaic URL:

```bash
# The link looks like: https://mosaic.us1.ddbuild.io/change-request/<request_id>
# Extract request_id from the URL path
```

2. List failed jobs:

```bash
command -v get_ddci_logs.sh
get_ddci_logs.sh --list-failed {request_id}
```

Output is tab-separated: `job_id`, `job_name`, `status`, `failure_reason`.

3. For each failed job, fetch the log summary:

```bash
get_ddci_logs.sh {job_id} {request_id} --summary
```

**If GitLab/DDCI logs are unavailable:** diagnose credentials, then use PR comments before giving up.

| Check | Command | If it fails |
|-------|---------|-------------|
| `get_ddci_logs.sh` exists | `command -v get_ddci_logs.sh` | Continue with PR-comment fallback. |
| `GITLAB_TOKEN` works | `[ -n "${GITLAB_TOKEN:-}" ] && curl -fsS -H "Authorization: Bearer $GITLAB_TOKEN" https://gitlab.ddbuild.io/api/v4/user >/dev/null` | If unset, `invalid_token`, or expired, do not print the token; continue. |
| `ddtool` token works | `ddtool auth gitlab token` | If `invalid_grant`, report that GitLab auth must be refreshed; continue. |
| project token works | `ddtool auth gitlab project-token {owner} {repo}` | If securestore/keychain write fails, report it; continue. |

Fetch compact Datadog CI PR comments for the failed check, head SHA, job name, or common failing test name:

```bash
gh api repos/{owner}/{repo}/issues/{number}/comments --paginate \
  --jq '[.[] | select((.body // "") | test("{failed_check}|{head_sha}|gazelle_check|repository-checks"; "i")) | {author:.user.login, updated_at, body:(.body[0:4000])}]'
```

Extract failed test names, job names, commit SHA, linked paths, and short error text.
Datadog CI comments often contain enough information to fix format, Gazelle, repository-check, and test failures even when GitLab logs are inaccessible.

If neither logs nor PR comments identify a file, line, test, or exact command, classify the failure as not auto-fixable and report the Mosaic/GitLab URL.

### GitHub Actions Failures

1. Extract the run ID from the check link.

2. Fetch failed job logs:

```bash
gh run view {run_id} --log-failed 2>&1 | tail -100
```

3. If the output is too large, fetch per-job:

```bash
gh run view {run_id} --json jobs --jq '.jobs[] | select(.conclusion == "failure") | {name, steps: [.steps[] | select(.conclusion == "failure") | .name]}'
```

## Phase 3: Analyze and Fix

Classify each failure before deciding the fix strategy:

| Priority | Category | Symptoms | Auto-fixable? | Action |
|----------|----------|----------|---------------|--------|
| **P0** | Build | Compilation failure, missing imports, syntax errors | Yes | Read error, fix code |
| **P1** | Test/logic | Unit test assertion, wrong output, type error | Maybe | Read test output, fix if root cause is clear |
| **P2** | Config | Wrong env var, missing flag, bad deploy config | Maybe | Check config; ask user if env-specific |
| **P3** | Dependency | Missing package, version mismatch, import not found | Maybe | Check lock file / dependency versions |
| **P4** | Lint/format | Style violations, unused imports, formatting | Yes | Run formatter/linter with `--fix` |
| **P5** | Flaky/infra | Network timeout, runner OOM, service unavailable, non-deterministic | No | Retry only — never "fix" an infra failure with code changes |

**Classification heuristics:**
- Error message mentions a package or module → P3 (Dependency)
- Error is in a config file or environment variable → P2 (Config)
- Error is non-deterministic (passes on re-run) → P5 (Flaky)
- Error is in a file this PR didn't touch → likely pre-existing, see Scope Discipline below

### Re-run Flaky Jobs

For failures classified as P5 (flaky/infra), re-run without fixing code:

**GitHub Actions:**

```bash
gh run rerun {run_id} --failed
```

**DDCI:**

```bash
retry_ddci_job.sh {job_id}
```

**If `retry_ddci_job.sh` is not available:** report the failure and Mosaic link. Let the user retry manually.

After re-running, return to Phase 1 to wait for the new run. Count this as an iteration.

### Classify: PR-related vs Pre-existing

Before fixing, compare the failure against the changed-files list captured in Step 1 of the main skill.

**PR-related** (fix on this branch):
- Failing test file is in the changed-files list
- Error references a symbol, type, or function this PR modified
- Build/lint/type-check failure on a file this PR touched

**Pre-existing** (fix separately):
- Failing test is in a file this PR did not touch
- Error is in an unrelated package or shared infrastructure
- Failure was already present on the base branch

### Fix Strategy

For each failure, in priority order:

1. **Read the error output** — identify the file, line, and error message.
2. **Read the affected file** at the reported location.
3. **Determine if auto-fixable:**
   - If the fix is clear (missing import, type error, lint violation) → apply the fix.
   - If the fix requires design decisions → **stop and ask the user**.
   - If the failure is flaky/infra → **do not fix, offer retry**.
4. **Apply the fix** using the Edit tool.

**Rules:**

| Rule | Detail |
|------|--------|
| Fix only what CI reports | Do NOT proactively fix unrelated issues |
| One concern per iteration | Fix all failures from one CI run, then push and recheck |
| Confidence threshold | Only auto-fix if you can identify the exact root cause from the logs |
| Ask on ambiguity | If multiple fixes are possible, present options to the user |
| Never suppress tests | Do not skip, disable, or mark tests as expected-failure to pass CI |

### Datadog Source Repository Checks

For `tools/format/gazelle_check`, stale BUILD metadata is likely after Go, Python, or proto import changes.
Use the repo's generator first:

```bash
bzl run //:gazelle -- update {touched directories}
```

If Bazel/Gazelle is blocked by local auth or credential-helper setup, use a scoped fallback:

1. Read the failing CI comment or log to identify the touched package.
2. Run language-native metadata in that package only, using temp dirs under `/tmp` if needed:
   ```bash
   TMPDIR=/tmp GOTMPDIR=/tmp GOCACHE=/tmp/go-cache go list -json {package_or_dir}
   ```
3. Compare imports against direct `deps`/`test deps` in the nearby `BUILD.bazel`.
4. Remove stale deps or add missing deps only when the mapping is unambiguous.
5. Record the generator blocker and manual BUILD edit in the final report.

### Scope Discipline

**Only commit changes that are directly required to make this PR's code correct.**

If a failure is classified as pre-existing (not caused by this PR's changes):

1. Create a new branch from the base branch (not the PR branch):
   ```bash
   default_branch=$(gh pr view {number} --json baseRefName --jq '.baseRefName')
   git fetch origin "$default_branch"
   git checkout -b fix/{short-description} "origin/$default_branch"
   ```
2. Apply the fix on the new branch.
3. Commit, push, and open a separate draft PR.
4. Report the new PR URL to the user.
5. Switch back to the PR branch and re-run the failing job to unblock CI.

### Commit and Push

After applying fixes:

```bash
git add {changed files}
git commit -m "$(cat <<'EOF'
fix: address CI failures from PR #{number} feedback

- {description of fix 1}
- {description of fix 2}
EOF
)"
git push
```

## Phase 4: Loop Control

After pushing fixes, return to Phase 1 to wait for the new CI run.

**Exit conditions (stop the loop):**

| Condition | Action |
|-----------|--------|
| All checks pass | Report success → exit |
| Iteration count reaches 3 | Report remaining failures → exit |
| No auto-fixable failures remain | Report unfixable failures → exit |
| User declines a fix | Report status and remaining failures → exit |
| Same failure persists after fix attempt | Report as unfixable → exit |

**Iteration tracking:**

Track across iterations:
- `iteration_count` — incremented each time through the loop
- `fixed_failures` — set of failure signatures already attempted (to detect repeats)
- `total_fixes_applied` — running count of fixes made

**If a failure recurs after a fix attempt**, it means the fix was incorrect. Do NOT retry the same fix. Report it as unfixable and let the user investigate.

## Phase 5: CI Loop Report

Return this report to the calling step (Step 9 in SKILL.md):

```
### CI Validation

| Iteration | Failures Found | Fixes Applied | Result |
|-----------|---------------|---------------|--------|
| 1         | {count}       | {count}       | {pass/fail} |
| 2         | {count}       | {count}       | {pass/fail} |
| ...       | ...           | ...           | ...    |

{if all passed}
All CI checks passing after {N} iteration(s).

{if failures remain}
**Remaining failures ({count}):**
- {check name}: {failure description} — {reason not fixable}

**Recommended next steps:**
- {specific action per remaining failure}
```

## Error Handling

| Error | Action |
|-------|--------|
| `gh pr checks` fails | Verify PR number. Check `gh auth status`. Report error. |
| Poller timeout | Report `LAST_SUMMARY` and pending checks. Ask how to proceed unless another parallel waiter still has actionable work. |
| `get_ddci_logs.sh` not found | Skip DDCI log analysis. Report the Mosaic URL for manual investigation. |
| Log output exceeds context | Truncate to last 100 lines. Focus on the first error in the output. |
| Push fails after fix | Report error. Do NOT force-push. Let user decide. |
| Rate limited by GitHub API | Wait 60s and retry once. If still limited, report and exit. |
| VPN/network timeout | Inform user to check AppGate VPN connection. Stop. |
