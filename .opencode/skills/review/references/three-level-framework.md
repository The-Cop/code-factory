# Three-Level Review Framework

Every PR review walks all three levels for every module.
Levels are not severity classes — they are different lenses on the same code.
A single hunk can produce findings at all three levels.

## Enumeration discipline

The review is exhaustive, not curated.
The first run of `/review` must surface every finding the framework would catch.
A second run on the same PR (after no edits) must produce the same list.
A second run on a partially fixed PR must only surface what the fixes did not touch.

Bright-line rules:

- Do not cap findings.
  If a module has 30 minor issues, list 30 minor issues.
- Do not collapse repeated instances.
  If the same defect appears at five locations, write five rows with five locations.
  Aggregation is the reader's job, not the reviewer's.
- Do not produce a "top issues" or "key findings" view.
  The findings table is the report, not a digest of it.
- Apply each check below independently before moving to the next.
  Do not skip a check because earlier checks already produced findings on the same lines.
  Different lenses catch different defects on the same code.
- For every check, record either at least one finding row or an explicit
  "scanned, no findings" tick in the per-check audit table (see `output-format.md`).
  A module is not reviewed until every check is ticked.

Rationalizations to refuse:

| Tempting thought | Why it is wrong |
|------------------|-----------------|
| "Only the top 5 critical issues matter." | The user asked for every issue, not a curated digest. |
| "These three nits collapse into one entry." | Each location is a separate fix; collapsing hides scope. |
| "This is a small PR, a shallow pass is enough." | The framework applies uniformly; depth does not scale with diff size. |
| "Pass 1 already flagged this line." | Each check is a different lens. Apply it independently. |
| "Listing every magic number would be noise." | Noise is the author's problem to triage, not the reviewer's to suppress. |

## Level 1: Intent and scope

The PR exists for a stated reason.
Every change must justify itself against that reason.
For each check, enumerate every instance in the changed hunks before moving on.

| Check | Enumerate every instance of |
|-------|-----------------------------|
| Alignment | Hunks that do not advance the stated or inferred PR intent. Every hunk that could be removed without breaking the PR's goal is a finding. |
| Scope creep | Unrelated refactors, opportunistic cleanups, dependency bumps, or formatting changes that obscure the real diff. |
| Missing pieces | Claims in the PR body or linked issues that have no corresponding code. Half-finished features behind a flag. |
| Surprise | Changes that are unexpected given the goal: new public API, schema migration, telemetry, vendored code. |
| Test alignment | Tests target the stated behavior, not only the code that was touched. |

Flag intent-vs-scope mismatches early.
A logically correct change that does not belong in this PR is still a problem.

## Level 2: Logic and behavior

Walk the new and modified control flow as if executing it.
Check the obvious paths and the paths the author hoped you would not check.
For each check, enumerate every instance in the changed hunks before moving on.

| Check | Enumerate every instance of |
|-------|-----------------------------|
| Control flow | Off-by-one, fence-post errors, wrong branch taken, missing else, fallthrough, early return that skips cleanup. |
| Nil/null/zero | Dereference of values that can be unset, default values that mean "absent" but are treated as valid, empty slice vs nil slice. |
| Error paths | Errors swallowed, returned but not handled, wrapped without context, surfaced to wrong layer. Partial failures left in inconsistent state. |
| Invariants | Pre/postconditions preserved across the change. State machine transitions still valid. Type contracts honored. |
| Concurrency | Race conditions, check-then-act without atomicity, shared mutable state without synchronization, goroutine/thread leaks, deadlocks. |
| Ordering | Operations that must happen in a specific order (init before use, lock before mutate, validate before persist). |
| Edge cases | Empty input, single element, large input, unicode, timezone, negative numbers, exact zero, off-by-one boundaries. |
| Backward compatibility | Public API signature changes, wire format changes, DB schema changes, config keys renamed or removed, default values flipped. |
| Old/new interactions | Newly added code path coexists with the old one. Migration steps. Feature flag transitions. Rollback safety. |
| Idempotency | Operations that may retry must produce the same result. Side effects guarded. |

## Level 3: Code quality and maintainability

The change is correct but does the next reader pay for it?
Apply this level after correctness is verified.
For each check, enumerate every instance in the changed hunks before moving on.

| Check | Enumerate every instance of |
|-------|-----------------------------|
| Duplication | Repeated constants, copy-pasted blocks, parallel hierarchies that should share. Three is the threshold for extraction. |
| Magic values | Hardcoded numbers, strings, timeouts without a named constant or comment explaining the value. |
| Dead code | Functions, branches, or imports left behind. Comments referencing removed code. TODOs older than the file. |
| Abstractions | Leaky abstractions that expose internals. Premature abstractions with one caller. Wrong abstraction (forced into a pattern that does not fit). |
| Naming | Stuttering (`user.UserService`), generic names (`Manager`, `Helper`, `Util`), misleading names that suggest behavior the code does not have. |
| Patterns | Inconsistent with sibling files in the same module. New pattern introduced without removing the old one. |
| Error handling | Granularity and consistency across the layer. User-facing messages do not leak internals. Logs include enough context to debug. |
| Security | Injection (SQL, shell, HTML), insecure deserialization, secrets in code or logs, broken auth/authz, regression in input validation. |
| Performance | N+1 queries, allocations on hot paths, blocking I/O in async code, redundant work in loops, missing pagination on large reads. |
| Test quality | Tests assert behavior, not implementation. Meaningful assertions over presence checks. No over-mocking. Edge cases covered. Tests fail for the right reason. |
| Test seams | New code is testable without setting up the world. Dependencies inverted at the boundary that needs to be mocked. |

## Severity tagging

Tag every finding with severity and confidence:

| Severity | Meaning |
|----------|---------|
| Critical | Blocks merge. Bug, security flaw, broken contract, data loss risk, breaking change without migration path. |
| Major | Should be addressed in this PR. Significant code smell, missing test for new behavior, performance regression, unclear scope. |
| Minor | Suggestion or nit. Style, naming, optional refactor, documentation gap. |

| Confidence | Meaning |
|------------|---------|
| HIGH | Definite issue with code evidence. The reviewer can point at the line and explain why it fails. |
| MEDIUM | Likely issue based on patterns or context. Probable but not proven. |
| LOW | Subjective observation or preference. Alternative approach. |

A finding can be Critical/MEDIUM (likely a bug, would block merge if confirmed) or Minor/HIGH (a definite nit).
The combinations are independent.

## Per-check audit

Every module ends with a per-check audit table that lists each of the checks above.
For each check, mark `✓ findings` if at least one finding row exists in the module's findings table,
or `✓ scanned` if the check was applied and produced nothing.
Never leave a check unmarked.
See `output-format.md` for the table format.

## Pass 2 self-audit

After Pass 1 enumerates findings across all modules, Pass 2 re-reads each changed file
once more with the union of Pass 1 findings in mind.
Pass 2 specifically scans for the categories most often missed in Pass 1:

- Cross-file issues: the same defect repeated in sibling files, inconsistent patterns across the module.
- Old/new code interactions: defects exposed by the diff that live on lines the diff did not modify.
- Test gaps: behavior added without an assertion, or assertions that only check presence.
- Error wrapping and propagation: errors returned without context, dropped at a boundary, or logged and swallowed.
- Dead code, magic values, and stale comments left behind by the diff.

Pass 2 findings are added to the same per-module findings table.
There is no separate Pass 2 section in the output.
