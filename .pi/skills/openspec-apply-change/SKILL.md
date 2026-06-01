---
name: "openspec-apply-change"
description: "Use when the user wants to implement an OpenSpec change, apply OPSX tasks, continue OpenSpec implementation work, or work through tasks from `openspec/changes/<name>/tasks.md`. Triggers include openspec apply, opsx apply, implement openspec change, continue OpenSpec change, and apply change."
---

# OpenSpec Apply Change

Announce: "I'm using the openspec-apply-change skill to implement an OpenSpec change."

Implement pending tasks from an OpenSpec change while keeping the task artifact current.

## Step 1: Select the Change

Parse `$ARGUMENTS` for a change name.

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

Pause and ask if a task is ambiguous, contradicts another artifact, or reveals a design issue.
When implementation changes the intended behavior, update the OpenSpec artifacts before continuing.

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
| Task contradicts artifacts | Pause, explain the contradiction, and update artifacts after user confirmation. |
| Validation fails | Fix the failure before marking the task complete. |
| User interrupts | Leave completed task checkboxes accurate and report the current progress. |
