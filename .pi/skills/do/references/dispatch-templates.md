# Dispatch Templates

Task dispatch prompt templates for the `/do` outer loop.
All dispatches use `agent = "orchestrator"`.

## Phase Orchestrator (non-EXECUTE)

Used for REFINE, RESEARCH, PLAN_DRAFT, PLAN_REVIEW, VALIDATE, DONE.

```
subagent(
  agent = "orchestrator",
  description = "<phase>: <short-name>",
  task = "
<current_phase><PHASE_NAME></current_phase>
<state_path>~/docs/plans/do/<short-name>/FEATURE.md</state_path>
<repo_root><REPO_ROOT></repo_root>
<workdir_path><WORKDIR_PATH></workdir_path>
<interaction_mode><interactive|autonomous></interaction_mode>

<feature_request>
<the user's feature description — REFINE only; omitted for later phases>
</feature_request>

<phase_context>
<Phase-specific context from state files. See Context Payloads in phase-flow.md:
  REFINE: feature_request + brainstorm_context + hydrated_context
  RESEARCH: FEATURE.md refined spec section
  PLAN_DRAFT: FEATURE.md spec + criteria, full RESEARCH.md, full CONVENTIONS.md
  PLAN_REVIEW: full PLAN.md, full CONVENTIONS.md, FEATURE.md criteria (reviewer); full RESEARCH.md (red-teamer only)
  VALIDATE: FEATURE.md criteria, PLAN.md validation strategy, full CONVENTIONS.md, git diff output
  DONE: full FEATURE.md, VALIDATION.md, events.jsonl summary>
</phase_context>

<state_drift>
<discrepancies from state-reality verification — resume mode only>
</state_drift>

<task>
Execute the <PHASE_NAME> phase. Work from <WORKDIR_PATH>.
State files are in ~/docs/plans/do/<short-name>/.
Write phase outputs to the appropriate state file.
Update FEATURE.md phase_status when complete (approved, blocked, or in_review).
Do NOT advance current_phase — the outer loop handles phase transitions.
</task>

<workflow_rules><WORKFLOW_RULES content></workflow_rules>
"
)
```

## Milestone Orchestrator (EXECUTE)

Dispatched once per ready milestone (or per parallel group with no file overlap).

```
subagent(
  agent = "orchestrator",
  description = "Execute M-XXX: <milestone-name>",
  task = "
<current_phase>EXECUTE</current_phase>
<milestone>M-XXX</milestone>
<state_path>~/docs/plans/do/<short-name>/FEATURE.md</state_path>
<workdir_path><WORKDIR_PATH></workdir_path>
<interaction_mode><interactive|autonomous></interaction_mode>

<task_bundles>
<Full contents of each TASK-XXX.md file for this milestone>
</task_bundles>

<conventions>
<Full CONVENTIONS.md — immutable project conventions for this feature>
</conventions>

<resume_snapshot>
<Full SNAPSHOT.md — task-scoped context (decisions, conventions, completed work summary,
active deviations, plan amendments, budget status). Replaces thin context slices —
gives the cold-start orchestrator everything it needs.>
</resume_snapshot>

<session_tail>
<Last 10 events from events.jsonl (JSONL), or empty if first milestone>
</session_tail>

<task>
Execute milestone M-XXX. Process each task sequentially using the task bundles.
For each task:
1. Verify preconditions from the task bundle before starting — if any fail, mark task as blocked
2. Dispatch implementer → shift-left → adversarial loop → update task bundle
3. Verify postconditions after completion
4. Update token_spent_estimate_usd in FEATURE.md (check budget if set)
At milestone boundary: run /atcommit for atomic commits.
If deviations occur: follow the Plan Amendment Protocol (update PLAN.md task contracts, not just events.jsonl).
If the implementer or a reviewer surfaces an issue outside the task contract, file a `discovered_from` bundle
(Discovery Capture Protocol in phase-flow.md).
Append TASK_COMPLETE and MILESTONE_COMPLETE events to events.jsonl (each with `actor: orchestrator`).
Update task bundle frontmatter (status, verdict, adversarial_rounds, commit_sha).
Update FEATURE.md Progress section with completed tasks and commit SHAs.
Do NOT advance current_phase — the outer loop handles transitions.
</task>

<workflow_rules><WORKFLOW_RULES content></workflow_rules>
"
)
```

**Parallel dispatch:** when multiple ready milestones have no file overlap,
dispatch in a single message (multiple Task calls).
After all return, read updated state and proceed to the next group.

## Bundle Generation (BUNDLE_GENERATION)

Dispatched once between PLAN_REVIEW approval and EXECUTE entry.
Skip if `tasks/` already exists (resume scenario).

```
subagent(
  agent = "orchestrator",
  description = "Generate task bundles: <short-name>",
  task = "
<current_phase>BUNDLE_GENERATION</current_phase>
<state_path>~/docs/plans/do/<short-name>/FEATURE.md</state_path>
<workdir_path><WORKDIR_PATH></workdir_path>

<plan_content><Full PLAN.md content></plan_content>
<research_context><Full RESEARCH.md content></research_context>
<feature_spec><FEATURE.md acceptance criteria section></feature_spec>
<conventions><Full CONVENTIONS.md content></conventions>

<task>
Generate individual task execution bundles in ~/docs/plans/do/<short-name>/tasks/.
For each task in PLAN.md, create TASK-XXX.md using the bundle schema from state-file-schema.md:
1. Extract full task description, steps, and acceptance criteria from PLAN.md
2. Extract preconditions/postconditions — convert to verifiable checks with commands
3. Pre-compute the task contract (concrete pass/fail criteria including mandatory invariants)
4. Read relevant codebase files from <workdir_path> and extract architectural context
5. Find pattern references with actual code snippets (file:line citations)
6. Set max_adversarial_rounds based on risk (Low=1, Medium=2, High=3)
7. Include verification commands with expected output
8. Summarize prior task outputs for tasks with dependencies

Each bundle must be self-contained — an implementer reading only that file plus CONVENTIONS.md
should have everything needed to execute the task without reading PLAN.md or RESEARCH.md.
Include relevant conventions from CONVENTIONS.md in each bundle's Architectural Context section.
</task>
"
)
```

After generation, verify the task file count matches the task count in PLAN.md.

## Brainstormer (Pre-REFINE, Optional)

Dispatched from Step 4d of SKILL.md when the user chooses "Brainstorm first".

```
subagent(
  agent = "brainstormer",
  description = "Brainstorm before /do: <slug>",
  task = "
<brainstorm_file><path>~/docs/brainstorms/<slug>.md</path><content><full file content></content></brainstorm_file>
<idea><user's feature description></idea>
<today><TODAY></today>
<task>
Start a new brainstorm. The file has been created with the initial idea.
Analyze whether the idea is problem-shaped or solution-shaped, then begin the diagnostic progression.
Ask one question at a time. Update the brainstorm file after each exchange.
This brainstorm feeds into a /do workflow — the sharpened problem will inform the REFINE phase.
</task>
"
)
```

After completion, read `~/docs/brainstorms/<slug>.md` and pass the content as
`<brainstorm_context>` in the subsequent REFINE dispatch.

## Status Mode (Read-only)

If the user asks for status without resuming, dispatch with a read-only instruction:

```
<task>
Report status without making changes. Read FEATURE.md and report
current phase, progress percentage, last checkpoint, and blockers.
Do not modify state or code.
</task>
```
