# Codex Delegation

The `--codex` flag and the Codex half of `--claude-codex` delegate the PR review to the `codex:codex-rescue` subagent.
The subagent is a thin forwarder around the Codex companion runtime.
Its only job is to forward the prompt to Codex and return Codex's stdout verbatim.

## Invocation

Run Codex in background mode and poll the job until it completes.
A foreground call dies at the default 120s Bash timeout because real PRs take 3-15+ minutes;
`--background` forks a detached worker and returns in seconds, then `/codex:status` and `/codex:result` recover the output.

### 1. Delegate (background)

```
Task(
  subagent_type = "codex:codex-rescue",
  description = "Codex PR review: #<PR_NUMBER>",
  prompt = "--background\n\n" + <see template below>
)
```

The literal first line `--background` followed by a blank line is a routing flag the `codex:codex-rescue` subagent strips before forwarding to `codex-companion task --background`.
Do not pass `--write`, `--wait`, `--resume`, or `--fresh`.
The prompt's "Review only" opening tells the rescue subagent to omit `--write`.

The Task returns within ~5-15 seconds with stdout matching:

```
<title> started in the background as <jobId>. Check /codex:status <jobId> for progress.
```

### 2. Parse jobId

Match the regex `started in the background as ([a-zA-Z0-9_-]+)\b` against the rescue stdout.
On no match, treat as a Codex failure (see Fallback rules).

### 3. Poll

Loop calling `Skill(skill="codex:status", args="<jobId> --wait --timeout-ms 100000")`.
Each call blocks server-side for up to 100s, staying under the 120s Bash kill, and returns as soon as the job reaches `completed`, `failed`, or `cancelled`.
Parse `Status:` with `/Status:\s+(queued|running|completed|failed|cancelled)\b/i`.

| Status | Action |
|--------|--------|
| `queued` | Continue polling. If 6 consecutive polls show `queued`, treat as a worker-launch failure. |
| `running` | Continue polling. Reset the queued-streak counter. |
| `completed` | Proceed to Fetch. |
| `failed` | Fallback. |
| `cancelled` | Fallback. |
| Unparseable | Fallback. |

Every 6 iterations (~10 min elapsed), emit one status line so the user knows the job is still progressing.
There is no upper iteration bound — keep polling until terminal state, the queued watchdog, or a parse failure.
Do **not** invoke `/codex:cancel` on timeout — leave the job alive so the user can recover the result.

### 4. Fetch

`Skill(skill="codex:result", args="<jobId>")`.
Pass the stdout through verbatim.

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
  The verbatim source is the output of `Skill(skill="codex:result", args="<jobId>")` once the job has terminal state `completed`.
- Do not paraphrase, summarize, or add commentary before or after.
- Do not fetch `/codex:result` for non-`completed` terminal states.
  The partial output is unreliable and the fallback header is more useful to the user.

## Fallback rules

| Failure mode | Action |
|--------------|--------|
| `command -v codex` returns non-zero | Warn: "Codex CLI not installed. Falling back to Claude review." Skip Codex delegation. |
| Rescue subagent returns empty stdout | Report: "Codex review failed (delegation)." |
| Rescue stdout missing jobId pattern | Report: "Codex review failed (no jobId)." |
| Codex job status `failed` | Report: "Codex job <jobId> failed." |
| Codex job status `cancelled` | Report: "Codex job <jobId> cancelled." |
| Codex job remains `queued` for 6 consecutive polls | Report: "Codex job <jobId> never started." |
| `/codex:status` output cannot be parsed | Report: "Codex status unparseable." |
| Worktree creation failed | Pass `Worktree: diff-only fallback` to Codex and explain in the prompt that no live file access is available. |

For every failure mode in `--codex` mode, ask the user via `AskUserQuestion` whether to retry with Claude.
In `--claude-codex` mode, continue with Claude-only output prefixed with `Codex unavailable; Claude-only`.

## Why this pattern

- The `codex:codex-rescue` subagent is the only sanctioned entry point for arbitrary Codex prompts from another skill.
- The `/codex:review` command targets local git state but cannot be invoked from another skill's runtime; replicating its logic via the subagent gives equivalent capability.
- Read-only enforcement comes from prompt content (the rescue subagent uses `--write` only when the request implies edits).
- Background mode is mandatory:
  Codex high-effort PR review routinely exceeds the default 120s Bash timeout.
  Foreground is reserved for short rescue prompts;
  PR review is not in that regime.
