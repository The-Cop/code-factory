# State File Schema

Reference for the /do skill's state file format. Load when creating or parsing state files.

## Directory Structure

```
~/docs/plans/do/<short-name>/
  FEATURE.md              # Canonical state and living document
  RESEARCH.md             # Codebase map + research brief (written after RESEARCH)
  CONVENTIONS.md          # Immutable project conventions (extracted after RESEARCH)
  PLAN.md                 # Milestones, tasks, validation strategy (written after PLAN_DRAFT)
  REVIEW.md               # Review feedback (written after PLAN_REVIEW)
  VALIDATION.md           # Validation results with evidence (written after VALIDATE)
  SNAPSHOT.md             # Task-scoped resume context (regenerated at phase/milestone transitions)
  events.jsonl            # Append-only, one JSON object per line (written from EXECUTE onward)
  HANDOFF.md              # Workspace handoff (written in DONE phase for workspace mode, optional)
  tasks/                  # Pre-computed task execution bundles (written after PLAN_REVIEW)
    TASK-001.md           # Self-contained bundle for T-001
    TASK-002.md           # Self-contained bundle for T-002
    TASK-042.md           # Discovered during work (discovered_from: T-002)
    ...
```

## FEATURE.md (main state file)

```markdown
---
schema_version: 1
short_name: user-auth
repo_root: /path/to/repo
worktree_path: /path/to/worktrees/repo-user-auth  # set during EXECUTE setup (null if no worktree)
workdir_mode: worktree  # worktree | branch_only | current_branch | workspace
base_branch: default  # default | <branch-name>
branch: feature/user-auth
base_ref: abc123
current_phase: EXECUTE
phase_status: in_progress
phase_terminal_reason: null  # null when phase_status != blocked; otherwise: succeeded | failed | timed_out | stalled | canceled_by_reconciliation | user_blocked
milestone_current: M-002
last_checkpoint: 2025-02-12T10:30:00Z
last_commit: def456
interaction_mode: interactive  # or "autonomous"
analysis_only: false  # true when task is research/analysis, no code changes
ambiguity_score: 0.15  # weighted ambiguity from refiner (0.0-1.0, gate: <= 0.2)
token_budget_usd: null  # optional, set via --budget flag (null = unlimited)
token_spent_estimate_usd: 0.00  # running total, updated after each TASK_COMPLETE
last_plan_amendment: null  # ISO timestamp of most recent PLAN.md amendment (null = no amendments)
---

# <Feature Name>

<Brief description of what this feature does>

## Acceptance Criteria

> Note: `phase_status` and `phase_terminal_reason` describe the current phase's lifecycle state.
> See **Phase Status and Terminal Reasons** below for the enum definitions and recovery routing.

**Functional Criteria** (binary pass/fail):

| # | Criterion | Verification Method |
|---|-----------|-------------------|
| F1 | <What must be true> | <Command, test, or observation to verify> |

**Edge Case Criteria** (binary pass/fail):

| # | Criterion | Verification Method |
|---|-----------|-------------------|
| E1 | <Edge case handled> | <How to trigger and verify> |

## Progress

**Marker legend:**

| Marker | Meaning |
|-|-|
| `[x]` | Complete |
| `[ ]` | Pending (planned, not started) |
| `[~]` | Discovered mid-flight — bundle filed, awaiting DONE triage |
| `[→]` | Discovered → filed externally (include issue URL) |
| `[-]` | Discovered → discarded during triage (rationale in bundle body) |

- [x] (2025-02-12 09:45Z) REFINE phase complete
- [x] (2025-02-12 10:00Z) RESEARCH phase complete
- [x] (2025-02-12 10:30Z) PLAN_DRAFT phase complete
- [x] (2025-02-12 11:00Z) PLAN_REVIEW phase complete - approved
- [x] (2025-02-12 11:15Z) T-001: Set up project structure (commit abc123)
- [ ] T-002: Implement core logic
- [ ] T-003: Add tests
- [~] T-DISC-001 (discovered from T-002) — Flaky login test exposes race in existing auth middleware
- [→] T-DISC-002 (discovered from T-005) — Convention drift in error handling — https://github.com/org/repo/issues/142
- [-] T-DISC-003 (discovered from T-007) — Stale TODO in legacy module — discarded (not a real defect)

## Surprises and Discoveries

<Unexpected findings during implementation>

## Decisions Made

<Decision log with rationale>

- Decision: <what was decided>
  Rationale: <why>
  Date: <timestamp>

## Open Questions

<Unresolved questions requiring input>

## Outcomes and Retrospective

<Final summary when complete - what worked, what didn't, lessons learned>
```

## Phase Status and Terminal Reasons

`phase_status` is the lifecycle state of the current phase as observed by SKILL.md.
It is set by the orchestrator when its dispatch returns and read by SKILL.md to decide what to do next.

| `phase_status` | Meaning |
|-|-|
| `not_started` | The phase has been entered but no orchestrator dispatch has run yet |
| `in_progress` | An orchestrator dispatch is active for this phase |
| `approved` | The phase finished successfully — SKILL.md may advance `current_phase` |
| `in_review` | The phase produced output awaiting interactive user approval (REFINE/PLAN_REVIEW/VALIDATE) |
| `blocked` | The phase did not finish successfully — `phase_terminal_reason` MUST be set |

`phase_terminal_reason` distinguishes the reason a phase ended in `blocked` so the resume
path can choose the right recovery action.
It MUST be `null` whenever `phase_status` is not `blocked`,
and MUST be one of the values below whenever `phase_status` is `blocked`.

| `phase_terminal_reason` | Meaning | Resume action |
|-|-|-|
| `succeeded` | Reserved (do not use with `blocked`) — set when transitioning to `approved` if a dedicated terminal record is needed | n/a |
| `failed` | The phase produced an error verdict (reviewer rejection, validator fail, adversarial stalemate) | Re-dispatch the same phase with critic feedback |
| `timed_out` | The phase exceeded its wall-clock budget | Re-dispatch with the same context |
| `stalled` | A dispatched subagent stopped emitting output past the configured stall window | Re-dispatch with the same context (see workflow-rules.md Stall Detection) |
| `canceled_by_reconciliation` | A pre-dispatch reconciliation check failed (worktree drift, branch mismatch, budget exhausted, external tracker terminal) | Resolve the underlying drift before re-dispatching; surface to the user |
| `user_blocked` | The user paused or denied at an interactive checkpoint | Resume only on explicit user instruction |

**Setting the field.** When the orchestrator marks `phase_status: blocked`,
it MUST also write `phase_terminal_reason` in the same FEATURE.md frontmatter update.
Leaving the reason `null` while `phase_status: blocked` is a workflow violation —
the resume path cannot route a generic block to the correct recovery action.

**Clearing the field.** When `phase_status` advances away from `blocked`
(e.g., `blocked → in_progress` on resume, or `blocked → approved` after a successful retry),
the orchestrator MUST set `phase_terminal_reason: null` in the same update
to keep the state file's invariant intact.

## RESEARCH.md

```markdown
# Research: <Feature Name>

## Problem Statement
- (Summarize the problem clearly - show deep understanding)

## Current Behavior
- (What happens today)
- (If a bug: include minimal repro and expected vs actual)

## Desired Behavior
- (What "done" means - verifiable outcomes)

## Codebase Map

### Entry Points
- `path/to/file:function` - Description

### Main Execution Call Path
- `caller` → `callee` → `next` (describe the flow)

### Key Types/Functions
- `path/to/file:Type` - Description
- `path/to/file:function` - Description

### Integration Points
- Where to add new functionality
- Existing patterns to follow

### Conventions
- Naming patterns, file organization, testing patterns

### Risk Areas
- Complex or fragile code requiring careful changes

## Findings (facts only)
- (Bullets; each includes `file:symbol` or `MCP:<tool> → <result>` or `websearch:<url> → <result>`)
- (Facts only - no assumptions here)

## Hypotheses (if needed)
- H1: <hypothesis> - <evidence supporting it>
- H2: <hypothesis> - <evidence supporting it>
- (Clearly marked as hypotheses, not facts)

## Solution Direction

### Approach
- (Strategic direction: what pattern/strategy, which components affected)
- (High-level only - NO pseudo-code or code snippets)
- (YES: module names, API/pattern names, data flow descriptions)

### Why This Approach
- (Brief rationale - what makes this the right choice)

### Alternatives Rejected
- (What other options were considered? Why not chosen?)

### Complexity Assessment
- **Level**: Low / Medium / High
- (1-2 sentences on what drives the complexity)

### Key Risks
- (What could go wrong? Areas needing extra attention)

## Research Brief

### Libraries/APIs
- Library name: key methods, usage patterns, gotchas

### Best Practices
- Pattern to follow with brief explanation

### Common Pitfalls
- What to avoid and why

### Internal References (Confluence)
- [Page](url) - Summary of what it covers

### External References
- [Source](url) - Summary of what it covers

## Open Questions
- (Questions that need answers before or during planning)
- (Mark as BLOCKING if it prevents planning)
```

## CONVENTIONS.md (Immutable Project Conventions)

Extracted once after the RESEARCH phase completes.
All downstream agents (planner, reviewer, implementer, task-critic, validator) inherit this document
instead of re-deriving conventions from RESEARCH.md.
Immutable for the feature lifecycle —
staleness during EXECUTE is handled by the Plan Amendment Protocol.

```markdown
# Project Conventions

> Extracted from RESEARCH phase. Immutable for this feature.
> If conventions change during EXECUTE, log a DEVIATION_MINOR and update PLAN.md task contracts.

## Tech Stack
- Language: <primary language>
- Framework: <primary framework>
- Key libraries: <list>

## Code Patterns

### Error Handling
- Pattern: <describe> (cite `file:line`)

### Logging & Observability
- Pattern: <describe> (cite `file:line`)

### Testing
- Framework: <name>
- Structure: <describe> (cite example test `file:line`)
- Naming: <convention>

### API / Interface
- Pattern: <describe> (cite `file:line`)

## Naming Conventions
- Files: <convention>
- Functions: <convention>
- Variables: <convention>
- Types: <convention>

## Build & Test Commands
- Build: `<exact command>`
- Test: `<exact command>`
- Lint: `<exact command>`
- Type check: `<exact command>`

## Immutable Constraints
These apply to ALL tasks regardless of what the plan says:
1. <constraint from codebase analysis>
2. <constraint from codebase analysis>
```

## events.jsonl

Append-only activity log — one JSON object per line.
The orchestrator and outer loop append events after each significant action.
Users can tail the file in their editor to watch progress;
`jq` queries give machine-readable filtering
(e.g., `jq 'select(.type=="DISCOVERED")' events.jsonl`).

**Common fields (every event):**

| Field | Type | Description |
|-|-|-|
| `ts` | string (ISO-8601 UTC) | Event timestamp |
| `type` | string | Event type (see table below) |
| `actor` | string | Who emitted it (see actor values below) |

**Actor values:**

| Actor | Who |
|-|-|
| `skill-md` | The outer SKILL.md loop |
| `orchestrator` | Phase or milestone orchestrator |
| `implementer` | Implementer agent |
| `task-critic` | Task-critic agent |
| `red-teamer` | Red-teamer agent |
| `reviewer` | Plan reviewer |
| `refiner` / `researcher` / `explorer` / `planner` / `validator` | Corresponding agents |
| `codex` | Codex integrations |
| `user` | Human-triggered event (approve, stop, accept-residual-risk) |

**Example stream:**

```jsonl
{"ts":"2026-04-21T09:45:00Z","type":"SESSION_START","actor":"skill-md","feature":"user-auth","branch":"feature/user-auth","workdir":"/path/to/wt","interaction_mode":"interactive","codex_available":true}
{"ts":"2026-04-21T09:45:02Z","type":"PHASE_ENTER","actor":"skill-md","phase":"EXECUTE"}
{"ts":"2026-04-21T09:45:05Z","type":"PREFLIGHT","actor":"orchestrator","build":"ok","tests":"142 pass / 0 fail","duration_ms":12300}
{"ts":"2026-04-21T09:46:00Z","type":"MILESTONE_START","actor":"orchestrator","milestone":"M-001","title":"Core Authentication"}
{"ts":"2026-04-21T09:46:30Z","type":"TASK_START","actor":"orchestrator","task":"T-001","title":"Set up project structure"}
{"ts":"2026-04-21T09:48:00Z","type":"TASK_COMPLETE","actor":"orchestrator","task":"T-001","tokens":23400,"duration_ms":90000,"spec":"COMPLIANT","quality":"APPROVED","adversarial_rounds":1,"verdict":"ACCEPT","red_team":"SKIPPED","cost_usd":0.35}
{"ts":"2026-04-21T09:51:00Z","type":"TASK_COMPLETE","actor":"orchestrator","task":"T-002","tokens":45100,"duration_ms":150000,"spec":"ISSUES","quality":"APPROVED","adversarial_rounds":2,"verdict":"ACCEPT","red_team":"SKIPPED","cost_usd":0.68}
{"ts":"2026-04-21T09:51:30Z","type":"DISCOVERED","actor":"orchestrator","from_task":"T-002","discovered":"T-042","summary":"Flaky login test exposes race in existing auth middleware","risk":"Medium"}
{"ts":"2026-04-21T09:53:10Z","type":"MILESTONE_COMPLETE","actor":"orchestrator","milestone":"M-001","tokens":99700,"duration_ms":395000,"commits":3}
{"ts":"2026-04-21T09:57:00Z","type":"DEVIATION_MINOR","actor":"implementer","task":"T-007","summary":"Rate limiter needs Redis, plan assumed in-memory","amendment":"A1"}
{"ts":"2026-04-21T10:02:00Z","type":"PHASE_ENTER","actor":"skill-md","phase":"VALIDATE"}
{"ts":"2026-04-21T10:05:30Z","type":"SESSION_COMPLETE","actor":"skill-md","total_tokens":289400,"total_duration_ms":1230000,"commits":8,"milestones_completed":3,"milestones_total":3,"cost_usd":4.34}
```

**Canonical event vocabulary:**

Event `type` values are a closed set — downstream readers (status reporters, SNAPSHOT.md
regenerators, dashboards, retrospective tooling) rely on this vocabulary.
Adding a new event type is a schema change and requires updating this table.
Existing events are append-only — never rename, never repurpose.
If an event's meaning needs to evolve, add a new event type instead of redefining an old one.

**Event types:**

| Type | Common extra fields | When |
|-|-|-|
| `SESSION_START` | `feature`, `branch`, `workdir`, `interaction_mode`, `codex_available` | First event; opened on EXECUTE entry |
| `SESSION_COMPLETE` | `total_tokens`, `total_duration_ms`, `commits`, `milestones_completed`, `cost_usd` | All phases done |
| `PHASE_ENTER` | `phase` | Entering a new phase |
| `PHASE_END` | `phase`, `phase_status`, `phase_terminal_reason` (when blocked), `duration_ms` | Phase orchestrator dispatch returned; mirrors final FEATURE.md write |
| `PREFLIGHT` | `build`, `tests`, `lint`, `typecheck`, `duration_ms` | Pre-flight gate results |
| `MILESTONE_START` | `milestone`, `title`, `parallel_with` (optional) | Starting a milestone |
| `MILESTONE_COMPLETE` | `milestone`, `tokens`, `duration_ms`, `commits` | All tasks done + committed |
| `TASK_START` | `task`, `title` | Dispatching implementer |
| `TASK_COMPLETE` | `task`, `tokens`, `duration_ms`, `spec`, `quality`, `adversarial_rounds`, `verdict`, `red_team`, `cost_usd` | Task passed reviews (`verdict` is `ACCEPT` or `ACCEPT_WITH_CAVEATS`) |
| `TASK_FAILED` | `task`, `reason`, `adversarial_rounds`, `tokens`, `duration_ms` | Task ended without an ACCEPT verdict (safety valve, plan-invalidating discovery, user abort) |
| `DISPATCH_STARTED` | `agent`, `task_id` (optional), `started_at` | A Task subagent dispatch was issued (orchestrator-internal; reserved for stall detection) |
| `DISPATCH_RETURNED` | `agent`, `task_id` (optional), `elapsed_ms`, `outcome` | A Task subagent dispatch returned (orchestrator-internal; reserved for stall detection) |
| `STALL_DETECTED` | `agent`, `task_id` (optional), `elapsed_ms`, `stall_timeout_ms`, `action` | A dispatched subagent exceeded the stall timeout (reserved — see workflow-rules.md Stall Detection) |
| `RECONCILE_FAILED` | `phase`, `check`, `detail` | Pre-dispatch reconciliation rejected the next dispatch (reserved — see workflow-rules.md Pre-Dispatch Reconciliation) |
| `TEMPLATE_RENDER_ERROR` | `template`, `unresolved` (list of placeholder names) | Dispatch template rendering produced unresolved `{{var}}` placeholders (reserved — see dispatch-templates.md Strict Rendering) |
| `BATCH_COMPLETE` | `tasks` (list), `tokens`, `duration_ms` | Batch boundary reached |
| `DISCOVERED` | `from_task`, `discovered`, `summary`, `risk` | Out-of-scope issue captured as new bundle |
| `TRIAGE_COMPLETE` | `counts` object (`filed`, `backlog`, `discarded`) | DONE-phase triage finished for all pending T-DISC-* bundles |
| `DEVIATION_MINOR` | `task`, `summary`, `amendment` (ID) | Plan adjustment applied |
| `DEVIATION_MAJOR` | `task`, `summary` | Plan invalidation; batch paused |
| `DRIFT_CHECK` | `milestone`, `planned_files`, `actual_files`, `unplanned`, `test_ratio` | Milestone boundary drift measurement |
| `STAGNATION` | `task`, `classification`, `adversarial_rounds`, `action` | Fix-cycle max reached |
| `SAFETY_VALVE_BLOCKED` | `task`, `unresolved_flaws` | Adversarial budget exhausted; awaiting user |
| `EVOLUTIONARY_LOOP` | `criterion`, `evidence`, `action` | Acceptance criterion proven wrong — loop to REFINE |
| `CODEX_DETECTION` | `available` | Codex CLI availability check |
| `CODEX_REVIEW` | `milestone`, `verdict`, `findings` | Codex milestone review |
| `CODEX_ADVERSARIAL` | `verdict`, `findings` | Codex adversarial gate |
| `CODEX_RESCUE` | `task`, `outcome` | Codex rescue for stagnation |
| `CODEX_SKIPPED` | `step` | Codex step skipped (CLI unavailable) |
| `CODEX_FAILED` | `step`, `reason` | Codex invocation failed |
| `BUDGET_WARNING` | `spent_usd`, `budget_usd`, `percent` | ≥80% of budget consumed |
| `BUDGET_EXHAUSTED` | `spent_usd`, `budget_usd` | 100% reached; stopping or pausing |

Events tagged "reserved" in the table above are part of the vocabulary
but their emitters land in later changes
(stall detection and pre-dispatch reconciliation arrive with the resilience PR;
strict template rendering arrives with the safety PR).
Documenting them here keeps the vocabulary closed and lets downstream tooling parse
both current and future event streams without a schema change.

Token and duration values are cumulative per agent bundle
(implementer + task-critic + any red-team / codex invocations summed for each task).

**Append rules:**

- One event per line, no pretty-printing, no trailing comma, no multi-line JSON.
- Never rewrite or truncate `events.jsonl` — append only.
- Every event MUST include `ts`, `type`, `actor`.
- Unknown extra fields are allowed; downstream readers ignore what they do not recognize.

**Query recipes (`jq`):**

Copy-paste-ready one-liners for operating on a session's `events.jsonl`.

| What | Command |
|-|-|
| Total cost so far (USD) | `jq -s 'map(.cost_usd // 0) \| add' events.jsonl` |
| Total tokens | `jq -s 'map(.tokens // .total_tokens // 0) \| add' events.jsonl` |
| Last event (cold-resume pointer) | `tail -1 events.jsonl \| jq .` |
| All discovered bundles with origin | `jq 'select(.type=="DISCOVERED") \| {from:.from_task,id:.discovered,risk,summary}' events.jsonl` |
| Failed / blocked tasks | `jq 'select(.type=="SAFETY_VALVE_BLOCKED" or .type=="STAGNATION")' events.jsonl` |
| Deviations grouped by severity | `jq -s 'map(select(.type \| startswith("DEVIATION_"))) \| group_by(.type) \| map({type:.[0].type,count:length})' events.jsonl` |
| Milestone elapsed time (ms) | `jq 'select(.type=="MILESTONE_COMPLETE") \| {milestone,duration_ms,commits}' events.jsonl` |
| Budget burn rate (% spent over time) | `jq 'select(.type=="TASK_COMPLETE") \| {ts,cost_usd}' events.jsonl \| jq -s 'reduce .[] as $e (0; . + $e.cost_usd)'` |
| Count discoveries still untriaged | `jq -s 'map(select(.type=="DISCOVERED")) \| length' events.jsonl` (cross-check against `Grep(pattern="^status: discovered$", path="tasks/")`) |
| Adversarial rounds histogram | `jq -s 'map(select(.type=="TASK_COMPLETE") \| .adversarial_rounds) \| group_by(.) \| map({rounds:.[0],count:length})' events.jsonl` |

Use `-s` (slurp) when aggregating across events; omit for per-line filtering.
Chain with standard shell tools (`head`, `tail`, `wc -l`) for further shaping.

## PLAN.md

```markdown
# Plan: <Feature Name>

**Goal:** One sentence describing what this builds
**Architecture:** 2-3 sentences about the approach
**Tech Stack:** Key technologies, libraries, and frameworks involved

## Research Reference
- **Source**: path to RESEARCH.md
- **Problem**: 1-2 sentence summary
- **Solution direction**: 1-2 sentence summary from research recommendation

## Scope

### In Scope
- (Bullet list of what this plan covers)

### Out of Scope
- (Bullet list of what is explicitly NOT part of this change)

## File Impact Map

| File | Change Type | Risk | Description |
|------|-------------|------|-------------|
| `path/to/file.ts` | New / Modify / Extend / Delete | Low / Medium / High | Brief description |

Change types:
- **New**: File created from scratch
- **Modify**: Existing file, changing behavior
- **Extend**: Existing file, adding capability without changing existing behavior
- **Delete**: Removing file or significant code block

## Dependency Graph

Show task-to-task dependency edges and critical path:

```
T-001 -> T-002 (reason)
T-002 -> T-003, T-004 (reason)
T-003, T-004 -> T-005 (reason)

Critical path: T-001 -> T-002 -> T-004 -> T-005
Parallel opportunities: T-003 and T-004 can run concurrently
```

## Milestones

### M-001: <Milestone Name>
**Scope**: What exists after this milestone
**Verification**: How to prove it works
**Dependencies**: What must be true before starting

### M-002: <Milestone Name>
...

## Task Breakdown

### Milestone M-001

Each task MUST be broken into bite-sized steps (one action per step). Tasks introducing new behavior MUST follow TDD-first structure. NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST.

- [ ] T-001 (M-001) Task description
  - Depends on: [] (or list of task IDs)
  - Preconditions:
    - <verifiable condition that must be true before starting>
    - Verify: `<command>` → expected: <result>
  - Files: `path/to/file.ts` (New/Modify), `tests/path/to/file.test.ts` (New/Modify)
  - Risk: Low | Medium | High
  - Steps (TDD-first — mandatory for behavior changes):
    1. Write failing test (include complete test code — not "add a test for X")
    2. Run test → `<exact command>` → expected: FAIL with `<specific error message>`
    3. Implement minimal code to pass (include complete code or precise file:line edit instructions)
    4. Run test → `<exact command>` → expected: PASS (and all existing tests still pass)
    5. (Do NOT commit — changes accumulate until milestone boundary)
  - Postconditions:
    - <verifiable condition that must be true after completion>
    - Verify: `<command>` → expected: <result>
  - Acceptance: What "done" looks like (observable behavior, not internal state)
- [ ] T-002 (M-001) Task description
  - Depends on: [T-001]
  - Preconditions:
    - T-001 complete: <what T-001 produces that this task needs>
  - Risk: Medium
  - Steps: (TDD-first when behavior changes; direct edit → verify for config/refactor)
  - Postconditions:
    - <what this task produces for downstream tasks>
  - Acceptance: What "done" looks like

### Milestone M-002
- [ ] T-003 (M-002) ...

## Integration Points
- (List boundaries this change touches: APIs, file formats, inter-component contracts)
- (Flag any breaking changes or version considerations)

## Risk Guidelines

| Risk Level | When to Apply | Execution Approach |
|------------|---------------|-------------------|
| Low | Simple changes, additive, well-understood patterns | Execute normally |
| Medium | Multiple files, API interactions, state changes | Review code paths before committing |
| High | Security, data migrations, core logic changes | Think through ALL edge cases before writing code |

## Validation Strategy

### Existing Test Coverage
- (What existing tests already validate parts of this?)

### New Tests Required

| Test Name | Type | File | Description |
|-----------|------|------|-------------|
| test_name | Unit / Integration / E2E | path or "new file" | What it verifies |

### Test Infrastructure Changes
- [ ] None required
- [ ] Extending existing test framework
- [ ] Adding new test files to existing framework
- [ ] Significant test infrastructure changes (describe)

### Per-Milestone Validation
- M-001: Command to run, expected output
- M-002: Command to run, expected output

### Final Acceptance
- [ ] Criterion 1: How to verify
- [ ] Criterion 2: How to verify

## Assumptions
- (List assumptions made during planning that could be wrong)
- (These become verification points before/during implementation)

## Open Questions
- (Questions that must be answered before implementing specific tasks)
- (Flag which task is blocked by each question)

## Plan Amendments

Tracks deviations that changed the plan during EXECUTE.
Each amendment updates the affected task contracts so resuming agents read the current plan,
not the original plan plus unstructured deviation logs.

### A1: <short description> (<ISO timestamp>)
- **Trigger**: What was discovered and why the plan was wrong
- **Changed**: Which task preconditions/postconditions/steps were updated
- **Downstream impact**: Which downstream tasks had their contracts re-validated
- **Status**: Applied | Pending user review

## Recovery and Idempotency

### Safe to Repeat
- Tasks that can run multiple times

### Requires Care
- Tasks with side effects

### Rollback Plan
- How to revert if needed
```

## TASK-XXX.md (Task Execution Bundle)

Generated after PLAN_REVIEW approval. Each file is a self-contained execution packet —
an implementer reading only this file should have everything needed to execute the task.

```markdown
---
task_id: T-001
milestone: M-001
status: pending          # pending | ready | in_progress | complete | blocked | skipped | discovered
risk: Low                # Low | Medium | High
max_adversarial_rounds: 1  # Derived from risk: Low=1, Medium=2, High=3
depends_on: []           # Task IDs that must complete before this task
discovered_from: null    # T-XXX, or phase name (RESEARCH | PLAN_DRAFT | PLAN_REVIEW | VALIDATE) when filed outside EXECUTE; null for planned tasks
adversarial_rounds: 0    # Updated during execution
verdict: null            # null | ACCEPT | ACCEPT_WITH_CAVEATS | BLOCKED
commit_sha: null         # Set at milestone boundary after /atcommit
token_cost_usd: null     # Running cost for this bundle's executions (null until TASK_COMPLETE)
duration_ms: null        # Cumulative execution time (null until TASK_COMPLETE)
---

# Task: T-001 — <short description>

## Description

<Full task text from PLAN.md — what to implement and why>

## Preconditions

Check these before starting — if any fail, the task is blocked:

- [ ] <dependency task> complete: <what it produces that this task needs>
  Verify: `<command>` → expected: <result>
- [ ] <codebase condition>: <what must exist or be true>
  Verify: `<command>` → expected: <result>

## Files

| File | Change Type | Risk |
|-|-|-|
| `path/to/file.ts` | New / Modify / Extend | Low / Medium / High |
| `tests/path/to/file.test.ts` | New | Low |

## Steps

<Full TDD or direct steps from PLAN.md>

1. Write failing test: <complete test code>
2. Run test → `<exact command>` → expected: FAIL with `<message>`
3. Implement: <precise instructions or code>
4. Run test → `<exact command>` → expected: PASS
5. (Do NOT commit — changes accumulate until milestone boundary)

## Task Contract

### Scope
<Task description>

### Acceptance Criteria (pass/fail)
1. Build passes with zero errors after changes
2. All existing tests pass
3. Lint and type check pass with zero violations
4. <AC from plan — concrete and testable>

### Mandatory Invariants
1. Error handling: errors at system boundaries are caught, logged, and propagated
2. Compatibility: no breaking changes to public APIs unless task explicitly requires it
3. Observability: existing logging/metrics/tracing preserved or extended
4. Security: no new injection vectors, exposed secrets, auth gaps
5. Codebase conventions: new code follows patterns in comparable files

### Out of Scope
- Changes to files not listed above
- Pre-existing issues in unrelated modules
- Improvements beyond stated requirements

## Architectural Context

<Relevant excerpts from RESEARCH.md for this task's files>
<Entry points, key types/functions, integration points>
<Conventions relevant to this area of the codebase>

## Pattern References

<Actual code snippets from comparable files in the codebase, with file:line citations>

### Pattern: <name>
**Found in**: `path/to/comparable.ts:45-67`
```<language>
<actual code from the file>
```
**Mirror**: Follow this structure for naming, error handling, and return patterns.

## Prior Task Summary

<What preceding tasks accomplished, if this task depends on them. Omit if no dependencies.>

## Verification Commands

| Command | Expected Output |
|-|-|
| `<exact command>` | `<expected result>` |
```

**Bundle lifecycle:**
1. **Created** by the bundle generator after PLAN_REVIEW approval (`status: pending`)
   or by the orchestrator mid-EXECUTE as a discovered task (`status: discovered`, `discovered_from: T-XXX`)
2. **Promoted** to `status: ready` by the orchestrator when all `depends_on` tasks reach `status: complete`
   (queryable via `Grep(pattern="^status: ready$", path="tasks/")`)
3. **Read** by the milestone orchestrator when dispatching the implementer (`status: ready → in_progress`)
4. **Updated** after each adversarial round (status, adversarial_rounds, verdict)
5. **Finalized** at milestone boundary (status: complete, commit_sha, token_cost_usd, duration_ms)
6. **Read by outer loop** for resume (find first `ready` task) and progress tracking

**Discovered tasks:** carry `status: discovered` until the user decides their fate
at the DONE phase (fold into this feature, file externally, or defer).
They are never auto-promoted to `ready` — discovery without disposition is intentional,
the point is to capture the work structurally, not to quietly expand scope.

## SNAPSHOT.md (Resume Context)

Auto-generated at every phase transition and milestone completion.
Gives a cold-start agent everything it needs to pick up the next task
without reading RESEARCH.md, PLAN.md, or events.jsonl from scratch.

The snapshot is **task-scoped** — it answers "what does the next agent need to know
to do this specific task?" rather than summarizing the entire project.

```markdown
# Resume Snapshot

> Auto-generated — do not edit manually.
> Regenerated at each phase transition and milestone completion.

## Current State

- **Phase**: EXECUTE
- **Milestone**: M-002 — Protected Routes
- **Next Task**: T-004 — Implement auth middleware
- **Test Baseline**: 42 pass / 0 fail
- **Branch**: feature/user-auth
- **Last Commit**: abc123 "feat(auth): add login endpoint"
- **Uncommitted Changes**: none

## Next Task Contract

- **Preconditions**:
  - T-001 complete: project structure in place (pkg/, cmd/, tests/)
  - T-002 complete: login endpoint exists at /api/login
- **Postconditions**:
  - Auth middleware applied to /api/* routes
  - TestAuthMiddleware passes
- **Files**: pkg/middleware/auth.go (New), cmd/server/routes.go (Modify)
- **Risk**: Medium
- **Max Adversarial Rounds**: 2

## Key Decisions (affecting next task)

Extracted from FEATURE.md Decisions Made:

- D1: JWT for authentication (not session cookies) — stateless, no server-side session store needed
- D3: Middleware chain pattern from existing codebase — see routes.go:45

## Conventions

From CONVENTIONS.md (immutable for this feature):

- Middleware signature: `func(next http.Handler) http.Handler` (from existing RateLimiter)
- Tests use `testutil.NewTestServer()` pattern — see auth_test.go:12
- Error responses: `pkg/api/errors.go` ApiError struct

## Completed Work Summary

| Task | Milestone | What it produced |
|-|-|-|
| T-001 | M-001 | Project structure: pkg/, cmd/, tests/ directories |
| T-002 | M-001 | Login endpoint at /api/login with JWT generation |
| T-003 | M-001 | Unit tests for login (TestLogin, TestLoginInvalidCredentials) |

## Active Deviations

- (none)

## Plan Amendments

- (none)

## Discovered Tasks (Pending Triage)

Bundles with `status: discovered` surfaced during earlier phases.
A resuming agent must see these before starting the next task —
they may change priorities or reveal blockers.

| ID | From | By | Risk | Summary |
|-|-|-|-|-|
| T-DISC-001 | T-002 | implementer | Medium | Flaky login test exposes race in existing auth middleware |
| T-DISC-002 | RESEARCH | explorer | Low | CONVENTIONS.md error pattern conflicts with actual code in pkg/api |

Leave the table header with "(none)" when no discovered bundles exist.
Triage happens at DONE (see phase-flow.md DONE step 1.3).

## Budget Status

- **Budget**: $5.00 (or unlimited)
- **Spent**: $1.23
- **Remaining**: $3.77 (75.4%)
```

**Snapshot lifecycle:**
1. **Created** on first EXECUTE entry (after PLAN_REVIEW + bundle generation)
2. **Regenerated** at every phase transition and milestone completion by the SKILL.md outer loop
3. **Included** in milestone orchestrator dispatch as `<resume_snapshot>` (replaces thin context slices)
4. **Read** on resume (Step 5a) to reconstruct context without re-reading all state files
