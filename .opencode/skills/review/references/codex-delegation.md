# Codex Delegation

The `--codex` flag and the Codex half of `--claude-codex` delegate the PR review to the `codex:codex-rescue` subagent.
The subagent is a thin forwarder around the Codex companion runtime.
Its only job is to forward the prompt to Codex and return Codex's stdout verbatim.

## Invocation

```
Task(
  subagent_type = "codex:codex-rescue",
  description = "Codex PR review: #<PR_NUMBER>",
  prompt = <see template below>
)
```

Do not pass `--write`, `--background`, `--wait`, `--resume`, or `--fresh`.
The prompt's "Review only" opening tells the rescue subagent to omit `--write`.
Foreground (default) is correct for review.

## Prompt template

```
Review only — do not write, edit, or modify any files. Read-only analysis.

You are reviewing GitHub PR #<PR_NUMBER>: "<title>".

## PR Intent

<paste the 2-4 sentence intent statement extracted in Step 6, including any Uncertainty block>

## Refs

- Base ref: <baseRefName>
- Head ref: <headRefName>
- Head SHA: <PR_HEAD_SHA>
- Worktree (read-only): <WT_PATH>

You may read files under the worktree path for additional context, but do not modify anything.

## Review Framework

Apply all three levels per module:

1. Intent and scope — does the change advance the PR Intent? Scope creep? Missing pieces?
2. Logic and behavior — control flow, invariants, race conditions, edge cases, backward compatibility, error paths, interactions between old and new code.
3. Code quality and maintainability — duplication, dead code, abstractions, naming, error handling, security, performance, test quality.

Group findings into logical modules (not strictly directories).
One module entry per module.
Tag every finding with Level (Intent/Logic/Quality), Severity (Critical/Major/Minor), and Confidence (HIGH/MEDIUM/LOW).
Cite specific file:line locations for every finding.

## Enumeration discipline

The review is exhaustive, not curated.

- Do not cap findings.
  If a module has 30 minor issues, list 30 minor issues.
- Do not collapse repeated instances.
  If the same defect appears at five locations, write five rows with five locations.
- Do not produce a "top issues" or "key findings" digest.
  The findings table is the report.
- Apply each check independently.
  Different lenses catch different defects on the same code.
- For each check listed in the framework, either record at least one finding row
  or mark the check `✓ scanned` in the per-check audit table.
  Never leave a check unmarked.

After enumerating, re-read each changed file once more with the union of findings in mind.
Specifically scan for cross-file repeats, old/new code interactions, test gaps,
error wrapping and propagation, dead code, and magic values.
Append new findings to the same module table.

## Required Output Format

Use this markdown structure exactly:

### PR Intent
<restate intent — confirm or adjust based on what you found>

### File Coverage Checklist
| # | File | Module | Reviewed |
|---|------|--------|----------|
| 1 | ... | ... | ✓ |

Every changed file must appear and be marked ✓.

### Cross-cutting Observations
<interface changes, schema changes, security, performance — omit subsections that are empty>

### Module Reviews

#### Module: <name>
**Intent (this module):** ...
**Files reviewed:** `path:line-range`, ...
**Findings:** <table with columns Level | Severity | Confidence | Location | Issue | Why It Matters | Likely Impact | Best Fix>
**Per-check audit:** <table with columns Level | Check | Status, where Status is `✓ findings` or `✓ scanned` for every check in the three-level framework — never blank>
**Missing or Insufficient Tests:** ...
**Pre-merge Cleanup:** ...

(repeat per module)

### Verdict
**Approve / Request Changes / Comment** — <1-2 sentence rationale tied to PR Intent.>

## PR Diff

```diff
<paste the full output of `gh pr diff <PR_NUMBER>` here, unmodified>
```
```

## Pass-through rules

- Return Codex's stdout verbatim.
- Do not paraphrase, summarize, or add commentary before or after.
- If stdout is empty, treat that as a Codex failure (the rescue subagent returns nothing on failure).

## Fallback rules

| Failure mode | Action |
|--------------|--------|
| `command -v codex` returns non-zero | Warn: "Codex CLI not installed. Falling back to Claude review." Skip Codex delegation. |
| Codex subagent returns empty stdout | Report: "Codex review failed." In `--codex` mode, ask user if they want to retry with Claude. In `--claude-codex` mode, continue with Claude-only output and add the header note `Codex unavailable; Claude-only`. |
| Worktree creation failed | Pass `Worktree: diff-only fallback` to Codex and explain in the prompt that no live file access is available. |

## Why this pattern

- The `codex:codex-rescue` subagent is the only sanctioned entry point for arbitrary Codex prompts from another skill.
- The `/codex:review` command targets local git state but cannot be invoked from another skill's runtime; replicating its logic via the subagent gives equivalent capability.
- Read-only enforcement comes from prompt content (the rescue subagent uses `--write` only when the request implies edits).
