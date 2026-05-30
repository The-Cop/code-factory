# Phase Flow — Detailed Descriptions

Reference for detailed phase behaviors. Loaded by the orchestrator when executing phases.

## Phase Dispatch Protocol

The SKILL.md outer loop dispatches a fresh orchestrator per phase. Each dispatch includes
only the context that phase needs, loaded from state files.

### Context Payloads (what SKILL.md loads per phase)

| Phase | Context Loaded from State Files | Context Size |
|-|-|-|
| REFINE | feature_request, repo_root, brainstorm_context, hydrated_context | Small |
| RESEARCH | FEATURE.md (refined spec section), repo_root | Small |
| PLAN_DRAFT | FEATURE.md (spec + criteria), full RESEARCH.md, CONVENTIONS.md | Medium |
| PLAN_REVIEW | full PLAN.md, CONVENTIONS.md, FEATURE.md (criteria) | Medium |
| BUNDLE_GENERATION | full PLAN.md, full RESEARCH.md, FEATURE.md (criteria), CONVENTIONS.md | Medium |
| EXECUTE (per milestone) | milestone task bundles, FEATURE.md (progress), events.jsonl tail, CONVENTIONS.md | Medium |
| VALIDATE | FEATURE.md (criteria), PLAN.md (validation strategy), git diff output, CONVENTIONS.md | Medium |
| DONE | full FEATURE.md, VALIDATION.md, events.jsonl summary | Small |

Note: PLAN_REVIEW reviewer gets CONVENTIONS.md (compressed conventions) instead of full RESEARCH.md.
Red-teamer still receives RESEARCH.md for assumption attacks.

### Return Contract (what SKILL.md reads after each dispatch)

| Phase | SKILL.md Reads | Decision |
|-|-|-|
| REFINE | FEATURE.md phase_status, phase_terminal_reason | approved → advance; blocked → route by terminal reason |
| RESEARCH | FEATURE.md phase_status, phase_terminal_reason, RESEARCH.md exists | approved → advance; blocked → route by terminal reason |
| PLAN_DRAFT | FEATURE.md phase_status, phase_terminal_reason, PLAN.md exists | approved → advance; blocked → route by terminal reason |
| PLAN_REVIEW | FEATURE.md phase_status, phase_terminal_reason | approved → bundle + EXECUTE; blocked → PLAN_DRAFT (or route per terminal reason) |
| BUNDLE_GENERATION | tasks/ directory populated | verified → EXECUTE |
| EXECUTE (milestone) | FEATURE.md progress, task bundle statuses | all complete → next milestone or VALIDATE |
| VALIDATE | FEATURE.md phase_status, phase_terminal_reason | approved → DONE; blocked → EXECUTE (or route per terminal reason) |
| DONE | FEATURE.md (outcomes, PR URL) | report to user |

### Terminal Reason Routing (blocked phases)

When `phase_status: blocked`, SKILL.md reads `phase_terminal_reason` and chooses the recovery path.
See state-file-schema.md "Phase Status and Terminal Reasons" for the enum semantics.

| `phase_terminal_reason` | SKILL.md action |
|-|-|
| `failed` | Re-dispatch the same phase, passing critic/reviewer feedback as `<state_drift>` context |
| `timed_out` | Re-dispatch the same phase with the original context — no feedback to add |
| `stalled` | Re-dispatch the same phase with the original context — no feedback to add |
| `canceled_by_reconciliation` | Surface the reconciliation `check` and `detail` to the user; do NOT re-dispatch until the underlying drift is resolved |
| `user_blocked` | Halt; resume only when the user issues an explicit instruction |
| `succeeded` | Treat as a writer error — the reason is reserved and must not appear with `phase_status: blocked`. Log and surface for review. |

Loop limits in **Phase Loop Conditions** still apply when re-dispatching after `failed` / `timed_out` / `stalled`.

### Phase Dispatch Protocol (orchestrator responsibilities on return)

Every phase orchestrator MUST, before its dispatch returns:

1. Set `phase_status` in FEATURE.md frontmatter to one of `approved`, `in_review`, or `blocked`.
2. If `phase_status: blocked`, also set `phase_terminal_reason` to a non-null value from the enum
   (state-file-schema.md "Phase Status and Terminal Reasons"). Setting `blocked` without a reason
   is a workflow violation — SKILL.md cannot route the recovery without it.
3. If `phase_status` advances away from `blocked`, set `phase_terminal_reason: null` in the same write.
4. Append a `PHASE_END` event to events.jsonl with `phase`, `phase_status`, `duration_ms`, and
   `phase_terminal_reason` (when blocked). The event MUST mirror the FEATURE.md write — readers
   that watch only events.jsonl rely on this consistency.

### Phase Loop Conditions

| Loop | Trigger | Max Iterations |
|-|-|-|
| PLAN_REVIEW → PLAN_DRAFT | Required changes or critical red-team findings | 3 |
| VALIDATE → EXECUTE | Validation failures or quality gate fails | 2 |
| EXECUTE milestone retry | Task adversarial stalemate requiring re-plan | 1 (then escalate) |

### Resume Snapshot Protocol

The SKILL.md outer loop generates SNAPSHOT.md at every phase transition and milestone completion.
See state-file-schema.md for the full schema.

**When to regenerate:**
1. After each phase completes (before advancing `current_phase`)
2. After each milestone completes during EXECUTE
3. On resume (Step 5a) — verify snapshot matches reality, regenerate if stale

**How to generate:**
1. Read FEATURE.md (progress, decisions, open questions)
2. Read task bundle statuses to find the next pending task
3. Read that task's TASK-XXX.md for contract, files, steps
4. Extract relevant decisions from FEATURE.md Decisions Made
5. Include relevant sections from CONVENTIONS.md (only patterns affecting the next task's files)
6. Summarize completed tasks (one line each: task ID, milestone, what it produced)
7. Include active deviations and plan amendments
8. **Enumerate pending triage bundles:** list every `tasks/T-DISC-*.md` where `status: discovered`
   (`Grep(pattern="^status: discovered$", path="tasks/")`). Populate the Discovered Tasks table with
   id, discovered_from, discovered_by, risk, and the first-line summary from the bundle body.
   If none, write "(none)".
9. Include budget status if `token_budget_usd` is set
10. Write to `SNAPSHOT.md` in the state directory

**Why snapshots exist:** When a milestone orchestrator starts cold,
it needs to understand why the plan chose this approach,
what prior tasks produced, and what conventions apply — not just the task description.
Twenty lines of RESEARCH.md won't carry that context.
The snapshot compresses all accumulated decisions into a task-scoped document.

### Milestone Dispatch Protocol (EXECUTE)

SKILL.md reads PLAN.md to build the milestone dependency graph and reads task bundle statuses.

1. Identify ready milestones: all dependencies complete, has pending tasks
2. Check File Impact Map for file overlap between ready milestones
3. No overlap → dispatch in parallel (multiple Task calls in one message)
4. Shared files → dispatch sequentially
5. After each milestone completes: regenerate SNAPSHOT.md, re-read task bundles, update dependency graph, identify next ready milestones

## EXECUTE Batch Loop

```
Plan Critical Review -> Pre-flight validation gate (build + test + lint + typecheck baseline, hard gate) -> Initialize events.jsonl
  -> Identify ready milestones (dependency graph) -> Execute round -> Batch Report -> Feedback -> Next round

Execute round:
  1. Find READY milestones (all dependencies completed, status = pending or in_progress)
  2. If multiple ready milestones have NO file overlap (per File Impact Map) -> run in PARALLEL
     Otherwise -> run SEQUENTIALLY (current behavior)
  3. For each active milestone, promote next pending task to `ready` (frontmatter status), pick next ready task:
     - Dispatch implementers (parallel across milestones, sequential within)
     - Shift-left (lint/format/typecheck) per task
     - Spec review (max 2 fix cycles) per task
     - Code quality review (max 2 fix cycles) per task
     - Red-team review (HIGH-RISK TASKS ONLY, max 2 fix cycles) per task
     - File `discovered_from` bundles for any out-of-scope failures surfaced (Discovery Capture Protocol)
     - Append TASK_COMPLETE event to events.jsonl with tokens/duration/cost
  4. At MILESTONE BOUNDARY: Run /atcommit, append MILESTONE_COMPLETE event to events.jsonl

STOP on: missing deps, test failures, unclear instructions, adversarial stalemate on all flaws, plan-invalidating discoveries
DEVIATION_MINOR: propose plan edit, ask user (interactive) or log and adjust (autonomous)
DEVIATION_MAJOR: pause execution, recommend re-planning
```

## DONE Finalization

```
Tests pass -> /atcommit (remaining) -> git push -> /pr (create PR) -> /pr-fix (validate + fix)
                                                                           |
                                                                           v
                                                                  New feedback? --yes--> /pr-fix (max 2 loops)
                                                                           |
                                                                           no
                                                                           |
                                                                           v
                                                                     Report + Archive
```

## REFINE Phase
- Spawn `refiner` to analyze, clarify, and explore approaches for the feature
- Output: Refined specification with problem statement, chosen approach, scope, behavior, acceptance criteria
- Well-specified descriptions pass through quickly; vague ones get iterative refinement
- Refiner proposes 2-3 approaches with trade-offs and gets user preference before finalizing
- Refiner asks one question at a time (prefer multiple choice) to reduce cognitive load
- **Interactive**: Asks clarifying questions, proposes approaches. After refiner completes, orchestrator presents the refined spec summary and WAITS for explicit user approval before proceeding to RESEARCH. User can approve, adjust, or request further refinement.
- **Autonomous**: Synthesizes from context, selects best approach, logs decisions in Decisions Made

## RESEARCH Phase
- Spawn `explorer` and `researcher` **in parallel** (both in a single message) for latency reduction
- `explorer`: **local codebase** mapping (modules, patterns, conventions)
- `researcher`: follows a structured research sequence:
  - **Step 0 — Domain Research Evaluation**: determines if the task relies on knowledge outside the codebase (external APIs, file formats, protocols, specs, third-party services)
  - **Step 1 — External Domain Research** (only if triggered): WebSearch/WebFetch for authoritative sources, edge cases, and non-obvious behaviors BEFORE Confluence
  - **Step 2 — Confluence + General Web Research**: design docs, RFCs, APIs, best practices
- Output: Context, Assumptions (tagged: [EXTERNAL DOMAIN], [CODEBASE], [TASK DESCRIPTION]), Constraints, Risks, Open Questions
- **Both sources are mandatory** - do not skip Confluence search
- **Interactive**: Present research summary, ask user to confirm assumptions and scope
- **Autonomous**: Proceed with best interpretation, log assumptions in Decisions Made

### Conventions Extraction (end of RESEARCH phase)

After explorer and researcher return,
the orchestrator extracts project conventions into `CONVENTIONS.md` —
an immutable artifact that all downstream agents inherit.

**Why this exists**: Conventions scattered across RESEARCH.md get re-derived by every agent,
causing drift (one agent uses one pattern, another uses a different one)
and wasting tokens on redundant deliberation.
CONVENTIONS.md front-loads these decisions once.

**Extraction protocol:**
1. Read explorer's Conventions section and pattern catalog
2. Read explorer's Build Environment section for exact commands
3. Read explorer's Key Types/Functions for naming patterns
4. Synthesize into CONVENTIONS.md using the schema from state-file-schema.md
5. Every convention MUST cite a specific `file:line` as evidence
6. Write to `~/docs/plans/do/<short-name>/CONVENTIONS.md`

**Immutability rule**: CONVENTIONS.md is not updated during EXECUTE.
If a convention proves wrong,
the deviation is handled through the Plan Amendment Protocol
(update PLAN.md task contracts and FEATURE.md deviations, not CONVENTIONS.md).

## PLAN_DRAFT Phase
- Spawn `planner` to create plan (references both codebase findings AND Confluence context)
- Output: Milestones, Task Breakdown, Validation Strategy
- Plan must embed relevant context inline (not only links)
- **Interactive**: Present plan, ask user to approve or request changes
- **Autonomous**: Proceed to review, let reviewer catch issues

## PLAN_REVIEW Phase

**Single-step parallel review: reviewer + red-teamer + Codex plan challenge.**

Consistency checking is now the planner's responsibility (self-consistency pass in planner Step 5).
No separate consistency-checker dispatch is needed.

1. Spawn `reviewer`, `red-teamer`, AND `codex:codex-rescue` (plan challenge) **all in parallel** (single message):
   - All three read the same PLAN.md and RESEARCH.md — they are independent
   - Codex plan challenge is optional: skip if codex unavailable, log `CODEX_SKIPPED: plan_review`
   - `reviewer`: substantive critique (coverage, path verification, research cross-check, dependency analysis, safety, executability)
     - Output: Review report, required changes
   - `red-teamer` in plan mode: adversarial challenge of plan assumptions
     - Attacks assumptions (checks evidence strength in RESEARCH.md)
     - Enumerates failure modes per milestone (external deps, internal assumptions, data edge cases)
     - Identifies security attack vectors and missing recovery paths
     - Assesses blast radius of shared code changes
     - Output: Red Team Plan Review with Critical / High / Medium findings

2. After all complete (reviewer + red-teamer + Codex if available), merge findings:
   - Codex plan concerns → append to REVIEW.md under `## Codex Plan Challenge`
   - If reviewer has required changes → loop back to PLAN_DRAFT (discard red-team + Codex results)
   - **Critical red-team findings** → loop back to PLAN_DRAFT (must address before execution)
   - **High findings (interactive)** → present to user, ask whether to address or track as risks
   - **High findings (autonomous)** → log as tracked risks, proceed
   - **Medium findings** → logged as risks to watch during EXECUTE
- **Interactive**: Present review + red-team findings, ask user for final approval before execution
- **Autonomous**: Auto-approve if no critical issues, loop back for required changes only

## EXECUTE Phase
**Working directory is already set up.** Branch and worktree (if applicable) were created in Step 4 before any phase work began.
The orchestrator works from `<workdir_path>` and writes all state to `~/docs/plans/do/<short-name>/`.

**Session Activity Log:**

Initialize `events.jsonl` in the state directory on EXECUTE entry.
Append one JSON object per line after every significant action (see state-file-schema.md for event types, schema, and required fields).
Every event MUST include `ts`, `type`, and `actor`.
The log is append-only — never rewrite or truncate.
Tell the user the log path so they can tail it (`tail -f events.jsonl | jq .`) or query it with `jq` to watch progress in real-time.

**Plan critical review — before implementing anything:**

The orchestrator re-reads the entire plan with fresh eyes,
verifies task ordering and dependencies,
checks the worktree has what the plan expects.
Raises concerns before any code is written.

**Context Preparation:**

Read PLAN.md and extract ALL tasks with their full text,
acceptance criteria, dependencies, risk levels, and the File Impact Map.
Build the milestone dependency graph.
Store this extracted context — you will inline it into each subagent dispatch.
Never make subagents read plan files; provide full context directly in the prompt.

**Milestone-Level Parallelism:**

After context preparation, identify **ready milestones** — milestones whose dependencies are all completed.
When multiple milestones are ready simultaneously, check the File Impact Map for file overlap:

| Condition | Execution Mode |
|-----------|---------------|
| Ready milestones have **no file overlap** in File Impact Map | Run in **parallel** — one task per milestone dispatched in a single message |
| Ready milestones **share modified files** | Run **sequentially** — one milestone at a time (current behavior) |

Parallel dispatch: spawn one implementer Task per ready milestone in a single response message.
After all return, run shift-left checks and reviews for each.
Within a single milestone, tasks always run sequentially (they share files by definition).

Log parallel milestones as an event:
`{"ts":"<ISO8601>","type":"MILESTONE_START","actor":"orchestrator","milestone":"M-002","title":"<title>","parallel_with":["M-003"]}`

**Per-task sequence** (same whether running one or multiple milestones):

1. **Dispatch fresh implementer** with full task text + scene-setting context inlined
   (milestone position, prior task summary, upcoming tasks, relevant discoveries, architectural context).
   Implementer self-evaluates before reporting — catches obvious issues before the adversarial loop.
2. Implementer asks questions → answers provided → implements → self-evaluates → reports (NO commit)
3. **Shift-left validation** (deterministic — orchestrator runs directly, no subagent):
   lint + format + type-check. Auto-fix formatting.
   Return to implementer if lint/type errors persist.
   Only proceed to the adversarial loop after shift-left passes.
4. **Adversarial review loop** — the orchestrator runs an adversarial loop between the implementer
   and a task-critic agent. See **Adversarial Review Loop** section below for full protocol.
5. **Red-team review (HIGH-RISK TASKS ONLY)** — only for tasks marked `Risk: High` in the plan.
   Adversarially probes for input edge cases, security vulnerabilities, race conditions, failure modes.
   Receives relevant plan-level red-team findings to focus on known risk areas.
   Critical findings → implementer fixes (max 2 cycles). High/Medium → logged as tracked risks.
   Skipped entirely for Low and Medium risk tasks.
6. **Discovery Capture Protocol** — before marking the task complete,
   file a `discovered_from` bundle for every out-of-scope failure the task surfaced.
   See **Discovery Capture Protocol** section below. This runs even when the adversarial loop ACCEPTs.
7. Mark task complete (only after ACCEPT verdict — safety valve outcomes are blocking),
   update state (set bundle `status: complete`, populate `token_cost_usd` and `duration_ms`),
   append a `TASK_COMPLETE` event to events.jsonl with token/duration/adversarial-round metrics

**Adversarial Review Loop:**

The adversarial loop replaces the previous sequential spec-review → quality-review chain.
A single `task-critic` agent evaluates both spec compliance AND code quality with escalating depth per round.
The implementer and task-critic compete until the critic ACCEPTs or the safety valve triggers.

**Risk-Proportional Round Budget:**

| Task Risk | Max Rounds | Scrutiny Depth | Red Team |
|-|-|-|-|
| Low | 1 | Correctness only | Skip |
| Medium | 2 | Correctness + design | Skip |
| High | 3 | Full escalating | Yes |

Read `max_adversarial_rounds` from the task bundle frontmatter.

**Step 4a: Task Contract (Pre-Computed in Bundle)**

The task contract is pre-computed in each TASK-XXX.md bundle during bundle generation.
The orchestrator does not extract it at runtime. The format is:

```markdown
## Task Contract for T-XXX

### Scope
[Task description from PLAN.md]

### Acceptance Criteria (pass/fail)
1. Build passes with zero errors after changes
2. All existing tests pass
3. Lint and type check pass with zero violations
4. [AC-1 from plan — made concrete and testable]
5. [AC-2 from plan — made concrete and testable]

### Mandatory Invariants (always apply, even if not in plan)
1. Error handling: errors at system boundaries are caught, logged, and propagated
2. Compatibility: no breaking changes to public APIs unless task explicitly requires it
3. Observability: existing logging/metrics/tracing preserved or extended
4. Security: no new injection vectors, exposed secrets, auth gaps
5. Codebase conventions: new code follows patterns in comparable files

### Out of Scope
- Changes to files not listed in the task's file impact
- Pre-existing issues in unrelated modules
- Improvements beyond stated requirements
```

Each criterion must be binary pass/fail — not "looks good."
Include project-level criteria (build, lint, tests) from the pre-flight baseline.
The Mandatory Invariants ensure the critic can block on non-functional regressions
even if the plan omitted them.

**Step 4b: Adversarial Loop**

```
max_rounds = task_bundle.max_adversarial_rounds  # Low=1, Medium=2, High=3
Round = 1
while Round <= max_rounds:
  1. Dispatch task-critic with: task contract, round number, max_rounds, previous verdicts (round 2+)
  2. If VERDICT: ACCEPT → break loop, proceed to step 5 (red-team or mark complete)
  3. If VERDICT: REJECT:
     a. Stalemate check (round 2+ only, see below)
     b. Dispatch implementer to fix critical flaws
        - Pass all critical flaws with full proof
        - Pass weaknesses (especially persistent ones about to be promoted)
        - Implementer applies class-level fixes and self-evaluates before returning
     c. Re-run shift-left validation after fixes
     d. Round++, loop back to step 1

Safety valve (BLOCKING — both modes): if Round > max_rounds and not accepted:
  - Codex rescue attempt (if available)
  - If still unresolved: STOP. Require explicit user acceptance of residual risk.
  - Autonomous mode does NOT silently convert critical flaws to tracked risks — it stops and waits.
  - Special case: Low-risk task rejected twice → escalate (may be mis-classified risk level).
  - Classify stagnation for reporting context (does not auto-resolve)
```

**Stalemate Detection (orchestrator responsibility, round 2+ only):**

Before dispatching the implementer in step 3b, compare the current critic verdict
with the immediately preceding critic verdict.
A critical flaw is the "same flaw" across two consecutive rounds if it meets at least 2 of these 3 criteria:
1. Flaw titles share key nouns (e.g., "error handling in parse" and "incomplete error handling — parse function")
2. Flaws reference the same file and line range (within 10 lines)
3. Flaw descriptions identify the same root cause

When in doubt, treat evolved or narrowed versions of a flaw as distinct —
false negatives (missing a stalemate) are less harmful than false positives.

If the same flaw appears in both consecutive verdicts AND the implementer's response
in the intervening round proposed a fix for that flaw, that is a stalemate:
- Remove the stalemated flaw from the list passed to the implementer
- Flag it to the user with full context (both rounds' descriptions and the attempted fix)
- Continue the loop with remaining flaws
- If ALL remaining critical flaws are stalemated, stop the loop and trigger the safety valve

**Early acceptance:** If the task-critic ACCEPTs on round 1, proceed directly to step 5.
No adversarial rounds were needed — the implementation was solid on first review.

**Discovery Capture Protocol** (all phases — RESEARCH, PLAN, EXECUTE, VALIDATE):

Every failure, broken test, latent bug, stale doc, or out-of-scope issue surfaced by an agent MUST
be captured as a `discovered_from` bundle in `tasks/`. The protocol is not EXECUTE-only — obstacles
uncovered during research, planning, review, or validation deserve the same structural capture.
Never delete, disable, comment out a failing test, or silently drop a finding to "keep moving" —
filing a discovered bundle is always the right escape hatch.

**When to file a discovered bundle** (any of the following, in any phase):

| Phase | Signal | Example |
|-|-|-|
| EXECUTE | Pre-existing failing test uncovered by the task's work | Unrelated test in same package newly fails after refactor |
| EXECUTE | Latent bug the task's code exposes but does not cause | Null pointer in caller revealed by tightened API contract |
| EXECUTE | Dead code, TODO, or broken invariant spotted while navigating | `// FIXME` comment referencing a real ticket-less defect |
| EXECUTE | Out-of-scope refactor opportunity blocking clean test coverage | Shared helper needs split to unit-test the new path |
| EXECUTE/RESEARCH | Convention or doc mismatch with the code as it actually exists | CONVENTIONS.md says X, code does Y and Y is the true pattern |
| RESEARCH | Stale or incorrect Confluence/README/ADR referenced by the feature | Linked design doc still describes v1 API after v2 migration shipped |
| RESEARCH | Adjacent system defect surfaced during codebase mapping | Explorer finds an unhandled error branch unrelated to the feature |
| PLAN_DRAFT/PLAN_REVIEW | Planner or reviewer spots work outside scope but worth capturing | Review flags a latent migration safety gap while validating task contracts |
| VALIDATE | Validator detects a regression outside the feature's changeset | Baseline comparison surfaces a pre-existing flaky test newly unmasked |

**How to file** (one frontmatter write — seconds of work):

1. Create `tasks/T-DISC-<NNN>.md` with frontmatter:
   ```yaml
   id: T-DISC-<NNN>
   status: discovered
   risk: <low|medium|high>
   milestone: null
   discovered_from: <T-XXX | RESEARCH | PLAN_DRAFT | PLAN_REVIEW | VALIDATE>
   discovered_by: <actor>           # implementer | task-critic | red-teamer | validator | explorer | researcher | planner | reviewer
   summary: <one-line description>
   ```
   For RESEARCH/PLAN/VALIDATE origins where no parent task exists, set `discovered_from` to the
   phase name (e.g., `RESEARCH`) and leave `milestone: null`.
2. Body: 3-5 sentences — what was found, where (file:line or doc URL), why it is out of scope for
   the current feature, what the minimum fix looks like.
3. Append a `DISCOVERED` event to events.jsonl with `from_task` (or phase name), `discovered`
   (bundle id), `summary`, and `risk`.
4. **Never auto-promote** discovered tasks to `ready`. They enter a triage queue the user reviews
   at batch boundaries, milestone report time, or the DONE-phase triage step (see DONE step 1.3).

**Rationalization resistance — STOP and file a bundle if you catch yourself thinking:**

| Rationalization | Reality |
|-|-|
| "This test was already broken — not our problem." | Nothing is pre-existing. If it fails on this branch, YOUR work owns it. File a bundle and document the diagnosis. |
| "The red-team found a latent bug but it's out of scope — ignore it." | Out-of-scope means *file it*, not *forget it*. A discovered bundle takes 30 seconds and preserves the finding. |
| "I'll just `t.Skip()` this test to stay green and come back later." | Later never comes. Skipping a test without a discovered bundle is a workflow violation. |
| "Context is tight — I'll skip filing and remember it." | You will not remember. Context pressure is the exact moment when filing matters most and costs least. |
| "This is a convention drift, not a bug — doesn't need a task." | Convention drift compounds. File it even if priority is low. |

A single `discovered_from` bundle is cheaper than a post-mortem about silently disavowed work.

**Token and Timing Tracking:**

After each subagent Task completes, extract `total_tokens` and `duration_ms` from the Task result.
Track cumulatively at three levels:

| Level | What's tracked | When reported |
|-------|---------------|--------------|
| Per-task | Sum of implementer + task-critic + red-teamer | TASK_COMPLETE event (also written to bundle frontmatter `token_cost_usd` / `duration_ms`) |
| Per-milestone | Sum of all tasks in the milestone | MILESTONE_COMPLETE event |
| Grand total | Sum of all milestones + overhead (research, planning, validation) | SESSION_COMPLETE event |

Include token/duration data in batch reports so the user can see resource consumption.

**Budget Enforcement** (when `token_budget_usd` is set in FEATURE.md):

After each TASK_COMPLETE, update `token_spent_estimate_usd` in FEATURE.md frontmatter.
Use approximate cost: `tokens * $0.000015` for Opus, `$0.000003` for Sonnet, `$0.0000008` for Haiku.
These are rough estimates — precision matters less than having a running total.

| Threshold | Action |
|-|-|
| 80% of budget | Append `BUDGET_WARNING` event to events.jsonl, include in batch report |
| 100% of budget | **Interactive**: pause, ask user to increase budget or stop gracefully at current milestone |
| 100% of budget | **Autonomous**: complete the current task, then stop. Do not start the next task. Append `BUDGET_EXHAUSTED` event. |

The budget check runs before dispatching each task — not after.
If the remaining budget is less than the estimated cost of the next task
(based on scope: ~$0.05 for Low risk, ~$0.15 for Medium, ~$0.30 for High),
surface the budget constraint before starting.

**Batch reporting** (after every batch or parallel round):

Every report MUST include the same six fields — discoveries are not optional, they are the
mechanism that makes the work-disavowal resistance visible to the user.

Required fields: **tasks completed**, **test status**, **discovered bundles this batch**,
**tokens**, **cost (USD)**, **duration**.

- **Autonomous — one-line format** (emitted at every `MILESTONE_COMPLETE`):

  ```
  Milestone M-XXX complete (<name>). Tasks: <done>/<total>. Tests: <pass>/<fail>. Discovered: <N>. Tokens: <X>k. Cost: $<Y>. Duration: <Z>s. Next: M-YYY.
  ```

  `Discovered: 0` when nothing new was filed this batch — always print the field so its absence
  is informative.

- **Interactive — structured block** (presented between batches):

  ```
  ## Batch Report — M-XXX

  Tasks: T-001, T-002, T-003 (3/3 complete)
  Tests: 158 pass / 0 fail (baseline +16)
  Tokens: 99.7k    Cost: $1.49    Duration: 6m 35s

  Discovered this batch:
  - T-DISC-001 (from T-002, Medium): <summary>
  - T-DISC-002 (from T-003, Low): <summary>

  Deviations: A1 applied (rate limiter needs Redis — see PLAN.md Amendments)

  Next: M-002 (Protected Routes). Continue?
  ```

  When nothing was discovered this batch, replace the Discovered section with
  `Discovered this batch: none`. Present an `ask_question` with the usual options:
  continue / adjust / review code / stop.

At milestone boundary (all tasks in milestone complete + tests pass):
- Run `/atcommit` to organize ALL accumulated changes into atomic commits grouped by concept
- `/atcommit` builds dependency graphs and groups files that belong together (e.g., package + tests, wiring + config)
- Typical result: 3-5 commits per feature instead of one per task
- Append `MILESTONE_COMPLETE` event to events.jsonl with milestone totals and commit count
- **Codex Milestone Review (if available):** Run `Skill(skill="codex:review", args="--wait --base <milestone_base_ref>")` on milestone changes. Critical findings → implementer fixes before next milestone. Others → logged as `CODEX_REVIEW` event.

**Mid-batch stop conditions**: missing dependencies, systemic test failures,
unclear instructions, repeated verification failures,
or discoveries that invalidate the plan's assumptions.

**Structured Deviation Handling:**

When an implementer or reviewer reports that something doesn't match the plan's assumptions,
classify the deviation by severity and handle accordingly:

| Severity | Detection | Handling |
|----------|-----------|---------|
| **Minor** — wrong assumption, step needs adjusting, small addition | Implementer says "this won't work because..." or "this already exists" or reviewer flags plan misalignment as justified | **Interactive**: propose specific PLAN.md edit, show before/after, ask user approval via `ask_question` before writing. **Autonomous**: log rationale in Decisions Made, apply edit, continue. |
| **Major** — wrong approach, missing phase, scope change, fundamental rethink | Implementer reports approach is infeasible, or discovery invalidates multiple downstream tasks | **Both modes**: stop the current batch, append a `DEVIATION_MAJOR` event to events.jsonl with evidence, present the issue to the user. Recommend re-planning (return to PLAN_DRAFT). |

**Plan Amendment Protocol** (applies to both severity levels):

Deviations that change assumptions feed back into PLAN.md — not just into events.jsonl.
A resuming agent reads the current plan, not the original plan plus unstructured deviation logs.

1. Append a `DEVIATION_MINOR` or `DEVIATION_MAJOR` event to events.jsonl with trigger, evidence, and affected tasks
2. Update affected task contracts in PLAN.md:
   - Modify preconditions/postconditions of the affected task
   - Re-validate downstream task preconditions — if a downstream task assumed what changed, update its contract too
   - Add an entry to the `## Plan Amendments` section with trigger, changes, and downstream impact
3. Update FEATURE.md: set `last_plan_amendment` to current timestamp, log in Surprises and Discoveries
4. Regenerate SNAPSHOT.md to reflect the amended plan

After resolving a deviation, re-read the latest PLAN.md before resuming — it may have changed.
Log all deviations as events in events.jsonl and in the Surprises and Discoveries section of FEATURE.md.

**TDD-first execution for behavior-changing tasks:**
When a task introduces or changes behavior, follow this exact sequence — no exceptions:
1. Write the failing test (complete test code, not a placeholder)
2. Run the test — verify it FAILS for the expected reason (not a syntax error)
3. Write minimal implementation to make the test pass
4. Run the test — verify it PASSES and all other tests still pass
5. Do NOT commit — changes accumulate until the milestone boundary

**Red flags — STOP and restart the task with TDD if you catch yourself:**
- Writing implementation code before the test
- Skipping the "verify failure" step
- Writing a test that passes immediately (you're testing existing behavior, not new behavior)
- Rationalizing "this is too simple to test" or "I'll add the test after"
- Running `git commit` or `/atcommit` after a single task (commits happen at milestone boundaries only)

**When TDD does not apply:** Config-only changes, documentation updates, refactoring that preserves existing behavior (with existing test coverage). Use direct step structure: edit → verify (do NOT commit — wait for milestone boundary).

**Milestone boundary commits:**
When all tasks in a milestone are complete and tests pass, the orchestrator (NOT the implementer) runs `/atcommit` to organize all accumulated changes into atomic commits. `/atcommit` analyzes file dependencies and groups changes by concept (e.g., a complete package with tests, an integration layer, configuration + wiring). This produces 3-5 well-organized commits for a typical feature instead of one commit per task.

**Drift Measurement** (deterministic — at each milestone boundary after committing):

Compare plan vs reality:

| Check | Detection | Threshold | Action |
|-------|-----------|-----------|--------|
| Unplanned files | `git diff --name-only <base_ref>..HEAD` vs File Impact Map | >20% unplanned | Log warning, review with user |
| Test ratio | New test files / New source files | <0.3 | Log warning, may need more tests |
| Scope drift | Count of tasks marked "Extra" in spec reviews | >2 per milestone | Log DEVIATION_MINOR |
| New public APIs | Grep for exported functions not in plan | Any unplanned | Log for review |

Log as event:
`{"ts":"<ISO8601>","type":"DRIFT_CHECK","actor":"orchestrator","milestone":"M-XXX","planned_files":N,"actual_files":N,"unplanned":[...],"test_ratio":N}`

**Never:**
- Dispatch multiple implementer subagents in parallel (causes conflicts)
- Skip the adversarial review loop or accept without a proof-based verdict
- Proceed to the next task while the adversarial loop has unresolved critical flaws
- Let implementer subagents run git commit — only the orchestrator commits at milestone boundaries
- Accept a task-critic verdict that lacks proof for its critical flaws — send it back

## VALIDATE Phase
- Spawn `validator` to run automated checks AND quality assessment
- Output: Validation report with test results, acceptance evidence, and quality scorecard (1-5 per dimension)
- Quality gate: all dimensions must score >= 3/5 to pass
- **Codex Adversarial Gate (if available):** After validator passes, run `Skill(skill="codex:adversarial-review", args="--wait --scope branch")`. Critical findings → loop to EXECUTE. Append to VALIDATION.md under `## Codex Adversarial Review`.
- May loop back to EXECUTE for test failures, quality gate failures, or Critical Codex findings
- **Interactive**: Present validation results and quality scorecard, ask user before creating PR
- **Autonomous**: Auto-proceed to DONE if validation and quality gate pass

## DONE Phase

Finalization sequence — each step depends on the previous one succeeding.

### 1. Outcomes & Retrospective
- Write Outcomes & Retrospective to FEATURE.md

### 1.3 Discovered Task Triage

Every `tasks/T-DISC-*.md` bundle that is still `status: discovered` MUST be dispositioned
before the feature closes. Discovery without disposition re-introduces the work-disavowal
failure mode that Milestone 1 was built to prevent.

1. Enumerate pending bundles:
   `Grep(pattern="^status: discovered$", path="tasks/", output_mode="files_with_matches")`
2. For each bundle, read frontmatter + body and present a triage prompt.

**Interactive mode** — one `ask_question` per bundle:

```
ask_question(
  header: "Triage T-DISC-<NNN>",
  question: "<one-line summary from bundle> (discovered from <T-XXX>, risk: <level>). Disposition?",
  options: [
    "File as external issue" -- Create GitHub issue via gh, record URL, set status: skipped,
    "Keep as backlog" -- Leave status: discovered for a future /do session to pick up,
    "Discard with rationale" -- Not a real defect; capture why and set status: skipped
  ]
)
```

Bundle updates per choice:

| Choice | Bundle frontmatter update | Body update |
|-|-|-|
| File as external issue | `status: skipped`, `external_issue: <URL>` | Append "Filed as <URL> on <ISO ts>" |
| Keep as backlog | no change (`status: discovered`) | none |
| Discard with rationale | `status: skipped`, `discard_reason: <one-liner>` | Append the full rationale |

For "File as external issue":

```bash
gh issue create --title "<bundle summary>" --body "Discovered during /do <feature-name>. See T-DISC-<NNN> body for diagnosis.

<bundle body contents>

Originating feature: <short-name>
Originating task: <discovered_from>"
```

Record the returned URL in the bundle frontmatter.

**Autonomous mode:** Default all pending bundles to "Keep as backlog" (no destructive action
without user consent). Surface the count in the completion report so the user can triage later.

3. Update FEATURE.md Progress section for every dispositioned bundle (see state-file-schema.md
   Progress conventions for the marker symbols).
4. Append one `TRIAGE_COMPLETE` event to events.jsonl summarizing the dispositions:

```json
{"ts":"<ISO8601>","type":"TRIAGE_COMPLETE","actor":"orchestrator","counts":{"filed":N,"backlog":N,"discarded":N}}
```

**If a bundle's rightful home is the current feature (not a follow-up),** the correct path is
*not* to fold it in during DONE. Answer "Keep as backlog", finish DONE, then start a fresh
`/do` invocation that resumes the bundle — this preserves the one-feature-one-PR boundary.

### 1.5 Documentation Update (Optional)

Check if the feature affects user-facing behavior:
- If API changes: update API docs
- If new CLI flags: update README or help text
- If behavior changes: update CHANGELOG.md entry

If the plan included doc tasks, they were already done in EXECUTE.
This step catches documentation that was missed by the plan.
Skip if the feature is purely internal (no user-facing changes).

### 2. Final Test Suite
- Run the full test suite one final time to confirm everything passes
- If tests fail: loop back to EXECUTE to fix. Do NOT proceed with uncommitted broken code.

### 3. Commit Remaining Changes (`/atcommit`)
- Run `/atcommit` to organize any remaining uncommitted changes into atomic commits
- This catches stragglers missed at milestone boundaries (validation fixes, retrospective updates, etc.)
- If nothing to commit, skip to step 4

### 4. Push to Remote
- Push all commits to the remote branch: `git push`
- If the branch has no upstream: `git push -u origin HEAD`
- If push fails: report the error. Do NOT force-push. Let the user decide.

### 5. Create Pull Request (`/pr`)
- **Interactive**: Present completion options before creating the PR:
  - Create PR as draft (Recommended)
  - Create PR as non-draft (`--open`)
  - Keep branch without PR
  - Discard work
- **Autonomous**: Create PR automatically as draft via `/pr` skill
- Record the PR URL in FEATURE.md frontmatter

### 6. Validate and Fix PR (`/pr-fix`)
- Run `/pr-fix` to check for review feedback from automated reviewers (Greptile, Codex, etc.)
- `/pr-fix` handles: fetching review threads, categorizing feedback, applying fixes, replying to threads, committing, pushing, and monitoring CI
- **Interactive**: `/pr-fix` will ask the user how to handle disagreements and whether to watch CI
- **Autonomous**: `/pr-fix` runs with "Fix all" and "Yes — watch and fix" defaults
- If `/pr-fix` produces additional commits, they are automatically pushed
- Loop `/pr-fix` up to 2 times if new automated review feedback arrives after fixes

### 7. Report and Archive
- Report final outcome to user: PR URL, commit count, CI status, review thread status
- Archive run state (mark `current_phase: DONE` in FEATURE.md)

### 7.5. Extract Session Learnings
- Dispatch `memory-extractor` (haiku) with events.jsonl + Decisions Made + Surprises sections
- Extracts reusable learnings (conventions, corrections, gotchas) into knowledge files
- Runs after archival — cheap post-session knowledge capture
- Dispatch with `run_in_background: true` — this is a non-blocking post-session task that should not delay completion reporting

**Early learning extraction** (in addition to DONE):
- At DEVIATION_MAJOR events — significant discoveries worth capturing immediately
- At session suspension (user says "stop here" during EXECUTE) — partial learnings are better than lost learnings
- At VALIDATE failures that loop back to EXECUTE — captures what went wrong
