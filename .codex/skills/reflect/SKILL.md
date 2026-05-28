---
name: "reflect"
description: "Use when the user wants to capture session learnings and update knowledge files, review pending learnings from previous sessions, or manually trigger a session reflection. Triggers: \"reflect\", \"capture learnings\", \"update agents.md\", \"review pending learnings\", \"what did we learn\", or at session end via Stop hook."
---

# Session Reflection

Announce: "I'm using the /reflect skill to capture session learnings and update knowledge files."

## Overview

Extracts actionable knowledge from the current session — conventions, corrections, patterns, and gotchas —
and updates the repo's knowledge files.
Uses confidence-based routing: high-confidence learnings are auto-applied,
medium-confidence ones are queued for human review.

## Reference Documents

| Reference | When to load |
|-----------|-------------|
| [extraction-rules.md](references/extraction-rules.md) | Signal definitions, confidence thresholds, target selection, deduplication rules. Shared with `memory-extractor` agent. |

## Step 1: Determine Mode

Parse the user's invocation prompt to select mode:

| Arguments | Mode |
|-----------|------|
| `--review` | **Review mode** — process pending learnings queue |
| Anything else or empty | **Extract mode** — analyze current session |

## Step 2A: Extract Mode (default)

### 2A.1: Locate Knowledge Files

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
AGENTS_MD=$REPO_ROOT/AGENTS.md
CLAUDE_MD=$REPO_ROOT/CLAUDE.md
CLAUDE_LOCAL_MD=$REPO_ROOT/CLAUDE.local.md
RULES_DIR=$REPO_ROOT/.claude/rules
# Resolve project memory directory (Claude Code encodes repo path as slash-to-dash)
PROJECT_DIR=$(ls -d ~/.claude/projects/*"$(basename "$REPO_ROOT")"* 2>/dev/null | head -1)
MEMORY_MD=$PROJECT_DIR/memory/MEMORY.md
PENDING_FILE=$PROJECT_DIR/pending-learnings.md
```

If `PROJECT_DIR` is empty, fall back to searching `~/.claude/projects/` for a directory containing `memory/MEMORY.md`.

Read all knowledge files to understand current content.
Also scan `$RULES_DIR/*.md` if the directory exists — these are scoped rule files.

### 2A.2: Analyze Session

Read [extraction-rules.md](references/extraction-rules.md) for the full signal definitions, confidence ranges, and deduplication rules.

Review the conversation history for learning signals: corrections, conventions, patterns, gotchas, and discoveries.
Score each learning using the confidence thresholds from the reference.

### 2A.3: Deduplicate

For each extracted learning, search the knowledge files using Grep per the deduplication rules in extraction-rules.md.

### 2A.4: Route by Confidence

Route each learning using the confidence thresholds from extraction-rules.md.
Use the target file selection rules from the same reference.

**High confidence (≥ 0.8) — auto-apply:**

1. Identify the correct section in the target file (or create a new section if needed)
2. Append the learning as a concise imperative bullet point
3. Use the Edit tool — never restructure or reorganize the file
4. Follow the writing rules from extraction-rules.md
5. Report: "Auto-applied: [learning] → [file]:[section]"

**Medium confidence (0.5–0.79) — queue for review:**
1. Append to `$PENDING_FILE` in this format:

```markdown
## Pending Learning — [date]

- **Learning**: [concise imperative bullet]
- **Confidence**: [score]
- **Target**: [AGENTS.md|MEMORY.md|CLAUDE.md]
- **Section**: [target section name]
- **Evidence**: [brief quote or reference from session]
- **Category**: [correction|convention|pattern|gotcha|discovery]

---
```

2. Report: "Queued for review: [learning] (confidence: [score])"

**Low confidence (< 0.5):**

Discard silently. Do not report discarded learnings unless the user explicitly asks.

### 2A.5: Self-Improvement Analysis

After extracting learnings, analyze the conversation for self-improvement findings.
If the session was short or routine with nothing notable, say "Nothing to improve" and skip to 2A.6.

**Finding categories:**

| Category | What to look for |
|-|-|
| **Skill gap** | Things the agent struggled with, got wrong, or needed multiple attempts |
| **Friction** | Repeated manual steps, things the user had to ask for explicitly that should have been automatic |
| **Knowledge** | Facts about the project, preferences, or setup that the agent didn't know but should have |
| **Automation** | Repetitive patterns that could become skills, hooks, or scripts |

**For each finding, determine the action:**

| Action | When to use |
|-|-|
| CLAUDE.md edit | Permanent project convention or boundary rule |
| Rules file | Topic-specific instruction scoped to certain file types — create or update `.claude/rules/<topic>.md` with `paths:` frontmatter |
| Auto memory | Pattern or insight for future sessions |
| Skill/Hook spec | Document a new skill or hook specification for later implementation |
| CLAUDE.local.md | Personal WIP context, local URLs, sandbox credentials |

**Auto-apply all actionable findings** — do not ask for approval on each one.
Apply the changes, then include them in the summary.

### 2A.6: Summary

Present a summary table:

```markdown
## Session Reflection Summary

### Auto-Applied Learnings
| Learning | Target | Section |
|-|-|-|
| ... | ... | ... |

### Queued for Review
| Learning | Confidence | Target |
|-|-|-|
| ... | ... | ... |

### Self-Improvement Findings
| Finding | Category | Action |
|-|-|-|
| ... | ... | ... |

(or "Nothing to improve" if session was routine)

### Stats
- Signals analyzed: N
- Auto-applied: N
- Queued: N
- Duplicates skipped: N
- Discarded (low confidence): N
- Self-improvement findings: N applied
```

## Step 2B: Review Mode (`--review`)

### 2B.1: Load Pending Learnings

Read `$PENDING_FILE`. If it doesn't exist or is empty:
- Report: "No pending learnings to review."
- Exit.

### 2B.2: Present for Review

For each pending learning, present it to the user with `an interactive prompt`:

**Pause and ask the user. Wait for their answer before proceeding.**

> **Learning** -- [learning text]\nConfidence: [score] | Target: [file] | Evidence: [evidence]
>
> - **Apply** -- Add this learning to the target file
> - **Edit** -- Modify before applying
> - **Skip** -- Keep in queue for later
> - **Reject** -- Remove from queue permanently

### 2B.3: Process Decisions

| Decision | Action |
|----------|--------|
| Apply | Edit the target file to append the learning, then remove from queue |
| Edit | Ask user for revised text, then apply the revision and remove from queue |
| Skip | Leave in queue, move to next |
| Reject | Remove from queue, move to next |

### 2B.4: Cleanup

After processing all items:
- Rewrite `$PENDING_FILE` with only skipped items
- If no items remain, delete the file
- Report summary: N applied, N skipped, N rejected

## Error Handling

| Error | Action |
|-------|--------|
| Knowledge file not found | Create it with a header section, then proceed |
| Pending file not found (review mode) | Report "No pending learnings" and exit |
| Edit conflict (content changed since read) | Re-read the file and retry the edit once |
| No learnings extracted | Report "No actionable learnings found in this session" |
| Permission denied on file write | Report the error and queue the learning to pending instead |
