---
name: "debug"
description: "Use when encountering any bug, test failure, unexpected behavior, or production issue that requires investigation before fixing. Triggers: \"debug\", \"investigate bug\", \"fix failing test\", \"why is this broken\", \"root cause\", \"debug this\", \"what's causing\", \"track down\", \"bisect\", \"prod bug\", \"production incident\", \"investigate incident\", \"errors in datadog\", \"5xx spike\", \"customer issue\", \"why is the service failing\", \"staging bug\"."
---

# Systematic Debugging

Announce: "I'm using the /debug skill to systematically investigate this issue before proposing fixes."

## Routing

| If you need... | Use instead |
|----------------|-------------|
| Implement a new feature or change | `/do` — full lifecycle with REFINE → EXECUTE phases |
| Fix a specific bug with known root cause | `/debug` — you're here |
| Address PR review comments | `/pr-fix` |

## The Iron Law

```
NO FIXES WITHOUT ROOT CAUSE INVESTIGATION FIRST.
```

Symptom fixes are failure. Quick patches mask underlying issues. Random changes waste time and create new bugs.

You MUST complete Phase 1 before proposing any fix. Violating the letter of this rule IS violating the spirit.

## When to Apply Full Process

Apply this for: test failures, production bugs, unexpected behavior, performance problems, build failures, integration issues, flaky tests, and data corruption.

Apply **especially** when:
- Time pressure makes "quick fixes" tempting
- The fix seems "obvious"
- Multiple failed attempts have already occurred
- Understanding is incomplete

## Anti-Pattern: "This Is Too Simple To Debug Systematically"

| Rationalization | Reality |
|----------------|---------|
| "Quick fix for now, proper fix later" | "Later" never comes. The quick fix becomes permanent. |
| "I already know what's wrong" | If you knew, you wouldn't have a bug. Verify. |
| "Just try changing X" | Random changes create new bugs and waste time. |
| "Skip testing, I can see the fix" | You can't verify a fix without reproducing the bug first. |
| "This is too simple for process" | Simple bugs with skipped investigation have the highest rework rate. |
| "I'll add tests after the fix" | Tests-after prove "what does this do?" not "what should this do?" |
| "Multiple changes at once will be faster" | Changing multiple variables prevents isolating the cause. |
| "I can guess the prod error without Datadog" | Real error messages have variations and stack contexts you can't predict. Phase 0 gives the exact strings. |
| "Phase 0 is overhead for a quick prod bug" | The quick prod bug is exactly where telemetry saves the most time. |
| "I'll grep prod logs later if reproduction fails" | Reproduction without prod evidence often fails on wrong inputs and you waste a full cycle. |

## Red Flags — STOP Immediately

If you catch yourself thinking any of these, STOP and return to Phase 1:

- "Let me just try..."
- "This should fix it"
- "I don't need to reproduce it"
- "The error message tells me everything"
- "I'll skip the investigation for this one"
- "This is different because..."

## Step 1: Initialize Debug Session

Determine from `$ARGUMENTS` and conversation whether to start a new session or resume:

**If `$ARGUMENTS` references a `~/docs/plans/debug/` state file:** Resume mode (Step 1b).
**Otherwise:** New session.

### New Session

```bash
STATE_ROOT=~/docs/plans/debug
mkdir -p "$STATE_ROOT"
```

Generate a session ID: `<timestamp>-<slug>` (slug from the bug description, kebab-case, max 30 chars).

Format all Markdown written to state files with semantic line breaks: one sentence per line, break after clause-separating punctuation (commas, semicolons, colons). Target 120 characters per line.

**Phase state machine** (`phase` field in DEBUG.md frontmatter):

| Value | Set by |
|---|---|
| `CLASSIFY` | Step 1 (initial) |
| `PHASE_0` | Step 3 entry — telemetry subagent in flight |
| `PHASE_0_COMPLETE` | Step 3 exit — telemetry section appended |
| `REPRODUCING` | Step 4 entry |
| `INVESTIGATING` | Step 4 hypothesis testing |
| `ROOT_CAUSE_FOUND` | Step 4g |
| `FIXING` | Step 6 entry |
| `VERIFIED` | Step 7 exit (also sets `status: resolved`) |

**Casing convention:** frontmatter `scope` is uppercase (`PROD`, `STAGING`, `LOCAL`). Datadog tag values and `--env` flags use lowercase (`prod`, `staging`).

Create `$STATE_ROOT/<session-id>/DEBUG.md`:

```markdown
---
session_id: <session-id>
status: investigating
phase: CLASSIFY
scope: <PROD|STAGING|LOCAL>
org: <2|197728|null>
service: <service-name|null>
created: <ISO timestamp>
last_updated: <ISO timestamp>
---

# Debug Session: <brief description>

## Bug Report
<user's description, error messages, and context>

## Reproduction
- [ ] Reproduced consistently
- Reproduction steps: <pending>
- Environment: <pending>

## Investigation Log
<!-- Append-only log of what you tried and learned -->

## Hypotheses
<!-- Numbered hypotheses with status: UNTESTED, CONFIRMED, REJECTED -->

## Root Cause
<pending — do NOT fill until Phase 2 completes>

## Fix Applied
<pending — do NOT fill until Phase 3 completes>

## Verification
<pending — do NOT fill until Phase 4 completes>
```

### Resume (Step 1b)

Read the state file. Parse `phase` from frontmatter. Route to the appropriate phase. Read the Investigation Log to restore context.

## Step 2: Classify Bug Scope

**Goal:** Decide whether to gather Datadog telemetry before reproducing.

Inspect `$ARGUMENTS` and conversation for environment signals.

| Signals | Scope | Datadog org |
|---|---|---|
| `my test`, `on my machine`, `local`, no service name, build/lint/unit failure | LOCAL | n/a — skip Phase 0 |
| `prod`, `production`, `live`, `customer`, `incident`, `outage`, `5xx`, `pager`, named deployed service | PROD | org 2 (default — no `--org` flag) |
| `staging`, `stage`, `pre-prod`, `test env`, `staging-deployed` | STAGING | org 197728 (`--org 197728`) |
| Service name present but environment unclear | AMBIGUOUS | ask user |

Datadog site is always `datadoghq.com`. Never pass `--site datad0g.com`.

For AMBIGUOUS, use `ask_question`:

```
ask_question(questions=[{
  "question": "Where is <service> deployed?",
  "header": "Environment",
  "multiSelect": false,
  "options": [
    {"label": "Production", "description": "Investigate Datadog org 2 (datadoghq.com)"},
    {"label": "Staging",    "description": "Investigate Datadog org 197728 (datadoghq.com)"},
    {"label": "Local only", "description": "Skip Phase 0, reproduce locally"}
  ]
}])
```

Persist the resolved scope to DEBUG.md frontmatter:

```yaml
scope: PROD | STAGING | LOCAL
org: 2 | 197728 | null
service: <service-name or null>
```

**Routing:**

- `scope == LOCAL` → skip to Step 4 (Phase 1 — Reproduce).
- `scope == PROD` or `scope == STAGING` → continue to Step 3 (Phase 0).

## Step 3: Phase 0 — Observe in Production

**Goal:** Gather Datadog telemetry to inform reproduction. NO hypotheses or fixes in this phase.

Only runs when `scope != LOCAL`. For the full template and command recipe, see
[references/production-telemetry.md](references/production-telemetry.md).

Dispatch a Task subagent that invokes the `/datadog` skill with the correct org:

```
subagent(
  agent = "general-purpose",
  description = "Phase 0 telemetry for <service> in <env>",
  task = "
  <context>
  Bug: <one-line description>
  Service: <service-name>
  Environment: <prod|staging>
  Datadog org: <2|197728>          # leave empty for prod (default)
  Datadog site: datadoghq.com      # always
  Time window: last 1h (widen if no signal)
  </context>

  <role>
  Read-only Datadog telemetry agent.
  Use the productivity:datadog skill via the pup CLI.
  </role>

  <rules>
  - Never pass --site (default datadoghq.com is correct).
  - For staging: every pup command includes --org 197728.
  - For prod: do not pass --org.
  - All pup output is JSON. Cache to /tmp/debug-phase0-*.json.
  - Batch initial queries in parallel with & ... wait.
  </rules>

  <task>
  Run in parallel and summarize:
  1. pup logs search --query 'service:<svc> status:error'
  2. pup error-tracking issues search (jq-filter by service)
  3. pup apm services stats --env <env> --start EPOCH --end EPOCH
  4. pup events search --query 'source:deploy service:<svc>'
  5. pup monitors list --tags 'service:<svc>'

  Return:
  - Top 3 error messages (count, first/last seen)
  - Top 3 error-tracking issues (id, count)
  - Slowest or failing traces (operation, duration, error)
  - Last deploy in bug window (version, timestamp)
  - Monitors currently in alert state
  </task>

  <constraints>
  - Cite the exact pup command for every finding.
  - Do not propose fixes or root causes.
  - If empty results after widening to 4h, say so explicitly.
  </constraints>"
)
```

After the subagent returns, append findings to DEBUG.md under a new section:

```markdown
## Production Telemetry (Phase 0)

- Service: <name>
- Environment: <prod|staging>
- Org: <2|197728>
- Site: datadoghq.com
- Time window: <from> to <to>

### Top Errors
- <count> x "<message>" — first <ts>, last <ts>

### Top Error-Tracking Issues
- ETI-<id>: <count> occurrences

### Failing Traces
- <operation> — <duration> — <error>

### Recent Deploys
- <version/commit> at <ts>

### Alerting Monitors
- <monitor-name> — <status>

### Raw Responses
- /tmp/debug-phase0-*.json
```

Set `phase: PHASE_0_COMPLETE` in DEBUG.md frontmatter and continue to Step 4.
Phase 0 evidence feeds Phase 1 reproduction with precise timestamps, error
strings, and request payloads.

## Step 4: Phase 1 — Reproduce and Investigate

**Goal:** Consistent reproduction and root cause identification. NO fixes allowed in this phase.

If Phase 0 ran, read the Production Telemetry section of DEBUG.md first — its
timestamps, error strings, and last-deploy entry usually shortcut reproduction
and may eliminate the need for `git bisect`.

### 4a: Read Error Messages Carefully

Read the full error output — stack traces, warnings, and surrounding log lines. Do not skip past warnings.

### 4b: Reproduce Consistently

Before any investigation, reproduce the bug:

1. Run the failing command or test exactly as reported.
2. Capture the full output.
3. If it fails intermittently (flaky), run 3-5 times and note the pattern.

**If you cannot reproduce:** Log this in the Investigation Log and explore recent changes (Step 4c) to understand what changed.

Update the Reproduction section with exact steps and output.

### 4c: Check Recent Changes

If Phase 0 captured a recent deploy event in the bug window, start with the
commit/version from that event before running `git bisect` — it is the highest-prior
candidate.

```bash
git log --oneline -20
git diff HEAD~5 --stat
```

Look for changes in the area where the bug manifests. This often reveals the introducing commit.

For deeper bisection:

```bash
git bisect start
git bisect bad HEAD
git bisect good <known-good-commit>
# Then run the reproduction command at each bisect step
```

### 4d: Gather Evidence

Dispatch the `explorer` agent to map the relevant code area:

```
subagent(
  agent = "explorer",
  description = "Explore bug area: <brief description>",
  task = "
  <bug_context>
  <error message, stack trace, and reproduction steps>
  </bug_context>

  <role>
  You are a read-only codebase exploration agent investigating a bug.
  </role>

  <task>
  Map the code path where this bug occurs. Produce a Codebase Map focused on:
  1. The exact call chain from entry point to error location
  2. Data flow through the failing path — what values are passed at each step
  3. Related test files and their coverage of this path
  4. Recent changes to files in this path (check git log for each file)
  5. Similar working code paths for comparison

  Trace BACKWARD from the error: start at the symptom, find the immediate cause,
  then trace up the call chain until you find the original trigger.
  </task>

  <constraints>
  - Every finding must cite file:line
  - Separate observations (what you saw) from hypotheses (what you infer)
  - Focus only on the bug-relevant code path
  </constraints>"
)
```

If the bug involves external APIs, libraries, or unfamiliar patterns, also dispatch the `researcher`:

```
subagent(
  agent = "researcher",
  description = "Research: <library/API involved>",
  task = "
  <bug_context>
  <error message and relevant code snippets>
  </bug_context>

  <role>
  You are a research agent investigating a bug involving external dependencies.
  </role>

  <task>
  Research the specific behavior causing this bug:
  1. Search for known issues, breaking changes, or behavioral quirks
  2. Check library documentation for the specific API/method involved
  3. Search for similar bug reports or Stack Overflow discussions
  4. Identify version-specific behavior differences

  Cite every finding with its source.
  </task>"
)
```

### 4e: Root Cause Tracing

Apply backward tracing through the call chain. For detailed technique, see [references/root-cause-tracing.md](references/root-cause-tracing.md).

The sequence:
1. **Observe the symptom** — Document what manifests.
2. **Find immediate cause** — Which code directly produces the error.
3. **Trace one level up** — What called that code? What values were passed?
4. **Keep tracing** — Continue up the call chain, examining values at each level.
5. **Find original trigger** — Where the invalid state originated.

At each level, verify values by reading the actual code — do not infer.

### 4f: Form and Test Hypotheses

State your theory: "I think X is root cause because Y" (cite evidence).

Add each hypothesis to the Hypotheses section:

```markdown
## Hypotheses
1. [UNTESTED] The empty string passed as `cwd` causes git init in the wrong directory
   - Evidence: `src/manager.ts:42` receives `projectDir` which is `''`
   - Test: Add logging before git init to confirm value
```

Test hypotheses one at a time. Update status to CONFIRMED or REJECTED with evidence.

### 4g: Update State

Update `DEBUG.md`:
- Set `phase: ROOT_CAUSE_FOUND` (or `phase: INVESTIGATING` if not yet found)
- Fill in the Root Cause section with the confirmed hypothesis
- Log all investigation steps in the Investigation Log

**Do NOT proceed to Phase 2 until root cause is confirmed with evidence.**

## Step 5: Phase 2 — Pattern Analysis

**Goal:** Understand the fix context before writing code.

1. **Find similar working code** — Search the codebase for analogous patterns that work correctly:
   - `Grep` for the function/method name with different arguments or callers
   - `Glob` for sibling modules that implement similar logic (e.g., other handlers, other adapters)
   - Check test files for the broken code path — they may reveal the intended behavior

2. **Compare working vs broken** — Read both code paths side by side. Identify every difference: argument order, error handling, null checks, type conversions, initialization. The root cause is often one of these differences.

3. **Check for wider impact** — Search for the same broken pattern elsewhere in the codebase:
   - `Grep` for the function/API that caused the bug — other callers may have the same issue
   - `Grep` for the same variable name or pattern in the same package
   - Check if the broken code was copy-pasted from somewhere (search for distinctive strings)

4. **Understand dependencies** — What else depends on the code you'll change? Use `Grep` for imports of the affected module and callers of the affected function.

Log findings in the Investigation Log.

## Step 6: Phase 3 — Fix Implementation

**Goal:** Minimal, targeted fix addressing the root cause.

### 6a: Write Failing Test First

Create a test that reproduces the bug:

1. Write a test that triggers the exact bug condition.
2. Run it — verify it FAILS for the expected reason.
3. This test proves the fix works when it passes.

**If a test cannot be written** (environment-specific, race condition): Document why in the Investigation Log and describe the manual verification method.

### 6b: Implement Single Fix

Fix the root cause — not the symptom. Change one thing at a time.

Dispatch a fresh `implementer` if the fix requires significant code changes:

```
subagent(
  agent = "implementer",
  description = "Fix bug: <brief description>",
  task = "
  <root_cause>
  <confirmed root cause with evidence>
  </root_cause>

  <fix_approach>
  <specific fix to implement — what to change and why>
  </fix_approach>

  <context>
  <relevant code paths, working analogies, and constraints from investigation>
  </context>

  <role>
  You are an implementation agent fixing a specific, investigated bug.
  </role>

  <task>
  Implement the fix described in <fix_approach>. Follow TDD:
  1. The failing test already exists (or write one first)
  2. Implement the minimal fix to make the test pass
  3. Verify all existing tests still pass
  4. Commit via /atcommit skill
  </task>

  <constraints>
  - Fix ONLY the root cause — no refactoring, no improvements, no cleanup
  - One logical change only
  - Do not change code outside the bug-relevant path
  </constraints>"
)
```

### 6c: Add Defense-in-Depth

After the primary fix, add validation at intermediate layers to prevent regression. See [references/defense-in-depth.md](references/defense-in-depth.md).

The four layers:
1. **Entry point validation** — Reject invalid input at API boundaries
2. **Business logic validation** — Check preconditions in internal functions
3. **Environment guards** — Prevent dangerous operations in specific contexts
4. **Debug instrumentation** — Log forensic context for future investigation

Add only layers that are proportional to the bug's severity. A typo fix does not need four layers of defense.

## Step 7: Phase 4 — Verification

**Goal:** Prove the fix works and nothing else broke.

1. **Run the failing test** — Verify it now PASSES.
2. **Run the full test suite** — Verify no regressions.
3. **Reproduce the original scenario** — Verify the original bug report scenario is resolved.
4. **Check edge cases** — Run related tests or manually verify adjacent scenarios.

Update `DEBUG.md`:
- Set `phase: VERIFIED`
- Fill in the Verification section with commands and output
- Set `status: resolved`

### Failure Protocol

An "attempt" is one cycle of: hypothesis → fix → verification failure. Each attempt gets logged in the Investigation Log with what was tried and why it failed.

If the fix doesn't work:
- **Attempt < 3:** Return to Phase 1 (Step 4). The root cause analysis was incomplete — re-examine rejected hypotheses and gather new evidence.
- **Attempt >= 3:** Question the architecture. The bug may be structural — escalate to the user with all investigation findings.

Log each attempt in the Investigation Log.

## Step 8: Report

Present a debug summary:

```markdown
## Debug Summary

**Bug:** <one-line description>
**Scope:** <PROD|STAGING|LOCAL> (org <2|197728|n/a>)
**Phase 0 telemetry:** <key finding from prod data, or "skipped — local bug">
**Root Cause:** <one-line explanation>
**Fix:** <one-line description of the change>
**Verification:** <test names and results>
**Defense layers added:** <list or "none — proportional to severity">
**Session file:** <path to DEBUG.md>
```

## Error Handling

| Error | Action |
|-------|--------|
| Cannot reproduce the bug | Log reproduction attempts. Check environment differences. Ask user for more context. |
| Root cause unclear after full investigation | Log all findings. Present hypotheses to user. Ask for domain knowledge. |
| Fix introduces new test failures | Revert the fix. Return to Phase 2 — the pattern analysis missed a dependency. |
| Fix attempt >= 3 fails | Stop. Present all investigation findings. Recommend architectural review. |
| State file not found during resume | List existing debug sessions or start fresh. |
| Flaky test (intermittent failure) | Run 10+ times. Check for shared state, timing dependencies, or resource contention. |
| Phase 0 subagent returns empty results | Widen time window (1h → 4h → 24h). Verify service name matches Datadog `service:` tag. Confirm correct org (prod=2, staging=197728). |
| `pup` returns 401 in Phase 0 | Subagent must run `pup auth login` (and `pup auth login --org 197728` for staging) and retry. |
| Wrong site used (`datad0g.com`) | Stop. Re-run without `--site`. Default `datadoghq.com` is correct for both prod and staging services. |
| Service environment genuinely ambiguous | `ask_question`: prod / staging / local. Persist to DEBUG.md frontmatter before running Phase 0. |
