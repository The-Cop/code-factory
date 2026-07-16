---
name: "openspec-apply-change"
description: "Use when the user wants to implement an OpenSpec change, apply OPSX tasks, continue OpenSpec implementation work, or work through tasks from `openspec/changes/<name>/tasks.md`. Triggers include openspec apply, opsx apply, implement openspec change, continue OpenSpec change, and apply change."
---

# OpenSpec Apply Change

Announce: "I'm using the openspec-apply-change skill to implement an OpenSpec change."

Implement pending tasks from an OpenSpec change while keeping the task artifact current.

## Step 1: Select the Change

Parse the user's invocation prompt for a change name.

If no name was provided:

1. Infer the change only when the conversation clearly names one.
2. Otherwise run `openspec list --json`.
3. Auto-select only when exactly one active change exists.
4. If multiple active changes exist, ask the user which one to apply.

Announce `Using change: <name>` before reading artifacts.

## Step 2: Load OpenSpec Context

Run:

```bash
openspec status --change "<name>" --json
openspec instructions apply --change "<name>" --json
```

Use the instruction output as the source of truth for:

- `schemaName`
- `contextFiles`
- total, completed, and remaining tasks
- current dynamic implementation instruction
- blocked or all-done state

If the state is `blocked`, report the missing artifacts and stop.
If the state is `all_done`, report completion and suggest `openspec-archive-change`.

## Step 3: Read Required Files

Read every file listed in `contextFiles`.
Do not assume a fixed schema layout.

Create a concise implementation checklist from the pending tasks.
Preserve the task wording from the artifact so progress updates map back cleanly.

## Step 4: Implement Pending Tasks

Work through pending tasks in order unless dependencies require a different order.

For each task:

1. State the task being implemented.
2. Make the minimal scoped code or documentation changes required.
3. Run the relevant focused validation for that task.
4. Mark the task complete in the task artifact by changing `- [ ]` to `- [x]`.
5. Continue until all tasks are complete or a blocker is reached.

When implementation evidence contradicts a planned path or assumption, classify the deviation before editing further:

- **Reversible and behavior-preserving**: the intended scope and observable behavior remain unchanged, and the choice is easy to undo. Select the easiest-to-reverse valid option. Update every affected canonical proposal, design, spec, or task artifact with the evidence and rationale. Run focused validation proving the substitute preserves the contract, record the command and result in the affected canonical task or design artifact, then continue from the updated artifacts.
- **Behavior-changing, irreversible, or scope-expanding**: the choice changes user-visible or system-visible behavior, commits to a difficult migration or contract, or adds work outside the approved scope. Stop at a safe checkpoint. Do not change canonical artifacts, implementation, or completion markers for the disputed work until the user gives direction.

Do not create a separate implementation-notes file.
Record deviations where a future apply or archive run will read them: update the affected canonical artifacts and keep task wording current.
After a reversible deviation, re-read the changed artifacts before resuming and include the focused validation evidence in the progress report.

Pause and ask if a task is ambiguous, contradicts another artifact, or reveals a design issue that cannot be resolved as behavior-preserving and reversible.

## Step 5: Report Progress

At completion or pause, report:

- Change name and schema.
- Tasks completed this session.
- Overall task progress.
- Validation performed.
- Remaining blocker, if any.

If every task is complete, suggest `openspec-archive-change`.

## Error Handling

| Failure | Resolution |
|-|-|
| No active change can be selected | Run `openspec list --json` and ask the user to choose. |
| Apply instructions report `blocked` | Report the missing artifacts and stop before coding. |
| Task contradicts artifacts | Classify the contradiction first: follow the reversible path without a confirmation round-trip, or pause for user direction when behavior, scope, or irreversibility is affected. |
| Deviation preserves behavior and is reversible | Update affected canonical artifacts with evidence and rationale, validate the substitute, then continue. |
| Deviation changes behavior, scope, or an irreversible decision | Stop at a safe checkpoint without marking the task complete and request user direction. |
| Validation fails | Fix the failure before marking the task complete. |
| User interrupts | Leave completed task checkboxes accurate and report the current progress. |
