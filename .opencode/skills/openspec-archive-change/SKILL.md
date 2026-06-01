---
name: openspec-archive-change
description: Use when the user wants to archive or finalize an OpenSpec change after implementation, merge OpenSpec delta specs into main specs, or complete an OPSX workflow. Triggers include openspec archive, opsx archive, archive OpenSpec change, and finalize OpenSpec change.
argument-hint: "[change name] [--yes] [--skip-specs]"
user-invocable: true
allowed-tools: Read, Glob, Grep, Bash(openspec:*), AskUserQuestion
---

# OpenSpec Archive Change

Announce: "I'm using the openspec-archive-change skill to archive an OpenSpec change."

Archive a completed OpenSpec change using the OpenSpec CLI lifecycle command.

## Step 1: Select the Change

Parse `$ARGUMENTS` for a change name and optional OpenSpec archive flags.

If no change name was provided, run:

```bash
openspec list --json
```

Ask the user to choose from active changes.
Do not guess when multiple active changes exist.

## Step 2: Check Readiness

Run:

```bash
openspec status --change "<name>" --json
openspec instructions apply --change "<name>" --json
```

Report incomplete artifacts or tasks before archiving.
If work is incomplete, ask the user to confirm before continuing.

Run validation unless the user explicitly passed `--no-validate`:

```bash
openspec validate "<name>"
```

## Step 3: Archive

Archive with the CLI so spec merging and archive naming follow OpenSpec behavior:

```bash
openspec archive "<name>"
```

Pass through explicit user flags such as `--yes`, `--skip-specs`, or `--no-validate`.
Use `--yes` only when the user requested non-interactive archiving.

## Step 4: Report Outcome

Report:

- Change name.
- Archive command used.
- Whether specs were merged or skipped.
- Archive location if the CLI reports it.
- Any warnings about incomplete tasks or skipped validation.

## Error Handling

| Failure | Resolution |
|-|-|
| Multiple active changes exist | Ask the user to choose before archiving. |
| Incomplete tasks remain | Warn and ask for confirmation before proceeding. |
| Validation fails | Stop and report the validation failure unless the user explicitly requested `--no-validate`. |
| Archive command prompts unexpectedly | Pause and ask the user instead of assuming confirmation. |
| Archive target already exists | Report the conflicting archive path and leave the active change untouched. |
